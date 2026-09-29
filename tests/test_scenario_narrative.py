"""
Offline tests for scenario_library.py + narrative_parser.py.
No network, no LLM — parse_narrative uses a mocked llm_fn fixture.
Runs in well under 5 seconds (pure CPU, no heavy imports).
"""

import asyncio
import json

import scenario_library
from narrative_parser import (
    TENSION_SAMPLES,
    heuristic_narrative,
    parse_narrative,
)

PROFILE_TYPES = ["podcast", "comedy", "educational", "gaming", "cooking"]

REQUIRED_FIELDS = [
    "name_ar", "name_en", "hook_strategy", "caption_theme", "zoom_style",
    "color_grade", "sfx_mood", "pacing", "min_clip_sec", "max_clip_sec",
    "broll_density", "emphasis_words_boost",
]

# Fixture the mocked llm_fn returns (deliberately messy: bad scores,
# unsorted key_moments) to prove normalization clamps and sorts.
FIXTURE_JSON = json.dumps({
    "story_beats": [
        {"label": "conflict", "start": 12.4, "end": 30.0},
        {"label": "intro", "start": 0.0, "end": 12.4},
    ],
    "joke_detection": [
        {"setup_text": "I told her I cook",
         "punchline_text": "instant noodles count",
         "punchline_start": 18.2},
    ],
    "tension_curve": [
        {"t": 30.0, "score": 0.5},
        {"t": 0.0, "score": 0.2},
        {"t": 15.0, "score": 1.7},          # out of range → clamp to 1.0
    ],
    "key_moments": [
        {"text": "mid moment", "start": 10.0, "score": 0.5, "reason": "r"},
        {"text": "top moment", "start": 5.0, "score": 2.5, "reason": "peak"},
        {"text": "low moment", "start": 20.0, "score": -3, "reason": "meh"},
    ],
})


def _run(coro):
    return asyncio.run(coro)


def _fake_words():
    """Word-level transcript with a >2s pause and two long words."""
    return [
        {"word": "hello", "start": 0.0, "end": 0.4},
        {"word": "everyone", "start": 0.4, "end": 0.9},
        # pause 0.9 → 3.2 (>2s) must split story beats here
        {"word": "welcome", "start": 3.2, "end": 3.7},
        {"word": "back", "start": 3.7, "end": 4.0},
        {"word": "eeeeeeeee", "start": 4.0, "end": 4.8},      # 0.8s spoken
        {"word": "extraordinary", "start": 4.8, "end": 5.2},  # 13 chars
        {"word": "short", "start": 5.2, "end": 5.5},
    ]


# ─────────────────────────────────────────────────────────────────────────────
#  scenario_library
# ─────────────────────────────────────────────────────────────────────────────

def test_get_profile_all_five_types():
    for ct in PROFILE_TYPES:
        p = scenario_library.get_profile(ct)
        assert isinstance(p, dict), ct
        for field in REQUIRED_FIELDS:
            assert field in p, f"{ct} missing {field}"
        assert p["name_en"] == ct
        assert isinstance(p["name_ar"], str) and p["name_ar"]
        assert isinstance(p["hook_strategy"], str) and len(p["hook_strategy"]) > 10
        assert 0 < p["min_clip_sec"] < p["max_clip_sec"]
        assert p["pacing"] > 0
        assert 0.0 <= p["broll_density"] <= 1.0


def test_get_profile_fallback_unknown_type():
    fallback = scenario_library.get_profile("does_not_exist_xyz")
    assert fallback == scenario_library.get_profile("podcast")


def test_get_profile_fallback_empty_and_none():
    empty = scenario_library.get_profile("")
    assert empty == scenario_library.get_profile("podcast")
    none_case = scenario_library.get_profile(None)
    assert none_case == scenario_library.get_profile("podcast")


def test_get_profile_returns_independent_copy():
    first = scenario_library.get_profile("comedy")
    first["caption_theme"] = "MUTATED"
    second = scenario_library.get_profile("comedy")
    assert second["caption_theme"] != "MUTATED"


def test_list_profiles_contains_all_five():
    listed = scenario_library.list_profiles()
    for ct in PROFILE_TYPES:
        assert ct in listed
    assert listed == sorted(listed)


# ─────────────────────────────────────────────────────────────────────────────
#  heuristic_narrative (pure Python, no LLM)
# ─────────────────────────────────────────────────────────────────────────────

def test_heuristic_beats_split_on_pauses():
    result = heuristic_narrative(_fake_words())
    beats = result["story_beats"]
    assert len(beats) == 2                      # one pause → two beats
    assert beats[0]["end"] <= 1.0               # ends before the gap
    assert beats[1]["start"] >= 3.0             # resumes after the gap
    for beat in beats:
        assert set(beat) == {"label", "start", "end"}
        assert beat["label"]


