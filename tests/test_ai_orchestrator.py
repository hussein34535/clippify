"""Tests for ai_orchestrator — the tool execution engine.

Covers:
  - The 7 dispatcher categories still resolve.
  - New real handlers (detect_scenes, beat_sync, generate_thumbnail) run against
    a real generated video and actually mutate state.
  - Module-backed handlers (filler_removal, jump_cut_remover) compute real segments.
  - Honest-stub handlers no longer claim silent success.
  - Graceful degradation: missing file / missing optional dep never crashes the
    dispatcher.
"""
import os
import sys
import subprocess
import tempfile

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ai_orchestrator import (
    execute_action_plan,
    HANDLERS,
    _ffmpeg_detect_scenes,
    _ffmpeg_extract_thumbnail,
    _ffmpeg_path,
    _get_words_list,
    _resolve_target_clip,
    _median_gap,
)


# ─── Fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def sample_video():
    """Generate a 3s video with a hard scene change at 1.5s (red → blue)."""
    try:
        exe = _ffmpeg_path()
    except Exception:
        pytest.skip("ffmpeg not available")
    tmp = tempfile.mkdtemp(prefix="clippify_test_")
    path = os.path.join(tmp, "scene_test.mp4")
    if os.path.exists(path):
        return path
    cmd = [
        exe, "-y",
        "-f", "lavfi", "-i", "color=c=red:s=320x240:r=30:d=1.5",
        "-f", "lavfi", "-i", "color=c=blue:s=320x240:r=30:d=1.5",
        "-filter_complex", "[0:v][1:v]concat=n=2:v=1[outv]",
        "-map", "[outv]", "-pix_fmt", "yuv420p", path,
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=60,
                         stdin=subprocess.DEVNULL)
    if res.returncode != 0 or not os.path.exists(path):
        pytest.skip(f"ffmpeg failed to make test video: {res.stderr[-200:] if res.stderr else ''}")
    return path


def _state(video_path=None):
    clips = [{
        "id": "c1", "name": "Intro",
        "start_time_in_timeline": 0, "end_time_in_timeline": 3,
        "effects": {},
    }]
    if video_path:
        clips[0]["source_path"] = video_path
    return {
        "tracks": [{"id": "v1", "name": "V1", "type": "video", "clips": clips}],
        "currentTime": 1.0,
        "selectedClipId": "c1",
    }


# ─── Dispatcher sanity ───────────────────────────────────────────────────────

def test_all_seven_categories_registered():
    assert set(HANDLERS.keys()) == {
        "timeline", "playback", "effects", "audio", "subtitles", "ai", "export"
    }


def test_execute_invalid_tool_name_recorded_as_error():
    r = execute_action_plan([{"name": "bogus", "args": {}}], _state())
    assert r["ok"] is False
    assert any("Invalid tool name" in e for e in r["errors"])


def test_unknown_category_recorded_as_error():
    r = execute_action_plan([{"name": "nonexistent.thing", "args": {}}], _state())
    assert r["ok"] is False


# ─── Helpers ─────────────────────────────────────────────────────────────────

def test_resolve_target_clip_prefers_selected():
    s = _state()
    c = _resolve_target_clip(s["tracks"], "c1")
    assert c is not None and c["id"] == "c1"


def test_resolve_target_clip_falls_back_to_first_video():
    s = _state(video_path="x.mp4")
    c = _resolve_target_clip(s["tracks"], None)
    assert c is not None
    assert c.get("source_path") == "x.mp4"


def test_get_words_list_from_flat_words():
    s = {"words": [{"text": "a", "start": 0.0, "end": 0.5}]}
    assert len(_get_words_list(s)) == 1


def test_get_words_list_synthesized_from_subtitle_track():
    s = {"tracks": [{"id": "sub1", "type": "subtitle", "clips": [
        {"text": "hi", "start_time_in_timeline": 0.0, "end_time_in_timeline": 1.0}
    ]}]}
    words = _get_words_list(s)
    assert len(words) == 1 and words[0]["text"] == "hi"


def test_median_gap_basic():
    assert _median_gap([0, 1, 2, 3]) == 1.0
    assert _median_gap([5]) == 0.5  # too few → default


# ─── Real FFmpeg-backed handlers ─────────────────────────────────────────────

