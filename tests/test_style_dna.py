"""
Offline tests for style_dna (editing-fingerprint extraction).
No network, no LLM — extract_style_dna uses mocked llm_fn fixtures.
"""

import asyncio
import json
import os

import pytest

import style_dna
from style_dna import (StyleDNA, heuristic_style_dna, extract_style_dna,
                       style_dna_to_prompt, save_dna, load_dna)


# ---------------------------------------------------------------- fixtures

def _words(opening=("What", "if", "you", "could", "edit", "faster")):
    tail = ("everywhere", "today", "forever")
    return [
        {"text": t, "start": i * 0.5, "end": i * 0.5 + 0.4}
        for i, t in enumerate(opening + tail)
    ]


CLIPS = [
    {"duration": 8.0, "text_overlay": "WAIT FOR IT"},
    {"duration": 6.0, "text_overlay": "no way 😱", "broll": True,
     "sfx": ["whoosh"], "transition": "whip"},
    {"duration": 3.0},
]


@pytest.fixture(autouse=True)
def isolated_library(tmp_path, monkeypatch):
    monkeypatch.setattr(style_dna, "LIBRARY_DIR",
                        str(tmp_path / "dna_lib"))


# ---------------------------------------------------------------- heuristic

def test_heuristic_rhythm_and_pacing():
    dna = heuristic_style_dna(_words(), CLIPS)
    total = 17.0
    assert dna.cut_rhythm == pytest.approx(3 / (total / 60), abs=0.01)
    assert dna.avg_clip_duration == pytest.approx(total / 3, abs=0.01)
    # clips get shorter toward the end → acceleration
    assert dna.pacing_acceleration is True


def test_heuristic_hook_styles():
    assert heuristic_style_dna(_words(), CLIPS).hook_style == "question"
    plain = _words(("This", "is", "a", "normal", "video"))
    assert heuristic_style_dna(plain, CLIPS).hook_style == "statement"
    shock = _words(("Nobody", "tells", "you", "this"))
    assert heuristic_style_dna(shock, CLIPS).hook_style == "shock"


def test_heuristic_captions_case_emoji():
    dna = heuristic_style_dna([], [
        {"duration": 4.0, "text_overlay": "🔥🔥 WOW"},
        {"duration": 4.0, "text_overlay": "AMAZING"},
    ])
    assert dna.caption_case == "upper"
    assert 0 < dna.caption_emoji_density <= 1
    lower = heuristic_style_dna([], [
        {"duration": 4.0, "text_overlay": "chill vibes only"}])
    assert lower.caption_case == "lower"
    assert lower.caption_emoji_density == 0.0


def test_heuristic_broll_sfx_transitions():
    clips = [dict(c) for c in CLIPS]
    clips[2]["transition"] = "fade"          # tie → first-seen max wins
    dna = heuristic_style_dna(_words(), clips)
    assert dna.broll_ratio == pytest.approx(1 / 3, abs=0.001)
    minutes = 17.0 / 60
    assert dna.sfx_density == pytest.approx(1 / minutes, abs=0.05)
    # explicit transitions: whip + fade; untagged clips carry no vote
    assert dna.transition_preference in ("whip", "fade")
    dominant = heuristic_style_dna(
        [], [{"duration": 2.0, "transition": "whip"},
             {"duration": 2.0, "transition": "whip"},
             {"duration": 2.0, "transition": "fade"}])
    assert dominant.transition_preference == "whip"


def test_heuristic_empty_and_degenerate_input():
    dna = heuristic_style_dna([], [])
    assert isinstance(dna, StyleDNA)
    assert dna.cut_rhythm == 0.0
    assert dna.avg_clip_duration == 0.0
    assert dna.hook_style == "statement"
    assert dna.pacing_acceleration is False
    # no acceleration when later clips are longer
    slow = heuristic_style_dna([], [{"duration": 3.0}, {"duration": 9.0}])
    assert slow.pacing_acceleration is False


