"""
Tests for Squad-W1B director_agent + critic.

All async entry points are exercised through asyncio.run() inside sync tests
(no pytest-asyncio dependency). LLM behaviour is simulated with prompt-routing
test doubles: the director's prompt starts with "You are the Director", the
critic's with "You are a senior short-form editor".
"""

import asyncio
import json

from critic import heuristic_review, review
from director_agent import (
    ClipCandidate,
    build_prompt,
    direct,
    heuristic_direct,
)

PROFILE = {
    "content_type": "podcast",
    "n_clips": 3,
    "clip_duration_sec": 8.0,
    "caption_theme": "TikTok Yellow",
}

SENTENCES = [
    "What if I told you the secret nobody tells you ?",
    "Most creators burn out because they chase views instead of systems .",
    "Here is the money trick that changed everything for me .",
    "Everyone thinks you need luck but the proof says otherwise .",
    "Stop posting daily and start posting with intent .",
    "The algorithm rewards watch time not hashtags .",
    "My worst video got a million views for one reason .",
    "Never open a video with your name or a greeting .",
    "Cut the intro and the people stay till the end .",
    "This hack doubled my retention in a week .",
    "Why does nobody talk about the first two seconds ?",
    "Because that is where the fear lives and the scroll dies .",
]

GOOD_PLAN_JSON = json.dumps({
    "clips": [
        {"start_sec": 0.0, "end_sec": 30.0,
         "hook_text": "Why do most creators quit before month six ?",
         "caption_theme": "TikTok Yellow", "zoom_style": "gentle",
         "sfx_queries": ["whoosh"], "broll_query": "",
         "viral_score": 0.9, "confidence": 0.85},
        {"start_sec": 40.0, "end_sec": 80.0,
         "hook_text": "Nobody tells you this secret about the algorithm",
         "caption_theme": "TikTok Yellow", "zoom_style": "dynamic",
         "sfx_queries": [], "broll_query": "data screens",
         "viral_score": 0.88, "confidence": 0.8},
    ],
    "reasoning": "two strongest narrative arcs",
})

BAD_PLAN_JSON = json.dumps({
    "clips": [
        {"start_sec": 10.0, "end_sec": 13.0,
         "hook_text": "hey guys welcome back", "zoom_style": "punch_in"},
        {"start_sec": 12.0, "end_sec": 210.0,
         "hook_text": "another day another video", "zoom_style": "punch_in"},
    ],
    "reasoning": "idk just take everything",
})


def _mk_words(sentences=None, word_step=0.3, pause=1.0):
    words, t = [], 0.0
    for sentence in (sentences or SENTENCES):
        for token in sentence.split():
            words.append({"text": token, "start": round(t, 2), "end": round(t + 0.28, 2)})
            t += word_step
        t += pause
    return words


def _words_spanning(total_sec, step=0.33):
    words, t, i = [], 0.0, 0
    while t < total_sec:
        words.append({"text": f"w{i}", "start": round(t, 2), "end": round(min(t + step, total_sec), 2)})
        t += step
        i += 1
    return words


def make_llm(director_responses):
    """Prompt-routed double: honest critic scoring + scripted director replies."""
    state = {"dir": 0, "prompts": []}

    def llm(prompt):
        state["prompts"].append(prompt)
        if prompt.startswith("You are the Director"):
            i = state["dir"]
            state["dir"] += 1
            # replay the last scripted response when the script runs dry
            item = director_responses[min(i, len(director_responses) - 1)]
            if isinstance(item, Exception):
                raise item
            return item
        # critic side — evaluate the embedded plan honestly
        if '"start_sec": 40' in prompt:
            return '{"approve": true, "score": 0.95, "feedback": "clean cuts"}'
        return '{"approve": false, "score": 0.1, "feedback": "restructure the timeline"}'

    llm.state = state
    return llm


def _director_prompts(state):
    return [p for p in state["prompts"] if p.startswith("You are the Director")]


# ── heuristic_direct ──────────────────────────────────────────────────────────

def test_heuristic_direct_shapes_valid_clips():
    words = _mk_words()
    plan = heuristic_direct(words, PROFILE)
    assert plan.clips, "heuristic must produce at least one clip"
    assert len(plan.clips) <= PROFILE["n_clips"]
    starts = [c.start_sec for c in plan.clips]
    assert starts == sorted(starts), "clips must be chronological"
    for c in plan.clips:
        assert c.end_sec > c.start_sec
        assert 0.0 <= c.viral_score <= 1.0
        assert 0.0 <= c.confidence <= 1.0
        assert c.caption_theme == "TikTok Yellow"
    for a, b in zip(plan.clips, plan.clips[1:]):
        assert a.end_sec <= b.start_sec, "heuristic clips must not overlap"
    assert "cut_at" in plan.tool_calls_made
    styles = {c.zoom_style for c in plan.clips}
    assert len(styles) == len(plan.clips), "zoom cycle should rotate styles"
    assert plan.reasoning


def test_heuristic_direct_empty_transcript_is_safe():
    plan = heuristic_direct([], PROFILE)
    assert plan.clips == []
    assert plan.reasoning
    assert plan.tool_calls_made == []


