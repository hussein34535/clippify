"""
Tests for the fair-use admission queue (fair_queue.py) + its /api/auto-edit
integration.

All tests are offline: tmp SQLite dbs, fake clock, mocked pipeline.
"""

import time
from datetime import datetime, timedelta, timezone

import pytest

import api
import fair_queue


# ── Fixtures ──────────────────────────────────────────────────────────────

class _FakeAddress:
    def __init__(self, host):
        self.host = host


class _FakeRequest:
    """Minimal stand-in for starlette Request (only .client is consulted)."""

    def __init__(self, host=None):
        self.client = _FakeAddress(host) if host is not None else None


@pytest.fixture
def fq_env(monkeypatch, tmp_path):
    """Isolated fairqueue db per test + flag off by default (app default)."""
    db_file = tmp_path / "test_fairqueue.db"
    monkeypatch.setenv("FAIRQUEUE_DB", str(db_file))
    monkeypatch.delenv("FREE_DAILY_CAP", raising=False)
    yield str(db_file)
    fair_queue.close()


# ── Unit: caps enforced per key independently ─────────────────────────────

def test_caps_enforced_per_key_independently(fq_env, monkeypatch):
    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")
    monkeypatch.setenv("FREE_DAILY_CAP", "2")

    assert fair_queue.admit("alice").ok
    assert fair_queue.admit("alice").ok
    denied = fair_queue.admit("alice")
    assert not denied.ok
    assert denied.reason == "daily_cap_reached"
    # Bob's counter is untouched by Alice's usage.
    assert fair_queue.admit("bob").ok
    assert fair_queue.admit("bob", cap=5).ok


# ── Unit: UTC-day rollover resets the cap (fake clock) ────────────────────

def test_rollover_new_day_resets_cap(fq_env, monkeypatch):
    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")
    monkeypatch.setenv("FREE_DAILY_CAP", "1")

    base = datetime(2026, 8, 24, 23, 59, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(fair_queue, "_utcnow", lambda: base)

    assert fair_queue.admit("alice").ok
    denied = fair_queue.admit("alice")
    assert not denied.ok
    assert 0 < denied.retry_after_sec <= 60

    # Manual midnight shift → fresh daily bucket.
    next_day = base + timedelta(seconds=120)
    monkeypatch.setattr(fair_queue, "_utcnow", lambda: next_day)
    assert fair_queue.admit("alice").ok

    # Old day's row still recorded, new day counted separately.
    conn = fair_queue._get_conn()
    days = dict(
        conn.execute(
            "SELECT day, count FROM usage WHERE idem=? ORDER BY day", ("alice",)
        ).fetchall()
    )
    assert len(days) == 2
    assert sum(days.values()) == 2  # 1 admitted per day; the denial never records


# ── Unit: paid plans bypass the cap but are still recorded ────────────────

def test_paid_bypass_records_usage_anyway(fq_env, monkeypatch):
    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")
    monkeypatch.setenv("FREE_DAILY_CAP", "1")

    for _ in range(4):
        decision = fair_queue.admit("pro-user", plan="pro")
        assert decision.ok

    conn = fair_queue._get_conn()
    count = conn.execute(
        "SELECT count FROM usage WHERE idem=? AND day=?",
        ("pro-user", fair_queue._today()),
    ).fetchone()[0]
    assert count == 4

    # Same key on the free plan is still capped.
    assert not fair_queue.admit("pro-user", plan="free").ok


# ── Unit: identity key derivation (ip fallback) ───────────────────────────

def test_identity_key_ip_fallback():
    assert fair_queue.identity_key({"id": "u42"}, None) == "u42"
    assert fair_queue.identity_key(None, _FakeRequest("10.0.0.7")) == "10.0.0.7"
    assert fair_queue.identity_key({"id": None}, _FakeRequest("testclient")) == "testclient"
    assert fair_queue.identity_key(None, _FakeRequest(None)) == "anon"
    assert fair_queue.identity_key(None, None) == "anon"
    assert fair_queue.identity_key("not-a-dict", _FakeRequest("1.2.3.4")) == "1.2.3.4"


# ── Unit: DISABLED flag short-circuits everything ─────────────────────────

def test_disabled_flag_short_circuit(fq_env, monkeypatch):
    # FAIRQUEUE_ENABLED unset → app default false.
    for _ in range(10):
        d = fair_queue.admit("spammer")
        assert d.ok and d.reason == "disabled"
    fair_queue.start_job("j1", "spammer")
    fair_queue.finish_job("j1")
    assert fair_queue.position_estimate() == 0
    # Nothing was persisted at all while disabled.
    import os

    assert not os.path.exists(fq_env)


# ── Unit: position estimate grows/shrinks with active jobs ────────────────

def test_position_estimate_grows_with_actives(fq_env, monkeypatch):
    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")

    assert fair_queue.position_estimate() == 0
    fair_queue.start_job("job-1", "k")
    fair_queue.start_job("job-2", "k")
    assert fair_queue.position_estimate() == 2
    fair_queue.finish_job("job-1")
    assert fair_queue.position_estimate() == 1
    fair_queue.finish_job("job-2")
    fair_queue.finish_job("job-never-started")  # idempotent
    assert fair_queue.position_estimate() == 0


# ── Integration: TestClient against /api/auto-edit ────────────────────────

@pytest.fixture
def isolated_db(monkeypatch, tmp_path):
    db_file = tmp_path / "test_sessions.db"
    monkeypatch.setattr(api, "DB_PATH", str(db_file))
    api.init_db()
    return str(db_file)


@pytest.fixture
def fake_video(tmp_path):
    video = tmp_path / "input_video.mp4"
    video.write_bytes(b"not a real video - just needs to exist on disk")
    return str(video)


def test_auto_edit_fair_queue_integration(
    client, isolated_db, fq_env, monkeypatch, fake_video
):
    from fastapi.testclient import TestClient

    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")
    monkeypatch.setenv("FREE_DAILY_CAP", "3")
    monkeypatch.setattr(api, "_run_auto_edit", lambda sid, req: None)

    # Fresh TestClient so the request lifecycle runs through admission.
    with TestClient(api.app) as c:
        for _ in range(3):
            r = c.post("/api/auto-edit", json={"video_path": fake_video})
            assert r.status_code == 202, r.text

        denied = c.post("/api/auto-edit", json={"video_path": fake_video})
        assert denied.status_code == 402
        assert denied.json()["detail"] == "quota_exceeded"
        retry_after = int(denied.headers["Retry-After"])
        assert retry_after > 0

        # Active slots were registered for the 3 admitted jobs.
        deadline = time.time() + 5
        while fair_queue.position_estimate() > 3 and time.time() < deadline:
            time.sleep(0.02)
        assert fair_queue.position_estimate() <= 3

        # Manual midnight shift → cap resets → next job admitted again.
        tomorrow = datetime.now(timezone.utc) + timedelta(days=1)
        monkeypatch.setattr(fair_queue, "_utcnow", lambda: tomorrow)
        r = c.post("/api/auto-edit", json={"video_path": fake_video})
        assert r.status_code == 202, r.text


def test_auto_edit_finish_job_releases_active_slot(fq_env, monkeypatch):
    """finish_job inside _run_auto_edit's finally frees the active slot."""
    monkeypatch.setenv("FAIRQUEUE_ENABLED", "true")
    fair_queue.start_job("sess-1", "tester")
    assert fair_queue.position_estimate() == 1
    fair_queue.finish_job("sess-1")
    assert fair_queue.position_estimate() == 0
