"""
Tests for the Auto-Edit pipeline endpoints (docs/CONTRACTS.md ⭐ section)
plus server-side contract fixes for legacy endpoints.

All tests are offline: no real LLM calls, no real video processing.
"""

import json
import threading
import time

import pytest

import api


# ── Fixtures ──────────────────────────────────────────────────────────────

@pytest.fixture
def isolated_db(monkeypatch, tmp_path):
    """Point the sessions DB at a temp file so tests never touch sessions.db."""
    db_file = tmp_path / "test_sessions.db"
    monkeypatch.setattr(api, "DB_PATH", str(db_file))
    api.init_db()
    return str(db_file)


@pytest.fixture
def fake_video(tmp_path):
    video = tmp_path / "input_video.mp4"
    video.write_bytes(b"not a real video - just needs to exist on disk")
    return str(video)


# ── POST /api/auto-edit ───────────────────────────────────────────────────

def test_auto_edit_returns_202_with_mocked_pipeline(
    client, isolated_db, monkeypatch, fake_video
):
    calls = []

    def fake_pipeline(sid, req):
        calls.append((sid, req))

    monkeypatch.setattr(api, "_run_auto_edit", fake_pipeline)

    response = client.post("/api/auto-edit", json={"video_path": fake_video})
    assert response.status_code == 202, f"Expected 202, got {response.status_code}: {response.text}"

    sid = response.json().get("session_id")
    assert sid, f"Missing session_id in payload: {response.json()}"

    deadline = time.time() + 5
    while not calls and time.time() < deadline:
        time.sleep(0.02)

    assert calls, "Background pipeline was never invoked"
    assert calls[0][0] == sid
    # Defaults per contract
    answers = calls[0][1].answers
    assert answers.n_clips == 5
    assert answers.clip_duration_sec == 60.0
    assert answers.content_type == "auto"
    assert answers.platform == "tiktok"
    assert answers.broll is True
    assert answers.music is False
    assert answers.translate_arabic is False


def test_auto_edit_missing_video_404(client, isolated_db):
    response = client.post(
        "/api/auto-edit", json={"video_path": "Z:/definitely/missing.mp4"}
    )
    assert response.status_code == 404


def test_auto_edit_quota_exceeded_402(client, isolated_db, monkeypatch, fake_video):
    monkeypatch.setattr(api, "consume_credit", lambda user: (False, "monthly limit reached"))
    response = client.post("/api/auto-edit", json={"video_path": fake_video})
    assert response.status_code == 402
    assert response.json()["detail"] == "quota_exceeded"


def test_auto_edit_quota_ok_when_billing_allows(
    client, isolated_db, monkeypatch, fake_video
):
    monkeypatch.setattr(api, "consume_credit", lambda user: (True, "ok"))
    monkeypatch.setattr(api, "_run_auto_edit", lambda sid, req: None)
    response = client.post("/api/auto-edit", json={"video_path": fake_video})
    assert response.status_code == 202


def test_auto_edit_session_starts_queued(client, isolated_db, monkeypatch, fake_video):
    monkeypatch.setattr(api, "_run_auto_edit", lambda sid, req: None)
    response = client.post("/api/auto-edit", json={"video_path": fake_video})
    assert response.status_code == 202
    sid = response.json()["session_id"]
    sess = api.get_session(sid)
    assert sess is not None
    assert sess["status"] == "queued"


# ── GET /api/auto-edit/status/{sid} ───────────────────────────────────────

def test_status_endpoint_returns_session(client, isolated_db):
    payload = {
        "type": "progress",
        "stage": "transcribing",
        "progress": 15.0,
        "message_ar": "جاري تفريغ الصوت...",
        "message_en": "Transcribing audio...",
    }
    sid = "status-test-sid"
    api.set_session(sid, 15.0, "transcribing", results=payload)

    response = client.get(f"/api/auto-edit/status/{sid}")
    assert response.status_code == 200
    data = response.json()
    assert data["type"] == "progress"
    assert data["stage"] == "transcribing"
    assert data["progress"] == 15.0


def test_status_endpoint_done_payload(client, isolated_db):
    payload = {
        "type": "done",
        "result": {"clips": [{"index": 0}], "compiled_file_url": None},
    }
    sid = "done-test-sid"
    api.set_session(sid, 100.0, "done", results=payload)

    response = client.get(f"/api/auto-edit/status/{sid}")
    assert response.status_code == 200
    data = response.json()
    assert data["type"] == "done"
    assert data["result"]["clips"][0]["index"] == 0


def test_status_endpoint_unknown_404(client, isolated_db):
    response = client.get("/api/auto-edit/status/no-such-session")
    assert response.status_code == 404


# ── POST /api/auto-edit/cancel/{sid} ──────────────────────────────────────

