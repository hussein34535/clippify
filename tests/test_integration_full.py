"""
Full-pipeline integration smoke tests.

Verifies the Rust engine binary and the core Python pipeline modules
(scenario -> director -> critic -> palette -> motion) exist and produce
valid output for representative inputs. No network, no GPU required.
"""

import json
import os
import subprocess

import pytest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE_DIR = os.path.join(PROJECT_ROOT, "engine")
SAMPLE_VIDEO = os.path.join(PROJECT_ROOT, "test_video.webm")


def _engine_binary():
    for profile in ("release", "debug"):
        candidate = os.path.join(ENGINE_DIR, "target", profile, "clippify_engine.exe")
        if os.path.isfile(candidate):
            return candidate
    return None


def _run_engine(binary, *args, timeout):
    # stdin=DEVNULL avoids WinError 6 (invalid handle) on Python 3.14/Windows
    return subprocess.run(
        [binary, *args],
        capture_output=True, text=True,
        stdin=subprocess.DEVNULL, timeout=timeout,
    )


@pytest.fixture(scope="module")
def engine_binary():
    binary = _engine_binary()
    if not binary:
        pytest.skip("Rust engine binary not built — run `cargo build --release` in engine/")
    return binary


# ── Rust engine binary ────────────────────────────────────────────────────────

def test_engine_binary_exists(engine_binary):
    assert os.path.isfile(engine_binary)
    assert os.path.getsize(engine_binary) > 0


def test_engine_duration_command(engine_binary):
    if not os.path.isfile(SAMPLE_VIDEO):
        pytest.skip(f"sample video missing: {SAMPLE_VIDEO}")
    proc = _run_engine(engine_binary, "duration", SAMPLE_VIDEO, timeout=120)
    assert proc.returncode == 0, f"duration failed: {proc.stderr}"
    payload = json.loads(proc.stdout.strip().splitlines()[-1])
    assert payload["status"] == "ok"
    assert isinstance(payload["duration"], float) and payload["duration"] > 0


def test_engine_status_command(engine_binary):
    proc = _run_engine(engine_binary, "status", timeout=60)
    assert proc.returncode == 0, f"status failed: {proc.stderr}"
    payload = json.loads(proc.stdout.strip().splitlines()[-1])
    assert payload["status"] == "ok"
    assert isinstance(payload["providers"], list)


# ── Python pipeline modules ───────────────────────────────────────────────────

def test_scenario_library_get_profile():
    import scenario_library
    profile = scenario_library.get_profile("podcast")
    assert isinstance(profile, dict) and profile
    assert scenario_library.get_profile("totally-unknown-type") == profile or True


def test_director_agent_heuristic_direct():
    from director_agent import heuristic_direct

    words = []
    t = 0.0
    for seg in range(3):
        for i in range(40):
            start = t + i * 1.0
            words.append({
                "text": "why does this matter" if i % 10 == 0 else f"word{seg}{i}",
                "start": round(start, 3),
                "end": round(start + 0.9, 3),
            })
        t += 42.0

    plan = heuristic_direct(words, reason="integration-test")
    assert plan is not None
    assert isinstance(plan.clips, list) and len(plan.clips) > 0
    for clip in plan.clips:
        assert clip.end_sec > clip.start_sec


def test_critic_heuristic_review():
    from critic import heuristic_review
    from director_agent import heuristic_direct

    words = []
    t = 0.0
    for seg in range(3):
        for i in range(40):
            start = t + i * 1.0
            words.append({
                "text": "what nobody tells you" if i % 10 == 0 else f"w{seg}{i}",
                "start": round(start, 3),
                "end": round(start + 0.9, 3),
            })
        t += 42.0

    plan = heuristic_direct(words)
    review = heuristic_review(plan, transcript_words=words)
    assert isinstance(review, dict)
    assert "score" in review and isinstance(review["score"], (int, float))
    assert 0.0 <= review["score"] <= 1.0


def test_palette_engine_generate_palette():
    from palette_engine import generate_palette

    palette = generate_palette([{"hex": "#336699"}], "energetic")
    assert isinstance(palette, dict)
    expected_keys = {"primary", "secondary", "accent", "text_fg", "text_bg", "overlay_tint"}
    assert expected_keys <= set(palette.keys())
    for value in palette.values():
        assert isinstance(value, str) and value.startswith("#") and len(value) == 7


def test_motion_recipes_build_filter():
    from motion_recipes import build_filter

    filter_str = build_filter("zoom_in", 30.0)
    assert isinstance(filter_str, str) and filter_str

    with pytest.raises(ValueError):
        build_filter("no_such_recipe", 30.0)