def test_detect_scenes_finds_cut(sample_video):
    times = _ffmpeg_detect_scenes(sample_video, threshold=0.3)
    assert len(times) >= 1
    # The concat creates a cut at ~1.5s
    assert any(abs(t - 1.5) < 0.3 for t in times)


def test_extract_thumbnail_writes_png(sample_video):
    out = _ffmpeg_extract_thumbnail(sample_video, 1.0)
    assert os.path.exists(out) and os.path.getsize(out) > 0


def test_ai_detect_scenes_dispatch(sample_video):
    r = execute_action_plan([{"name": "ai.detect_scenes", "args": {}}], _state(sample_video))
    res = r["results"][0]
    assert res["ok"] is True
    assert "scene" in res["message"].lower() or "Detected" in res["message"]


def test_ai_generate_thumbnail_dispatch(sample_video):
    s = _state(sample_video)
    r = execute_action_plan([{"name": "ai.generate_thumbnail", "args": {"time": 0.5}}], s)
    res = r["results"][0]
    assert res["ok"] is True
    # execute_action_plan deep-copies the state, so mutations land in new_state
    clip = r["new_state"]["tracks"][0]["clips"][0]
    assert clip["ai_features"]["thumbnail"]


# ─── Module-backed handlers (filler / jump-cut) ──────────────────────────────

def test_filler_removal_keeps_speech():
    s = _state()
    s["words"] = [
        {"text": "hello", "start": 0.0, "end": 0.5},
        {"text": "world", "start": 2.0, "end": 2.5},  # 1.5s gap → trimmed
    ]
    r = execute_action_plan([{"name": "ai.remove_filler_words", "args": {"trim_mode": "natural"}}], s)
    res = r["results"][0]
    assert res["ok"] is True
    assert "segments kept" in res["message"]
    # execute_action_plan deep-copies the state, so mutations land in new_state
    new_clip = r["new_state"]["tracks"][0]["clips"][0]
    segs = new_clip["ai_features"]["active_segments"]
    assert len(segs) >= 1


def test_jump_cut_remover_dispatch():
    s = _state()
    s["words"] = [{"text": "a", "start": 0.0, "end": 0.3}]
    r = execute_action_plan([{"name": "ai.jump_cut_remover", "args": {}}], s)
    assert r["results"][0]["ok"] is True


# ─── Honest-stub handlers ────────────────────────────────────────────────────
# These must NOT claim silent success — their message must admit they're queued.

@pytest.mark.parametrize("tool", [
    "ai.remove_object",
    "ai.predict_trend",
    "ai.interpolate_frames",
    "ai.upscale_video",
])
def test_stub_handlers_are_honest(tool):
    r = execute_action_plan([{"name": tool, "args": {}}], _state())
    res = r["results"][0]
    assert res["ok"] is True  # queued ≠ error
    msg = res["message"].lower()
    assert "not yet implemented" in msg or "queued" in msg or "requires" in msg, (
        f"Stub {tool} should be honest, got: {res['message']}"
    )


def test_audio_detect_key_is_honest():
    r = execute_action_plan([{"name": "audio.detect_key", "args": {}}], _state())
    msg = r["results"][0]["message"].lower()
    assert "not yet implemented" in msg or "no key-detection" in msg


# ─── Graceful degradation ────────────────────────────────────────────────────

def test_missing_file_does_not_crash():
    s = _state(video_path="C:/definitely/does/not/exist.mp4")
    for tool in ["ai.detect_scenes", "ai.beat_sync", "ai.generate_thumbnail",
                 "ai.score_virality", "ai.remove_background", "audio.separate_stems"]:
        r = execute_action_plan([{"name": tool, "args": {}}], s)
        # Must return a result (not raise) and flag failure with a clear message
        assert len(r["results"]) == 1
        assert r["results"][0]["ok"] is False
        assert "not found" in r["results"][0]["message"].lower()


def test_score_virality_without_transcript_is_helpful(sample_video):
    s = _state(sample_video)  # no 'words' key
    r = execute_action_plan([{"name": "ai.score_virality", "args": {}}], s)
    msg = r["results"][0]["message"]
    assert r["results"][0]["ok"] is True  # guidance, not error
    assert "transcript" in msg.lower()