def test_build_prompt_mentions_tools_and_feedback():
    words = _mk_words()
    base = build_prompt(words, PROFILE)
    assert "cut_at" in base and "add_broll" in base and '"clips"' in base
    refined = build_prompt(words, PROFILE, feedback="fix overlap")
    assert "fix overlap" in refined
    assert refined != base


# ── heuristic_review ──────────────────────────────────────────────────────────

def _good_plan():
    return [
        ClipCandidate(start_sec=0.0, end_sec=30.0,
                      hook_text="Why do most creators quit before month six ?",
                      zoom_style="gentle"),
        ClipCandidate(start_sec=40.0, end_sec=80.0,
                      hook_text="Nobody tells you this secret about the algorithm",
                      zoom_style="dynamic"),
    ]


def _bad_plan():
    return [
        ClipCandidate(start_sec=10.0, end_sec=13.0,
                      hook_text="hey guys welcome back", zoom_style="punch_in"),
        ClipCandidate(start_sec=12.0, end_sec=210.0,
                      hook_text="another day another video", zoom_style="punch_in"),
    ]


def test_heuristic_review_good_plan_scores_high():
    verdict = heuristic_review(_good_plan(), _words_spanning(100))
    assert verdict["score"] >= 0.75
    assert not any("overlap" in i or "pacing" in i for i in verdict["issues"])


def test_heuristic_review_flags_bad_plan_issues():
    verdict = heuristic_review(_bad_plan(), _words_spanning(220))
    joined = " ".join(verdict["issues"])
    assert verdict["score"] < 0.6
    assert "overlap" in joined
    assert "pacing" in joined
    assert "variety" in joined
    assert "weak_hook" in joined


def test_heuristic_review_empty_plan_scores_zero():
    verdict = heuristic_review([])
    assert verdict["score"] == 0.0
    assert verdict["issues"] == ["no_clips"]


# ── direct() with mocked llm_fn ───────────────────────────────────────────────

def test_direct_with_mocked_llm_single_iteration():
    words = _mk_words()
    llm = make_llm([GOOD_PLAN_JSON])
    plan = asyncio.run(direct(words, "video.mp4", PROFILE, llm))
    assert llm.state["dir"] == 1, "approved plan must not trigger extra iterations"
    assert len(plan.clips) == 2
    assert plan.clips[1].start_sec == 40.0
    assert plan.clips[1].broll_query == "data screens"
    for tool in ("cut_at", "add_zoom", "add_sfx", "add_broll", "set_caption_theme"):
        assert tool in plan.tool_calls_made
    assert "approved" in plan.reasoning.lower()


def test_direct_accepts_async_llm_fn():
    words = _mk_words()

    async def llm(prompt):
        return GOOD_PLAN_JSON

    plan = asyncio.run(direct(words, "video.mp4", PROFILE, llm))
    assert len(plan.clips) == 2


def test_direct_refine_loop_triggers_second_iteration():
    words = _mk_words()
    llm = make_llm([BAD_PLAN_JSON, GOOD_PLAN_JSON])
    plan = asyncio.run(direct(words, "video.mp4", PROFILE, llm))
    prompts = _director_prompts(llm.state)
    assert len(prompts) == 2, "critic rejection must trigger exactly one refinement"
    assert "overlap" in prompts[1], "second attempt must carry the critic feedback"
    assert len(plan.clips) == 2
    assert plan.clips[1].start_sec == 40.0
    assert "approved" in plan.reasoning.lower()


def test_direct_all_iterations_fail_returns_best_effort():
    words = _mk_words()
    llm = make_llm([BAD_PLAN_JSON])
    plan = asyncio.run(direct(words, "video.mp4", PROFILE, llm))
    assert llm.state["dir"] == 3, "must exhaust the full iteration budget"
    assert plan.clips, "best-of-N plan still returned"


def test_direct_falls_back_to_heuristic_when_llm_down():
    words = _mk_words()

    def dead_llm(prompt):
        raise RuntimeError("all providers exhausted")

    plan = asyncio.run(direct(words, "video.mp4", PROFILE, dead_llm))
    assert plan.clips, "fallback plan must contain clips from the transcript"
    assert "llm_failed" in plan.reasoning
    assert "cut_at" in plan.tool_calls_made


# ── review() blending ─────────────────────────────────────────────────────────

def test_review_blends_subjective_editor_score():
    words = _words_spanning(220)
    plan = _bad_plan()
    structural = heuristic_review(plan, words)["score"]

    def pessimist(prompt):
        return '{"approve": false, "score": 0.2, "feedback": "too slow"}'

    verdict = asyncio.run(review(plan, words, pessimist))
    expected = round((structural + 0.2) / 2.0, 3)
    assert abs(verdict["score"] - expected) < 1e-6
    assert "too slow" in verdict["feedback"]
    assert verdict["issues"], "structural issues must survive the blend"


def test_review_survives_llm_crash():
    words = _words_spanning(100)
    plan = _good_plan()
    structural = heuristic_review(plan, words)

    def exploding(prompt):
        raise RuntimeError("router down")

    verdict = asyncio.run(review(plan, words, exploding))
    assert verdict["score"] == structural["score"]
    assert verdict["issues"] == structural["issues"]
