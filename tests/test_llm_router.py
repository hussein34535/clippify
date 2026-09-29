"""
Offline tests for the LLM router (BYOK store, usage ledger, cascade).
No real network: llm_router._transport is monkeypatched per-provider.
"""

import json
import sqlite3

import pytest

import llm_router
import providers.ledger as ledger
import providers.store as store


# ---------------------------------------------------------------- helpers

def _make_transport(responses):
    """responses: url-substring → (status, text). Returns (transport, calls)."""
    calls = []

    def transport(method, url, *, headers=None, json_body=None, timeout=60):
        calls.append({"method": method, "url": url, "json": json_body})
        for sub, resp in responses.items():
            if sub in url:
                return resp
        return 404, '{"error":"unmatched"}'

    return transport, calls


def _ollama_ok(models=("qwen2.5vl:7b",)):
    tags = json.dumps({"models": [{"name": m} for m in models]})
    chat = json.dumps({"message": {"content": "ollama-answer"}})
    return {"/api/tags": (200, tags), "/api/chat": (200, chat)}


@pytest.fixture(autouse=True)
def isolated_env(tmp_path, monkeypatch):
    """Fresh providers.db + clean key envs per test."""
    monkeypatch.setenv("CLIPPIFY_PROVIDERS_DB", str(tmp_path / "providers.db"))
    for name in ("GEMMA_API_KEY", "GROQ_API_KEY", "PROVIDER_CAPS"):
        monkeypatch.delenv(name, raising=False)


# ---------------------------------------------------------------- store

def test_store_roundtrip_encrypted():
    store.set_key("gemini", "sk-secret-123")
    raw = sqlite3.connect(store.db_path()).execute(
        "SELECT key_enc FROM byok WHERE provider='gemini'"
    ).fetchone()[0]
    assert bytes(raw) != b"sk-secret-123"          # never plaintext
    assert b"secret" not in bytes(raw)
    assert store.get_key("gemini") == "sk-secret-123"


def test_store_delete_and_list():
    store.set_key("gemini", "k1")
    store.set_key("groq", "k2")
    assert sorted(store.list()) == ["gemini", "groq"]
    assert store.delete_key("gemini") is True
    assert store.delete_key("gemini") is False      # already gone
    assert store.list() == ["groq"]
    assert store.get_key("gemini") is None


# ---------------------------------------------------------------- ledger

def test_ledger_add_and_available():
    assert ledger.available("groq") == ledger.cap_for("groq") == 200
    ledger.add_used("groq")
    ledger.add_used("groq", 3)
    assert ledger.used_today("groq") == 4
    assert ledger.available("groq") == 196


def test_ledger_caps_override_via_env(monkeypatch):
    monkeypatch.setenv("PROVIDER_CAPS", json.dumps({"gemini_free": 10}))
    assert ledger.cap_for("gemini") == 10
    assert ledger.cap_for("groq") == 200            # untouched


def test_rollover_new_day_resets():
    assert ledger.available("gemini") == 1500        # ensures schema exists
    yesterday = "2020-01-01"
    conn = sqlite3.connect(store.db_path())
    conn.execute(
        "INSERT INTO daily(provider, day, used) VALUES('gemini', ?, 1500)", (yesterday,)
    )
    conn.commit()
    conn.close()
    assert ledger.used_today("gemini") == 0         # implicit UTC-day reset
    assert ledger.available("gemini") == 1500


def test_cooldown_expiry():
    ledger.set_cooldown("gemini", "2020-01-01T00:00:00+00:00")   # past
    assert ledger.cooldown_until("gemini") is None
    future = "2999-01-01T00:00:00+00:00"
    ledger.set_cooldown("gemini", future)
    assert ledger.cooldown_until("gemini") == future
    ledger.clear_cooldown("gemini")
    assert ledger.cooldown_until("gemini") is None


# ---------------------------------------------------------------- cascade

def test_success_increments_ledger(monkeypatch):
    transport, calls = _make_transport(_ollama_ok())
    monkeypatch.setattr(llm_router, "_transport", transport)
    out = llm_router.ask("hi")
    assert out["provider"] == "ollama"
    assert out["text"] == "ollama-answer"
    assert isinstance(out["latency_ms"], int)
    assert ledger.used_today("ollama") == 1
    assert len(calls) >= 2                          # tags + chat


def test_byok_precedence_over_shared(monkeypatch):
    store.set_key("gemini", "user-own-key")
    gem = (200, json.dumps(
        {"candidates": [{"content": {"parts": [{"text": "gemini-byok"}]}}]}))
    transport, calls = _make_transport({
        "generativelanguage": gem,
        **_ollama_ok(),
    })
    monkeypatch.setattr(llm_router, "_transport", transport)
    out = llm_router.ask("hi", prefer="auto")
    assert out["provider"] == "gemini"
    gem_calls = [c for c in calls if "generativelanguage" in c["url"]]
    assert len(gem_calls) == 1
    assert "key=user-own-key" in gem_calls[0]["url"]  # BYOK key, not shared env
    # BYOK won immediately → cascade never reached ollama/groq hops:
    assert not any("/api/chat" in c["url"] or "groq.com" in c["url"] for c in calls)


