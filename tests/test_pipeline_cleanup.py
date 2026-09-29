"""
Offline cleanup tests for the pipeline refactor:
  - Campaign auto-load gated behind CLIPPIFY_CAMPAIGN env var
  - gaming content-type profile present, unknown types still fall back to podcast
  - /api/analyze-video stores content_type + real Content DNA (mocked LLM)

All LLM/network touchpoints are monkeypatched — the whole suite must stay < 10s.
"""

import json
import time
import types as pytypes

import pytest


# ─────────────────────────────────────────────────────────────────────────────
#  (a) Campaign env gate
# ─────────────────────────────────────────────────────────────────────────────

def test_campaign_disabled_by_default(monkeypatch):
    import orchestrator
    monkeypatch.delenv("CLIPPIFY_CAMPAIGN", raising=False)
    assert orchestrator._campaign_enabled() is False
    monkeypatch.setenv("CLIPPIFY_CAMPAIGN", "")
    assert orchestrator._campaign_enabled() is False
    monkeypatch.setenv("CLIPPIFY_CAMPAIGN", "0")
    assert orchestrator._campaign_enabled() is False
    monkeypatch.setenv("CLIPPIFY_CAMPAIGN", "off")
    assert orchestrator._campaign_enabled() is False


def test_campaign_enabled_on_opt_in(monkeypatch):
    import orchestrator
    for val in ("1", "true", "TRUE", "True"):
        monkeypatch.setenv("CLIPPIFY_CAMPAIGN", val)
        assert orchestrator._campaign_enabled() is True, f"failed for value: {val}"


def test_load_campaign_not_called_when_env_off(monkeypatch):
    import orchestrator
    import campaign as campaign_mod

    calls = []
    monkeypatch.setattr(campaign_mod, "load_campaign", lambda: calls.append(1))
    monkeypatch.delenv("CLIPPIFY_CAMPAIGN", raising=False)

    # Mirrors the gate inside run_editing_plan without running the full pipeline
    assert orchestrator._campaign_enabled() is False
    if orchestrator._campaign_enabled():
        orchestrator._apply_campaign(pytypes.SimpleNamespace())
    assert calls == [], "load_campaign must NOT be called unless CLIPPIFY_CAMPAIGN=1"


def test_apply_campaign_constraints_when_env_on(monkeypatch):
    import orchestrator
    import campaign as campaign_mod

    calls = []

    def fake_loader():
        calls.append(1)
        return pytypes.SimpleNamespace(
            name="CampX",
            allow_bg_music=False,
            allow_broll=False,
            translate_to_arabic=False,
            min_duration=10,
        )

    monkeypatch.setattr(campaign_mod, "load_campaign", fake_loader)
    monkeypatch.setenv("CLIPPIFY_CAMPAIGN", "1")

    plan = pytypes.SimpleNamespace(
        global_music=True,
        music_path="song.mp3",
        auto_broll=True,
        translate_to_arabic=True,
        duration_sec=60.0,
    )
    assert orchestrator._campaign_enabled() is True
    orchestrator._apply_campaign(plan)

    assert calls == [1], "load_campaign must be called exactly once when enabled"
    assert plan.global_music is False
    assert plan.music_path == ""
    assert plan.auto_broll is False
    assert plan.translate_to_arabic is False
    assert plan.duration_sec == 60.0  # 60s >= campaign minimum -> untouched


# ─────────────────────────────────────────────────────────────────────────────
#  (b) Gaming profile + fallback intact
# ─────────────────────────────────────────────────────────────────────────────

def test_gaming_profile_present():
    from content_types import ALL_TYPES, HOOK_STRATEGY, EMPHASIS_SFX, get_type_profile

    profile = get_type_profile("gaming")
    podcast_keys = set(ALL_TYPES["podcast"].keys())
    assert set(profile.keys()) == podcast_keys, "gaming profile keys must match podcast structure"

    assert profile["caption_theme"] == "Cyberpunk Neon"
    assert profile["zoom_style"] == "dynamic"
    assert profile["default_n_clips"] == 6
    assert profile["default_duration"] == 45
    assert isinstance(profile["hook_strategy"], dict)
    assert "llm_prompt_hint" in profile["hook_strategy"]
    assert profile["emphasis_sfx"] == EMPHASIS_SFX["gaming"]
    assert HOOK_STRATEGY["gaming"]["llm_prompt_hint"]
    assert get_hook_prompt_resolves("gaming")