def test_heuristic_key_moments_long_words():
    result = heuristic_narrative(_fake_words())
    moments = result["key_moments"]
    reasons = {m["reason"] for m in moments}
    texts = {m["text"] for m in moments}
    assert "long_word_duration" in reasons      # eeeeeeeee spoken 0.8s
    assert "long_word" in reasons               # extraordinary = 13 chars
    assert "extraordinary" in texts
    assert "short" not in texts                 # plain word not emphasized
    assert all(0.0 <= m["score"] <= 1.0 for m in moments)
    assert len(moments) <= 5                    # top-5 cap


def test_heuristic_empty_input_returns_empty_sections():
    result = heuristic_narrative([])
    assert set(result.keys()) == {
        "story_beats", "joke_detection", "tension_curve", "key_moments"
    }
    assert all(v == [] for v in result.values())


def test_heuristic_tension_curve_shape():
    result = heuristic_narrative(_fake_words())
    curve = result["tension_curve"]
    assert len(curve) == TENSION_SAMPLES
    ts = [point["t"] for point in curve]
    assert ts == sorted(ts)
    assert all(0.0 <= point["score"] <= 1.0 for point in curve)


def test_heuristic_accepts_tuple_words():
    tuples = [(0.0, 0.4, "hello"), (0.4, 0.9, "everyone"),
              (3.5, 4.5, "extraordinary")]
    result = heuristic_narrative(tuples)
    assert len(result["story_beats"]) == 2
    assert any(m["text"] == "extraordinary"
               for m in result["key_moments"])


# ─────────────────────────────────────────────────────────────────────────────
#  parse_narrative (mocked llm_fn)
# ─────────────────────────────────────────────────────────────────────────────

def test_parse_narrative_with_mocked_llm_json_string():
    async def fake_llm(prompt):
        return FIXTURE_JSON

    result = _run(parse_narrative(_fake_words(), fake_llm))
    assert set(result.keys()) == {
        "story_beats", "joke_detection", "tension_curve", "key_moments"
    }
    # story beats sorted by start despite reversed fixture order
    starts = [b["start"] for b in result["story_beats"]]
    assert starts == sorted(starts)
    assert result["story_beats"][0]["label"] == "intro"
    # jokes passed through
    joke = result["joke_detection"][0]
    assert joke["punchline_text"] == "instant noodles count"
    assert joke["punchline_start"] == 18.2
    # tension scores clamped to [0,1], sorted by t
    assert all(0.0 <= p["score"] <= 1.0 for p in result["tension_curve"])
    ts = [p["t"] for p in result["tension_curve"]]
    assert ts == sorted(ts)
    # key moments: top-5 by score desc, scores clamped
    scores = [m["score"] for m in result["key_moments"]]
    assert scores == sorted(scores, reverse=True)
    assert scores[0] == 1.0 and scores[-1] == 0.0
    assert result["key_moments"][0]["text"] == "top moment"


def test_parse_narrative_llm_returns_parsed_dict():
    async def fake_llm(prompt):
        return json.loads(FIXTURE_JSON)         # like llm_router.ask_json

    result = _run(parse_narrative(_fake_words(), fake_llm))
    assert result["joke_detection"][0]["setup_text"] == "I told her I cook"
    assert len(result["key_moments"]) == 3


def test_parse_narrative_sync_llm_fn():
    def sync_llm(prompt):                       # plain sync function
        return FIXTURE_JSON

    result = _run(parse_narrative(_fake_words(), sync_llm))
    assert len(result["story_beats"]) == 2


def test_parse_narrative_llm_failure_returns_empty_dict():
    class RouterExhausted(Exception):
        pass

    async def failing_llm(prompt):
        raise RouterExhausted("all providers exhausted")

    assert _run(parse_narrative(_fake_words(), failing_llm)) == {}


def test_parse_narrative_garbage_response_returns_empty_dict():
    async def garbage_llm(prompt):
        return "Sorry, I cannot help with that."

    assert _run(parse_narrative(_fake_words(), garbage_llm)) == {}


def test_parse_narrative_prompt_contains_transcript_and_schema():
    captured = {}

    async def spy_llm(prompt):
        captured["prompt"] = prompt
        return FIXTURE_JSON

    _run(parse_narrative(_fake_words(), spy_llm))
    prompt = captured["prompt"]
    assert "hello" in prompt and "extraordinary" in prompt
    for section in ("story_beats", "joke_detection", "tension_curve",
                    "key_moments"):
        assert section in prompt


def test_parse_narrative_heuristic_fallback_flag():
    async def failing_llm(prompt):
        raise RuntimeError("offline")

    result = _run(
        parse_narrative(_fake_words(), failing_llm,
                        use_heuristic_fallback=True)
    )
    assert len(result["story_beats"]) == 2      # came from heuristics
    assert result["key_moments"]