def test_cancel_sets_flag(client, isolated_db):
    sid = "cancel-test-sid"
    api.set_session(sid, 10.0, "transcribing", results={"type": "progress"})
    try:
        response = client.post(f"/api/auto-edit/cancel/{sid}")
        assert response.status_code == 200
        assert api._cancel_flags.get(sid) is True
    finally:
        api._cancel_flags.pop(sid, None)


def test_cancel_unknown_404(client, isolated_db):
    response = client.post("/api/auto-edit/cancel/no-such-session")
    assert response.status_code == 404


def test_cancelled_worker_reports_cancelled_status(client, isolated_db, fake_video):
    """Worker honors the cooperative cancel flag between stages."""
    import concurrent.futures

    req = api.AutoEditRequest(video_path=fake_video)
    sid = "cancel-worker-sid"
    api._cancel_flags[sid] = True
    try:
        api._run_auto_edit(sid, req)
        sess = api.get_session(sid)
        assert sess["status"] == "cancelled"
        assert sess["results"]["type"] == "cancelled"
    finally:
        api._cancel_flags.pop(sid, None)


# ── WS /ws/progress/{session_id} ──────────────────────────────────────────

def test_ws_progress_broadcast_reaches_subscriber(client, isolated_db):
    sid = "ws-progress-test-sid"
    with client.websocket_connect(f"/ws/progress/{sid}") as ws:
        payload = {
            "type": "progress",
            "stage": "rendering",
            "progress": 72.0,
            "message_ar": "جاري المعالجة...",
            "message_en": "Rendering...",
        }
        api._broadcast_progress(sid, json.dumps(payload))
        received = json.loads(ws.receive_text())
        assert received["stage"] == "rendering"
        assert received["progress"] == 72.0

    # Subscriber unregistered after disconnect
    deadline = time.time() + 5
    while api._progress_subs.get(sid) and time.time() < deadline:
        time.sleep(0.05)
    assert not api._progress_subs.get(sid), "Subscriber was not cleaned up after disconnect"


def test_broadcast_with_no_subscribers_is_safe(client, isolated_db):
    # Must not raise even though nobody is listening
    api._broadcast_progress("nobody-listening", json.dumps({"type": "progress"}))


# ── Contract fixes (docs/CONTRACTS.md table) ──────────────────────────────

def test_ducking_accepts_new_contract(client, isolated_db):
    response = client.post(
        "/api/audio/ducking",
        json={
            "vocals_path": "missing_vocals.wav",
            "background_path": "missing_background.wav",
            "output_path": "out_ducked.wav",
            "duck_factor": 0.2,
        },
    )
    # Files don't exist → engine error (500) is fine; validation rejection (422) is NOT.
    assert response.status_code != 422, f"Contract regression: {response.text}"


def test_style_analyze_reference_contract(client, isolated_db):
    response = client.post(
        "/api/style/analyze-reference",
        json={"reference_path": "missing_reference.mp4", "profile_name": "my_style"},
    )
    # Missing file → 404; wrong body shape → 422 must never happen.
    assert response.status_code == 404, f"Expected 404 (file missing), got {response.status_code}"


def test_style_imitate_contract(client, isolated_db):
    response = client.post(
        "/api/style/imitate",
        json={
            "target_path": "missing_target.mp4",
            "profile_path": "profiles/missing_profile.json",
            "output_name": "imitated_output",
            "words": [],
        },
    )
    assert response.status_code == 404, f"Expected 404 (target missing), got {response.status_code}"


def test_autoframing_contract(client, isolated_db):
    response = client.post(
        "/api/project/ai/autoframing",
        json={"timeline": {"tracks": {"video": []}}, "clip_id": "nope"},
    )
    assert response.status_code != 422, f"Contract regression: {response.text}"


def test_viral_recommendations_contract(client, isolated_db):
    response = client.post(
        "/api/viral/recommendations",
        json={"words": [], "dna": {}, "viral_timeline": {}},
    )
    assert response.status_code != 422, f"Contract regression: {response.text}"


def test_render_plan_accepts_contract_fields(client, isolated_db, monkeypatch):
    started = threading.Event()

    def fake_run_editing_plan(plan, status_callback=None, sound_fx=False):
        started.set()
        raise RuntimeError("mocked offline")

    monkeypatch.setattr(api, "run_editing_plan", fake_run_editing_plan)

    response = client.post(
        "/api/render-plan",
        json={
            "video_path": "whatever.mp4",
            "clips": [
                {
                    "index": 0,
                    "start_sec": 0.0,
                    "end_sec": 5.0,
                    "hook": "hook text",
                    "reason": "high energy",
                    "caption_theme": "TikTok Yellow",
                    "zoom_style": "none",
                    "color_grade": "original",
                }
            ],
            "custom_instructions": "ركز على الوجه في المنتصف",
            "music_path": "music/chill.mp3",
            "global_music": True,
            "global_ending_cta": "اشترك في القناة",
        },
    )
    assert response.status_code in (200, 202), f"Got {response.status_code}: {response.text}"
    assert response.json().get("session_id")
    assert started.wait(timeout=10), "Render worker never started"