def get_hook_prompt_resolves(content_type):
    from content_types import get_hook_prompt
    return bool(get_hook_prompt(content_type))


def test_unknown_type_falls_back_to_podcast():
    from content_types import ALL_TYPES, get_hook_prompt, get_type_profile

    fallback = ALL_TYPES["podcast"]
    assert get_type_profile("definitely_not_a_real_type") is fallback
    assert get_hook_prompt("definitely_not_a_real_type") == fallback["hook_strategy"]["llm_prompt_hint"]


# ─────────────────────────────────────────────────────────────────────────────
#  (c) /api/analyze-video stores content_type (+ mocked real DNA path)
# ─────────────────────────────────────────────────────────────────────────────

WORDS = [
    {"start": float(i), "end": float(i) + 0.4, "text": t}
    for i, t in enumerate(["welcome", "to", "the", "show", "today", "we", "learn", "editing"])
]


def _poll_results(api, session_id, timeout=5.0):
    deadline = time.time() + timeout
    sess = None
    while time.time() < deadline:
        sess = api.get_session(session_id)
        if sess and isinstance(sess.get("results"), dict):
            return sess
        time.sleep(0.05)
    return sess


@pytest.fixture
def mocked_pipeline(monkeypatch, tmp_path):
    """Patch transcription/viral-scorer heavy work; leave Content DNA pluggable."""
    import api
    import viral_scorer

    video_file = tmp_path / "input.mp4"
    video_file.write_bytes(b"\x00" * 64)

    monkeypatch.setattr(api, "generate_subtitles", lambda path: [dict(w) for w in WORDS])
    monkeypatch.setattr(viral_scorer, "get_viral_timeline", lambda path, words: {0.0: 0.9})
    return {"video_path": str(video_file)}


def test_analyze_video_stores_content_type_and_real_dna(client, mocked_pipeline, monkeypatch):
    import api
    import llm_config

    monkeypatch.setattr(llm_config, "GEMMA_API_KEY", "test-key")
    monkeypatch.setattr(
        llm_config, "ask_llm",
        lambda prompt, temperature=0.5, json_mode=False, max_retries=2:
            '{"tone": "x", "speakers_type": "dialogue", "info_density": "casual", '
            '"language_and_dialect": "English US", "visual_vibe": "Neon Cyberpunk", '
            '"target_pacing": "fast-paced"}',
    )

    resp = client.post(
        "/api/analyze-video",
        json={"video_path": mocked_pipeline["video_path"], "content_type": "gaming"},
    )
    assert resp.status_code == 200
    session_id = resp.json()["session_id"]

    sess = _poll_results(api, session_id)
    assert sess is not None, "analysis did not finish in time"
    assert sess.get("errors") in ([], None), f"unexpected errors: {sess.get('errors')}"
    results = sess["results"]
    assert results["content_type"] == "gaming"
    assert results["words"], "words must be present"
    assert results["content_dna"]["tone"] == "x", "real DNA (via llm_config.ask_llm) must win"


def test_analyze_video_dna_fallback_without_api_key(client, mocked_pipeline, monkeypatch):
    import api
    import llm_config

    monkeypatch.setattr(llm_config, "GEMMA_API_KEY", "")

    resp = client.post(
        "/api/analyze-video",
        json={"video_path": mocked_pipeline["video_path"], "content_type": "comedy"},
    )
    assert resp.status_code == 200
    session_id = resp.json()["session_id"]

    sess = _poll_results(api, session_id)
    assert sess is not None, "analysis did not finish in time"
    results = sess["results"]
    assert results["content_type"] == "comedy"
    assert results["content_dna"]["tone"] == "conversational", "offline dummy DNA expected"
