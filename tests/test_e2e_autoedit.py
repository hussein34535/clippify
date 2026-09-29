"""
AGENT-G1 [qa-security] — full-journey E2E integration tests (offline).

Covers docs/CONTRACTS.md:
  a) register → login → me (auth routers mounted by api.py)
  b) quota: free plan 3 credits → 4th rejected (402 shape) + /api/billing/usage numbers
  c) auto-edit happy path through the REAL _run_auto_edit worker (heavy stage
     functions monkeypatched to instant deterministic fakes), WS /ws/progress/{sid}
     delivery, ordered stage subset [queued..done], final clips[] contract keys
  d) cancel path: worker blocked on threading.Event → POST cancel → status
     "cancelled", WS receives cancelled payload, no error frames
  e) security regressions: /api/broll/download scheme rejection, missing pexels
     host allowlist (documented gap, see SECURITY.md), downloader.validate_url

No network access, no real LLM/ffmpeg calls. Suite budget: < 15s.
"""

import json
import threading
import time
import uuid
from pathlib import Path

import pytest


# ── Fixtures ──────────────────────────────────────────────────────────────

@pytest.fixture
def isolated_db(monkeypatch, tmp_path):
    """Sessions DB at a temp file so tests never touch sessions.db."""
    import api
    db_file = tmp_path / "e2e_sessions.db"
    monkeypatch.setattr(api, "DB_PATH", str(db_file))
    api.init_db()
    return str(db_file)


@pytest.fixture
def users_db(tmp_path, monkeypatch):
    """Isolated users.db per test (same pattern as tests/test_auth_billing.py)."""
    db_file = tmp_path / "users.db"
    monkeypatch.setenv("CLIPPIFY_USERS_DB", str(db_file))
    return db_file


@pytest.fixture
def fake_video(tmp_path):
    video = tmp_path / "input_video.mp4"
    video.write_bytes(b"not a real video - just needs to exist on disk")
    return str(video)


@pytest.fixture
def broadcast_spy(monkeypatch):
    """Capture every _broadcast_progress payload (deterministic stage stream,
    independent of WS subscribe timing) while keeping the original delivery."""
    import api
    captured = []
    lock = threading.Lock()
    original = api._broadcast_progress

    def spy(session_id, payload_json_str):
        with lock:
            captured.append(json.loads(payload_json_str))
        return original(session_id, payload_json_str)

    monkeypatch.setattr(api, "_broadcast_progress", spy)
    class _Spy:
        def all(self):
            with lock:
                return list(captured)
        def for_sid(self, sid):
            # payloads don't carry the sid; callers use one session per test
            return self.all()
    return _Spy()


def _register_and_login(client, users_db):
    """Register + login via the mounted auth routers. Returns (headers, user_dict)."""
    email = f"e2e-{uuid.uuid4().hex[:10]}@example.com"
    r = client.post(
        "/api/auth/register",
        json={"email": email, "password": "secret123", "name": "E2E"},
    )
    assert r.status_code == 200, (
        f"auth router not mounted or broken ({r.status_code}): {r.text}"
    )
    data = r.json()
    headers = {"Authorization": f"Bearer {data['access_token']}"}
    # login round-trip on the same account
    r2 = client.post("/api/auth/login", json={"email": email, "password": "secret123"})
    assert r2.status_code == 200, r2.text
    assert r2.json()["user"]["id"] == data["user"]["id"]
    return headers, data["user"]


EXPECTED_STAGE_ORDER = [
    "queued", "transcribing", "understanding", "selecting",
    "hooks", "effects", "rendering", "compiling",
]


def _assert_ordered_subsequence(stages_seen):
    """stages_seen must appear in the same relative order as EXPECTED_STAGE_ORDER."""
    order_idx = {s: i for i, s in enumerate(EXPECTED_STAGE_ORDER)}
    positions = [order_idx[s] for s in stages_seen if s in order_idx]
    assert positions, f"No known stages observed: {stages_seen}"
    assert positions == sorted(positions), (
        f"Stages out of order: {stages_seen} vs contract {EXPECTED_STAGE_ORDER}"
    )


