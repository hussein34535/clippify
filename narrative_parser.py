"""
narrative_parser.py — Story-level understanding of a transcript.

    from narrative_parser import parse_narrative, heuristic_narrative

    result = await parse_narrative(words, llm_router.ask_json)
    # {
    #   "story_beats":     [{label, start, end}, ...],
    #   "joke_detection":  [{setup_text, punchline_text, punchline_start}, ...],
    #   "tension_curve":   [{t, score(0..1)}, ...],
    #   "key_moments":     [{text, start, score, reason}, ...]   # top-5
    # }

parse_narrative sends the word-level transcript to the injected llm_fn
(sync or async — e.g. llm_router.ask / .ask_json) and parses its JSON.
Any LLM or parsing failure returns {} (callers decide what to do).

heuristic_narrative is the pure-Python fallback (no LLM): pauses > 2s
become beat boundaries, unusually long words become emphasis moments,
and the tension curve is derived from local speaking density.

Word input is tolerant: each item may be a dict {"word"/"text", "start",
"end"} or a (start, end, text) tuple. Timestamps are seconds.
"""

import asyncio
import json

# ─────────────────────────────────────────────────────────────────────────────
#  Tunables
# ─────────────────────────────────────────────────────────────────────────────

PAUSE_BEAT_SEC = 2.0        # gap between words that starts a new story beat
LONG_WORD_SEC = 0.6         # spoken duration marking an emphasized word
LONG_WORD_CHARS = 10        # char length marking an emphasized word
MAX_KEY_MOMENTS = 5
MAX_PROMPT_WORDS = 600      # cap tokens sent to the LLM
TENSION_SAMPLES = 24        # points in the heuristic tension curve
EMPTY_NARRATIVE = {
    "story_beats": [],
    "joke_detection": [],
    "tension_curve": [],
    "key_moments": [],
}


# ─────────────────────────────────────────────────────────────────────────────
#  Word normalization helpers
# ─────────────────────────────────────────────────────────────────────────────

def _norm_words(transcript_words):
    """Normalize raw word items to [{"text", "start", "end"}], sorted by start."""
    out = []
    if not isinstance(transcript_words, (list, tuple)):
        return out
    for item in transcript_words:
        try:
            if isinstance(item, dict):
                text = str(item.get("word") or item.get("text") or "").strip()
                start = float(item.get("start", 0.0))
                end = float(item.get("end", start))
            elif isinstance(item, (list, tuple)) and len(item) >= 3:
                start = float(item[0])
                end = float(item[1])
                text = str(item[2]).strip()
            else:
                continue
        except (TypeError, ValueError):
            continue
        if not text:
            continue
        out.append({"text": text, "start": max(0.0, start),
                    "end": max(start, end)})
    out.sort(key=lambda w: w["start"])
    return out


def _as_float(value, default=None):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp01(value):
    return max(0.0, min(1.0, value))


# ─────────────────────────────────────────────────────────────────────────────
#  LLM path
# ─────────────────────────────────────────────────────────────────────────────

def _build_prompt(words):
    lines = []
    for w in words[:MAX_PROMPT_WORDS]:
        lines.append(f"[{w['start']:.2f}-{w['end']:.2f}] {w['text']}")
    transcript_block = "\n".join(lines)
    return (
        "You are a video narrative analyst. Below is a word-level transcript "
        "(seconds). Analyze its storytelling structure and respond with ONLY "
        "valid JSON (no markdown, no commentary) shaped exactly like this:\n"
        "{\n"
        '  "story_beats": [{"label": "...", "start": 0.0, "end": 0.0}],\n'
        '  "joke_detection": [{"setup_text": "...", "punchline_text": "...", '
        '"punchline_start": 0.0}],\n'
        '  "tension_curve": [{"t": 0.0, "score": 0.0}],\n'
        '  "key_moments": [{"text": "...", "start": 0.0, "score": 0.0, '
        '"reason": "..."}]\n'
        "}\n"
        "Rules: tension scores are floats in [0,1]; key_moments are the top 5 "
        "most clip-worthy moments sorted by score; story_beats cover the whole "
        "timeline in order.\n\n"
        "TRANSCRIPT:\n" + transcript_block
    )


def _extract_json(text):
    """Best-effort JSON extraction from an LLM string response."""
    if isinstance(text, dict):
        return text
    if not isinstance(text, str):
        raise ValueError("llm_fn returned non-string/non-dict")
    t = text.strip()
    if t.startswith("```"):
        t = t.split("```")[1]
        if t.startswith("json"):
            t = t[4:]
    start = min([i for i in (t.find("{"), t.find("[")) if i != -1],
                default=-1)
    if start == -1:
        raise ValueError("no JSON found in LLM response")
    end = max(t.rfind("}"), t.rfind("]"))
    return json.loads(t[start:end + 1])