def test_local_pref_puts_ollama_first(monkeypatch):
    store.set_key("gemini", "user-key")
    transport, calls = _make_transport({
        "/api/chat": (200, json.dumps({"message": {"content": "local!"}})),
        "/api/tags": (200, json.dumps({"models": [{"name": "llama3"}]})),
        "generativelanguage": (200, "{}"),
    })
    monkeypatch.setattr(llm_router, "_transport", transport)
    out = llm_router.ask("hi", prefer="local")
    assert out["provider"] == "ollama"
    assert calls[0]["url"].endswith("/api/tags")    # reachability probe ran
    assert calls[1]["url"].endswith("/api/chat")


def test_429_sets_cooldown_and_falls_through(monkeypatch):
    transport, calls = _make_transport({
        "generativelanguage": (429, '{"error":"quota exceeded"}'),
        "groq.com": (200, json.dumps(
            {"choices": [{"message": {"content": "groq-answer"}}]})),
    })
    monkeypatch.setattr(llm_router, "_transport", transport)
    monkeypatch.setenv("GEMMA_API_KEY", "shared-gem")
    monkeypatch.setenv("GROQ_API_KEY", "shared-groq")
    out = llm_router.ask("hi")
    assert out["provider"] == "groq"
    until = ledger.cooldown_until("gemini")
    assert until is not None                        # cooled till UTC midnight
    assert "T00:00:00" in until
    assert ledger.used_today("groq") == 1


def test_capped_provider_skipped(monkeypatch):
    ledger.add_used("groq", ledger.cap_for("groq"))   # burn the free cap
    transport, _ = _make_transport({
        "groq.com": (200, json.dumps({"choices": []})),
    })
    monkeypatch.setattr(llm_router, "_transport", transport)
    monkeypatch.setenv("GROQ_API_KEY", "shared-groq")
    with pytest.raises(llm_router.RouterExhausted) as excinfo:
        llm_router.ask("hi")
    reasons = {r["provider"]: r["reason"] for r in excinfo.value.reasons}
    assert reasons["groq"] == "daily_cap_reached"
    # Cooled provider skipped too:
    ledger.set_cooldown("groq", "2999-01-01T00:00:00+00:00")
    with pytest.raises(llm_router.RouterExhausted) as excinfo2:
        llm_router.ask("hi")
    assert any("cooldown" in r["reason"] for r in excinfo2.value.reasons)


def test_exhausted_carries_reasons(monkeypatch):
    transport, _ = _make_transport({})              # everything unmatched → 404
    monkeypatch.setattr(llm_router, "_transport", transport)
    with pytest.raises(llm_router.RouterExhausted) as excinfo:
        llm_router.ask("hi")
    providers_hit = [r["provider"] for r in excinfo.value.reasons]
    assert "ollama" in providers_hit and "gemini" in providers_hit and "groq" in providers_hit
    assert all(r["reason"] for r in excinfo.value.reasons)


def test_vision_groq_skipped_gemini_inline_data(monkeypatch):
    captured = {}

    def transport(method, url, *, headers=None, json_body=None, timeout=60):
        captured.update(url=url, body=json_body)
        if "/api/tags" in url:
            return 200, json.dumps({"models": [{"name": "llama3"}]})  # no qwen2.5
        if "generativelanguage" in url:
            return 200, json.dumps(
                {"candidates": [{"content": {"parts": [{"text": "seen"}]}}]})
        return 404, ""

    monkeypatch.setattr(llm_router, "_transport", transport)
    monkeypatch.setenv("GEMMA_API_KEY", "shared-gem")
    frames = [base64_of(b"frame0"), base64_of(b"frame1")]
    out = llm_router.ask("what do you see", vision_frames=frames)
    assert out["provider"] == "gemini"
    inline = [p["inline_data"]["data"] for p in captured["body"]["contents"][0]["parts"]
              if "inline_data" in p]
    assert inline == frames                          # base64 frames passed through


def base64_of(raw: bytes) -> str:
    import base64
    return base64.b64encode(raw).decode()


def test_ask_json_tolerant_parse(monkeypatch):
    fenced = 'Sure!\n```json\n{"clips": [1, 2]}\n```'
    transport, _ = _make_transport({
        "/api/chat": (200, json.dumps({"message": {"content": fenced}})),
        "/api/tags": (200, json.dumps({"models": [{"name": "llama3"}]})),
    })
    monkeypatch.setattr(llm_router, "_transport", transport)
    data = llm_router.ask_json("give json")
    assert data == {"clips": [1, 2]}


# ---------------------------------------------------------------- HTTP router

def test_status_and_key_endpoints():
    fastapi = pytest.importorskip("fastapi")
    pytest.importorskip("httpx")
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from providers.router import router as providers_router

    app = fastapi.FastAPI()
    app.include_router(providers_router)
    client = TestClient(app)

    r = client.get("/status")
    assert r.status_code == 200
    rows = {row["provider"]: row for row in r.json()}
    assert set(rows) == {"ollama", "gemini", "groq"}
    for row in rows.values():
        assert set(row) == {"provider", "mode", "available_today", "cap", "cooldown_until"}
    assert rows["gemini"]["mode"] == "off"          # no key anywhere
    assert rows["ollama"]["mode"] == "free"         # local → never off

    r = client.post("/key", json={"provider": "gemini", "key": "byok-1"})
    assert r.status_code == 200 and r.json()["mode"] == "byok"
    assert client.get("/status").json()[1]["mode"] == "byok"

    assert client.post("/key", json={"provider": "groq", "key": ""}).status_code == 400
    assert client.delete("/key/nope").status_code == 404
    assert client.delete("/key/gemini").status_code == 200
    assert store.get_key("gemini") is None