# ── a+b) auth journey + quota ─────────────────────────────────────────────

def test_journey_register_login_me_quota_and_402_shape(client, isolated_db, users_db, monkeypatch, fake_video):
    import api
    from billing import quotas
    from auth import service

    headers, user = _register_and_login(client, users_db)
    assert user["plan"] == "free"

    # me reflects the registered identity
    r = client.get("/api/auth/me", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["user"]["id"] == user["id"]

    # free plan: 3 consumes succeed …
    uid = user["id"]
    for i in range(1, 4):
        ok, msg = quotas.consume_credit(service.get_user_by_id(uid))
        assert ok is True, (i, msg)
    fresh = service.get_user_by_id(uid)
    assert fresh["credits_used"] == 3

    # … 4th is over quota
    ok, msg = quotas.consume_credit(fresh)
    assert ok is False and msg == "quota_exceeded"

    # usage endpoint reports the numbers
    r = client.get("/api/billing/usage", headers=headers)
    assert r.status_code == 200, r.text
    usage = r.json()
    assert usage["videos_used"] == 3
    assert usage["videos_limit"] == 3  # free plan
    assert usage["period_start"] and usage["period_end"]

    # guarded endpoint returns the contracted 402 shape when quota refuses
    monkeypatch.setattr(api, "consume_credit", lambda u: (False, "quota_exceeded"))
    resp = client.post(
        "/api/auto-edit", json={"video_path": fake_video}, headers=headers
    )
    assert resp.status_code == 402, resp.text
    assert resp.json()["detail"] == "quota_exceeded"


# ── c) happy path through the real worker + WebSocket ────────────────────

@pytest.fixture
def patched_pipeline(monkeypatch, tmp_path):
    """Patch every heavy stage function where _run_auto_edit resolves it.

    - api.generate_subtitles / api._select_clips_with_ai / api._plan_effects_with_ai /
      api.run_editing_plan are module-level imports in api.py.
    - content_dna.extract_content_dna and viral_scorer.get_viral_timeline are
      imported INSIDE the worker body, so patch them on their own modules.
    """
    import api
    import content_dna
    import viral_scorer

    gate = threading.Event()          # holds worker inside stage 1 until released
    words = [
        {"text": w, "start": i * 0.5, "end": i * 0.5 + 0.45}
        for i, w in enumerate(["alpha", "beta", "gamma", "delta",
                               "epsilon", "zeta", "eta", "theta"])
    ]

    monkeypatch.setattr(api, "generate_subtitles", lambda path: (gate.wait(8), words)[1])
    monkeypatch.setattr(
        content_dna, "extract_content_dna",
        lambda w, llm_fn=None: {"tone": "humor", "topics": ["testing"], "pace": "fast"},
    )
    monkeypatch.setattr(
        viral_scorer, "get_viral_timeline",
        lambda path, w: {float(t): 0.80 + (t % 10) * 0.01 for t in range(0, 21)},
    )

    def fake_select(w, n_clips, duration_sec, content_type, **kw):
        return [
            {"index": 0, "start_sec": 0.0, "end_sec": 9.0,
             "hook_options": ["This will blow your mind"], "reason": "peak energy"},
            {"index": 1, "start_sec": 9.0, "end_sec": 18.0,
             "hook_options": ["Wait for the plot twist"], "reason": "narrative peak"},
        ][:max(1, int(n_clips))]

    monkeypatch.setattr(api, "_select_clips_with_ai", fake_select)

    def fake_effects(texts, content_type, auto_broll=True, clip_words_list=None, **kw):
        return [
            {"index": i, "caption_theme": "TikTok Yellow", "zoom_style": "none",
             "color_grade": "original", "emphasis_words": [], "sfx_queries": [],
             "brolls": []}
            for i in range(len(texts))
        ]

    monkeypatch.setattr(api, "_plan_effects_with_ai", fake_effects)

    produced = []  # basenames copied into <repo>/output — cleaned up by fixture

    def fake_run_editing_plan(plan, status_callback=None, sound_fx=False):
        paths = []
        for i in range(len(plan.clips)):
            src = tmp_path / f"e2e_render_{uuid.uuid4().hex[:8]}_clip{i}.mp4"
            src.write_bytes(b"%PDF-fake-rendered-clip")
            produced.append(src.name)
            paths.append(str(src))
        return paths

    monkeypatch.setattr(api, "run_editing_plan", fake_run_editing_plan)

    yield gate

    # teardown: remove copies the worker made into <repo>/output/
    out_dir = Path(api.__file__).parent / "output"
    for name in produced:
        try:
            (out_dir / name).unlink(missing_ok=True)
        except OSError:
            pass


def test_journey_auto_edit_happy_path_ws_and_status(
    client, isolated_db, users_db, fake_video, patched_pipeline, broadcast_spy
):
    import api

    headers, _user = _register_and_login(client, users_db)

    resp = client.post(
        "/api/auto-edit",
        json={
            "video_path": fake_video,
            "answers": {
                "content_type": "comedy", "platform": "tiktok",
                "n_clips": 2, "clip_duration_sec": 60.0,
                "music": False, "broll": False,
                "translate_arabic": False, "custom_instructions": "",
            },
        },
        headers=headers,
    )
    assert resp.status_code == 202, resp.text
    sid = resp.json()["session_id"]
    assert sid

    # Subscriber joins BEFORE the gated worker is released.
    ws_messages = []
    ws_ready = threading.Event()

    with client.websocket_connect(f"/ws/progress/{sid}") as ws:
        stop_reader = threading.Event()

        def reader():
            ws_ready.set()
            while not stop_reader.is_set():
                try:
                    ws_messages.append(json.loads(ws.receive_text()))
                except Exception:
                    break  # socket closed — clean exit

        t = threading.Thread(target=reader, daemon=True)
        t.start()
        assert ws_ready.wait(5)

        patched_pipeline.set()  # release generate_subtitles → pipeline flushes

        deadline = time.time() + 10
        final = None
        while time.time() < deadline:
            r = client.get(f"/api/auto-edit/status/{sid}")
            assert r.status_code == 200, r.text
            final = r.json()
            if final.get("type") in ("done", "error", "cancelled"):
                break
            time.sleep(0.05)
        time.sleep(0.3)          # small drain window for the WS queue
        stop_reader.set()

    assert final is not None and final["type"] == "done", f"pipeline failed: {final}"

    # Ordered stages from the broadcast spy (complete, race-free view)
    seen_stages = [m.get("stage") for m in broadcast_spy.all() if m.get("type") == "progress"]
    _assert_ordered_subsequence(seen_stages)
    assert seen_stages[0] == "queued"

    # WS delivered at least the terminal frame through the real socket
    assert any(m.get("type") == "done" for m in ws_messages), \
        f"WS never delivered done; got: {ws_messages}"
    assert not any(m.get("type") == "error" for m in ws_messages)

    # Final payload contract: clips[] with viral_score / hook / file_url
    clips = final["result"]["clips"]
    assert len(clips) == 2
    for clip in clips:
        assert isinstance(clip["viral_score"], float) and 0.0 <= clip["viral_score"] <= 1.0
        assert isinstance(clip["hook"], str) and clip["hook"]
        assert isinstance(clip["file_url"], str) and clip["file_url"]
        assert clip["caption_theme"]
        assert clip["duration_sec"] > 0


# ── d) cancel journey ─────────────────────────────────────────────────────

def test_journey_cancel_blocked_worker_reports_cancelled(
    client, isolated_db, users_db, fake_video, monkeypatch, broadcast_spy
):
    import api

    blocker = threading.Event()
    monkeypatch.setattr(
        api, "generate_subtitles",
        lambda path: (blocker.wait(10), [{"text": "x", "start": 0.0, "end": 0.4}])[1],
    )

    headers, _user = _register_and_login(client, users_db)
    resp = client.post("/api/auto-edit", json={"video_path": fake_video}, headers=headers)
    assert resp.status_code == 202, resp.text
    sid = resp.json()["session_id"]

    ws_messages = []
    with client.websocket_connect(f"/ws/progress/{sid}") as ws:
        # let the worker reach the blocked transcription call
        deadline = time.time() + 5
        while not blocker.wait(0.05) and time.time() < deadline:
            pass
        # worker is now parked inside generate_subtitles → request cancellation
        r = client.post(f"/api/auto-edit/cancel/{sid}", headers=headers)
        assert r.status_code == 200, r.text

        blocker.set()  # resume worker; next checkpoint raises _AutoEditCancelled

        final = None
        deadline = time.time() + 10
        while time.time() < deadline:
            poll = client.get(f"/api/auto-edit/status/{sid}")
            final = poll.json()
            if final.get("type") in ("cancelled", "error"):
                break
            time.sleep(0.05)
        time.sleep(0.3)
        try:
            ws_messages.append(json.loads(ws.receive_text(timeout=2)))
        except Exception:
            pass

    assert final["type"] == "cancelled", f"expected cancelled, got {final}"

    types_ws = {m.get("type") for m in ws_messages if isinstance(m, dict)}
    spy_types = {m.get("type") for m in broadcast_spy.all()}
    combined = types_ws | spy_types
    assert "cancelled" in combined, f"cancellation never broadcast: {combined}"
    assert "error" not in combined, f"cancel leaked an error frame: {combined}"

    sess = api.get_session(sid)
    assert sess["status"] == "cancelled"


# ── e) security regressions ───────────────────────────────────────────────

class TestSecurityRegressions:
    def test_broll_download_rejects_http_and_bad_scheme(self, client, isolated_db):
        # http:// must be refused ("Only HTTPS URLs allowed for security")
        r = client.post(
            "/api/broll/download",
            json={"download_url": "http://videos.pexels.com/x.mp4", "keyword": "city"},
        )
        assert r.status_code != 200, "http:// URL was accepted!"
        assert "https" in str(r.json().get("detail", "")).lower(), r.text

        # non-http(s) schemes must be refused as well
        r2 = client.post(
            "/api/broll/download",
            json={"download_url": "ftp://videos.pexels.com/x.mp4", "keyword": "city"},
        )
        assert r2.status_code != 200, "ftp:// URL was accepted!"

    @pytest.mark.xfail(
        reason="Known SSRF gap: /api/broll/download fetches ANY https host — "
               "no pexels/pixabay allowlist yet. See SECURITY.md. "
               "Will XPASS once the host allowlist lands.",
        strict=False,
    )
    def test_broll_download_rejects_non_pexels_host(self, client, isolated_db, monkeypatch):
        # Never touch the network: any fetch attempt explodes loudly.
        import requests

        def _boom(*a, **kw):
            raise AssertionError("network fetch attempted to non-pexels host")

        monkeypatch.setattr(requests, "get", _boom)
        r = client.post(
            "/api/broll/download",
            json={"download_url": "https://evil.example.com/steal.mp4",
                  "keyword": "city"},
        )
        assert r.status_code == 400, (
            f"non-pexels host should be 400-rejected, got {r.status_code}: {r.text}"
        )

    def test_validate_url_blocks_shell_metachars_and_ssrf_vectors(self):
        from downloader import validate_url

        good = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        assert validate_url(good) == good.strip()

        for bad in [
            "https://www.youtube.com/watch?v=abc;rm -rf /",
            "https://www.youtube.com/watch?v=a&`whoami`",
            'https://www.youtube.com/watch?v=x"|calc',
            "https://www.youtube.com/watch?v=<script>",
            "http://www.youtube.com/watch?v=abc",              # not https
            "https://169.254.169.255/latest/meta-data",        # IP-literal SSRF
            "https://evil-site.com/watch?v=abc",               # wrong host
            "",                                                 # empty
        ]:
            with pytest.raises(ValueError):
                validate_url(bad), bad