def _normalize(data):
    """Validate + coerce parsed LLM output; invalid entries are dropped."""
    if not isinstance(data, dict):
        return {}
    out = {}

    beats = []
    for b in data.get("story_beats") or []:
        if not isinstance(b, dict):
            continue
        start, end = _as_float(b.get("start")), _as_float(b.get("end"))
        label = str(b.get("label") or "").strip()
        if start is None or end is None:
            continue
        beats.append({"label": label or "beat",
                      "start": start, "end": max(start, end)})
    out["story_beats"] = sorted(beats, key=lambda b: b["start"])

    jokes = []
    for j in data.get("joke_detection") or []:
        if not isinstance(j, dict):
            continue
        setup = str(j.get("setup_text") or "").strip()
        punch = str(j.get("punchline_text") or "").strip()
        pstart = _as_float(j.get("punchline_start"))
        if not punch:
            continue
        jokes.append({"setup_text": setup, "punchline_text": punch,
                      "punchline_start": pstart if pstart is not None else 0.0})
    out["joke_detection"] = jokes

    curve = []
    for point in data.get("tension_curve") or []:
        if not isinstance(point, dict):
            continue
        t, score = _as_float(point.get("t")), _as_float(point.get("score"))
        if t is None or score is None:
            continue
        curve.append({"t": t, "score": _clamp01(score)})
    out["tension_curve"] = sorted(curve, key=lambda p: p["t"])

    moments = []
    for m in data.get("key_moments") or []:
        if not isinstance(m, dict):
            continue
        text = str(m.get("text") or "").strip()
        start = _as_float(m.get("start"))
        score = _as_float(m.get("score"))
        if not text or start is None:
            continue
        moments.append({"text": text, "start": start,
                        "score": _clamp01(score if score is not None else 0.0),
                        "reason": str(m.get("reason") or "").strip()})
    moments.sort(key=lambda m: (-m["score"], m["start"]))
    out["key_moments"] = moments[:MAX_KEY_MOMENTS]

    return out


async def _maybe_await(fn_result):
    if asyncio.isfuture(fn_result) or asyncio.iscoroutine(fn_result):
        return await fn_result
    return fn_result


async def parse_narrative(transcript_words: list, llm_fn,
                          use_heuristic_fallback: bool = False) -> dict:
    """
    Analyze a word-level transcript into story structure via `llm_fn`.

    llm_fn may be sync or async and may return a JSON string or an
    already-parsed dict. Returns {} when the LLM call or JSON parsing
    fails entirely. With use_heuristic_fallback=True, a total failure
    returns heuristic_narrative() instead of {}.
    """
    words = _norm_words(transcript_words)
    prompt = _build_prompt(words)
    try:
        raw = await _maybe_await(llm_fn(prompt))
        data = _extract_json(raw)
    except Exception:
        if use_heuristic_fallback:
            return heuristic_narrative(words)
        return {}
    normalized = _normalize(data)
    if use_heuristic_fallback and not normalized:
        return heuristic_narrative(words)
    return normalized


# ─────────────────────────────────────────────────────────────────────────────
#  Pure-Python heuristic fallback (no LLM)
# ─────────────────────────────────────────────────────────────────────────────

def heuristic_narrative(transcript_words) -> dict:
    """
    No-LLM narrative estimate: pauses > 2s split story beats, long-spoken /
    long-written words mark emphasis, tension follows local speech density.
    Always returns all four sections (empty lists for empty input).
    """
    result = {k: [] for k in EMPTY_NARRATIVE}
    words = transcript_words if (
        transcript_words and isinstance(transcript_words[0], dict)
        and "text" in transcript_words[0]
    ) else _norm_words(transcript_words)
    if not words:
        return result

    # ── story beats: pause gaps > PAUSE_BEAT_SEC become boundaries ──
    beat_spans = []
    seg_start_idx = 0
    for i in range(1, len(words)):
        if words[i]["start"] - words[i - 1]["end"] > PAUSE_BEAT_SEC:
            beat_spans.append((seg_start_idx, i - 1))
            seg_start_idx = i
    beat_spans.append((seg_start_idx, len(words) - 1))
    result["story_beats"] = [
        {
            "label": " ".join(w["text"] for w in words[a:b + 1][:5]),
            "start": round(words[a]["start"], 3),
            "end": round(words[b]["end"], 3),
        }
        for a, b in beat_spans
    ]

    # ── key moments: long words = emphasis ──
    duration = max(w["end"] for w in words)
    scored = []
    for w in words:
        span = w["end"] - w["start"]
        if span >= LONG_WORD_SEC:
            reason, score = "long_word_duration", _clamp01(span / 2.0)
        elif len(w["text"]) >= LONG_WORD_CHARS:
            reason, score = "long_word", _clamp01(len(w["text"]) / 20.0)
        else:
            continue
        scored.append({"text": w["text"], "start": round(w["start"], 3),
                       "score": round(max(score, 0.3), 3), "reason": reason})
    scored.sort(key=lambda m: (-m["score"], m["start"]))
    result["key_moments"] = scored[:MAX_KEY_MOMENTS]

    # ── tension curve: local speech density over TENSION_SAMPLES buckets ──
    total = duration or 1.0
    step = total / TENSION_SAMPLES
    for k in range(TENSION_SAMPLES):
        lo, hi = k * step, (k + 1) * step
        count = sum(1 for w in words if lo <= w["start"] < hi)
        density = count / max((hi - lo) * 3.0, 1e-6)   # ~3 words/sec = calm
        emphasis = sum(
            1 for m in result["key_moments"] if lo <= m["start"] < hi
        )
        score = _clamp01(density * 0.7 + emphasis * 0.15)
        result["tension_curve"].append({"t": round(lo, 3),
                                        "score": round(score, 3)})

    return result