def test_heuristic_tolerates_start_end_clips_and_tuples():
    dna = heuristic_style_dna([(0.0, 0.5, "How"), (0.5, 1.0, "come")],
                              [{"start": 0.0, "end": 5.0},
                               {"start": 5.0, "end": 11.0}])
    assert dna.avg_clip_duration == pytest.approx(5.5)
    assert dna.hook_style == "question"
    assert dna.cut_rhythm == pytest.approx(2 / (11 / 60), abs=0.01)


# ---------------------------------------------------------------- prompt

def test_style_dna_to_prompt_non_empty_fragment():
    text = style_dna_to_prompt(heuristic_style_dna(_words(), CLIPS))
    assert isinstance(text, str) and len(text) > 100
    assert "STYLE DNA" in text
    assert "cuts/min" in text
    assert "question" in text          # hook style rendered
    assert "whip" in text              # transition rendered


# ---------------------------------------------------------------- persistence

def test_save_load_roundtrip():
    dna = heuristic_style_dna(_words(), CLIPS)
    save_dna(dna, "MrBeast Clone")
    path = style_dna.os.path.join(style_dna.LIBRARY_DIR,
                                  "MrBeast_Clone.json")
    assert os.path.isfile(path)
    with open(path, encoding="utf-8") as fh:
        raw = json.load(fh)
    assert set(raw) == set(StyleDNA.__dataclass_fields__)
    assert load_dna("MrBeast_Clone") == dna


def test_load_missing_raises_and_bad_name_rejected():
    with pytest.raises(FileNotFoundError):
        load_dna("ghost_creator")
    with pytest.raises(ValueError):
        save_dna(StyleDNA(), "../evil")


# ---------------------------------------------------------------- LLM path

def test_extract_with_sync_llm_mock():
    def llm(prompt):
        return json.dumps({"hook_style": "shock", "color_mood": "warm",
                           "cut_rhythm": 42.0})

    dna = asyncio.run(extract_style_dna(_words(), CLIPS, llm))
    assert dna.hook_style == "shock"
    assert dna.color_mood == "warm"
    assert dna.cut_rhythm == 42.0
    # fields the mock omitted come from heuristics
    assert dna.pacing_acceleration is True
    assert dna.transition_preference == "whip"


def test_extract_with_async_llm_dict_response():
    async def llm(prompt):
        assert "TRANSCRIPT" in prompt and "CLIP METADATA" in prompt
        return {"broll_ratio": 0.8, "caption_case": "upper"}

    dna = asyncio.run(extract_style_dna(_words(), CLIPS, llm))
    assert dna.broll_ratio == 0.8
    assert dna.caption_case == "upper"


def test_extract_garbage_falls_back_to_heuristic():
    async def llm(prompt):
        return "sorry, I cannot help with that"

    fallback = heuristic_style_dna(_words(), CLIPS)
    dna = asyncio.run(extract_style_dna(_words(), CLIPS, llm))
    assert dna == fallback


def test_extract_llm_crash_falls_back_to_heuristic():
    def llm(prompt):
        raise RuntimeError("router exhausted")

    fallback = heuristic_style_dna(_words(), CLIPS)
    assert asyncio.run(extract_style_dna(_words(), CLIPS, llm)) == fallback


def test_extract_invalid_values_are_coerced_or_dropped():
    def llm(prompt):
        return json.dumps({
            "hook_style": "vibes",            # invalid enum → dropped
            "broll_ratio": 7.5,               # clamped to 1.0
            "pacing_acceleration": "yes",     # not a bool → dropped
            "cut_rhythm": -5,                 # negative → dropped
        })

    dna = asyncio.run(extract_style_dna(_words(), CLIPS, llm))
    base = heuristic_style_dna(_words(), CLIPS)
    assert dna.hook_style == base.hook_style
    assert dna.cut_rhythm == base.cut_rhythm
    assert dna.pacing_acceleration == base.pacing_acceleration
    assert dna.broll_ratio == 1.0
