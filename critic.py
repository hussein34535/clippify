"""
critic.py — Squad-W1B plan reviewer.

Scores a DirectorPlan the way a top short-form editor would, using five
structural checks (each 0-1, averaged into the total):

    hook_strength — does each clip open (first ~2s) with a question or a
                    bold statement?
    pacing        — are clips within the 15-90s sweet spot?
    variety       — more than one zoom style across the plan?
    overlap       — do clips stay disjoint on the timeline?
    coverage      — do the clips span the video instead of clustering?

    from critic import review, heuristic_review
    verdict = await review(plan, words, llm_fn)   # {score, feedback, issues}

`llm_fn` is optional: when provided, a subjective "would a top editor
approve?" score is blended 50/50 into the structural score. Any LLM failure
is tolerated and `heuristic_review(plan)` remains a pure-Python fallback.
"""

import json
from typing import Any, Callable, List, Optional

try:
    from llm_config import extract_json as _extract_json_impl  # type: ignore
except ImportError:  # pragma: no cover - llm_config is in-repo, guarded anyway
    _extract_json_impl = None


MIN_CLIP_SEC = 15.0
MAX_CLIP_SEC = 90.0
HOOK_WINDOW_SEC = 2.0

BOLD_MARKERS = (
    "never", "always", "stop", "secret", "nobody", "everyone", "truth",
    "million", "%", "percent", "most", "worst", "best", "proven", "shocking",
    "warning", "mistake", "hack", "proof",
)
QUESTION_WORDS = ("what", "why", "how", "who", "when", "which", "should",
                  "could", "would", "is it", "do you", "did you")


def _clamp01(value: Any, default: float = 0.0) -> float:
    try:
        value = float(value)
    except (TypeError, ValueError):
        return default
    return max(0.0, min(1.0, value))


def _extract_json(raw: Any) -> Any:
    if isinstance(raw, dict):
        return raw
    text = str(raw).strip()
    if _extract_json_impl is not None:
        try:
            return _extract_json_impl(text)
        except Exception:
            pass
    if text.startswith("```"):
        parts = text.split("```")
        text = parts[1] if len(parts) > 1 else text
        if text.startswith("json"):
            text = text[4:]
    starts = [i for i in (text.find("{"), text.find("[")) if i != -1]
    if not starts:
        raise ValueError("no JSON found in LLM response")
    start = min(starts)
    end = max(text.rfind("}"), text.rfind("]"))
    return json.loads(text[start:end + 1])


async def _ask(llm_fn: Callable, prompt: str) -> Any:
    out = llm_fn(prompt)
    if hasattr(out, "__await__"):
        out = await out
    return out


def _as_clips(plan: Any) -> List[Any]:
    if plan is None:
        return []
    if isinstance(plan, (list, tuple)):
        candidates = list(plan)
    else:
        candidates = list(getattr(plan, "clips", []) or [])
    return [c for c in candidates if hasattr(c, "start_sec")]


def _clip_seconds(clip) -> float:
    return max(0.0, float(getattr(clip, "end_sec", 0.0)) - float(getattr(clip, "start_sec", 0.0)))


def _normalize_words(transcript_words) -> List[dict]:
    words = []
    for w in transcript_words or []:
        if isinstance(w, dict):
            try:
                start = float(w.get("start", 0.0))
                end = float(w.get("end", start + 0.2))
            except (TypeError, ValueError):
                continue
            words.append({"text": str(w.get("text", "")), "start": start,
                          "end": max(end, start)})
    return words


def _opening_transcript_text(words: List[dict], clip) -> str:
    start = float(getattr(clip, "start_sec", 0.0))
    return " ".join(w["text"] for w in words if start <= w["start"] < start + HOOK_WINDOW_SEC)


def _is_strong_hook(text: str) -> bool:
    low = (text or "").lower().strip()
    if not low:
        return False
    if "?" in text:
        return True
    if any(m in low for m in BOLD_MARKERS):
        return True
    return any(low.startswith(qw) for qw in QUESTION_WORDS)


# ── pure-Python review ────────────────────────────────────────────────────────

def heuristic_review(plan, transcript_words=None) -> dict:
    """Structural scoring only — no network, deterministic."""
    clips = _as_clips(plan)
    if not clips:
        return {"score": 0.0, "feedback": "plan has no clips to review",
                "issues": ["no_clips"]}

    n = len(clips)
    issues: List[str] = []

    # pacing: clips should live in the 15-90s window
    bad_pace = [c for c in clips if not (MIN_CLIP_SEC <= _clip_seconds(c) <= MAX_CLIP_SEC)]
    pacing = 1.0 - len(bad_pace) / n
    for c in bad_pace[:3]:
        issues.append(
            f"pacing:{float(c.start_sec):.0f}-{float(c.end_sec):.0f}s "
            f"({_clip_seconds(c):.0f}s outside {MIN_CLIP_SEC:.0f}-{MAX_CLIP_SEC:.0f}s)"
        )

    # overlap: sorted clips must be disjoint
    ordered = sorted(clips, key=lambda c: float(c.start_sec))
    overlaps = 0
    for i in range(len(ordered) - 1):
        if float(ordered[i + 1].start_sec) < float(ordered[i].end_sec) - 1e-6:
            overlaps += 1
            issues.append(f"overlap:clip{i}/clip{i + 1}")
    overlap_score = 1.0 if not overlaps else max(0.0, 1.0 - overlaps / max(1, n - 1))

    # variety: zoom styles should differ across clips
    styles = {(getattr(c, "zoom_style", "") or "none") for c in clips}
    variety = len(styles) / n
    if len(styles) < 2 and n > 1:
        issues.append(f"variety:single zoom style '{sorted(styles)[0]}' across {n} clips")

    # hook strength: first ~2s of each clip (hook_text + transcript) needs a hook
    words = _normalize_words(transcript_words)
    strong = 0
    for idx, c in enumerate(clips):
        opening = f"{getattr(c, 'hook_text', '')} {_opening_transcript_text(words, c)}"
        if _is_strong_hook(opening):
            strong += 1
        else:
            issues.append(f"weak_hook:clip{idx} first {HOOK_WINDOW_SEC:.0f}s lack a question/bold statement")
    hook_score = strong / n

    # coverage: total seconds covered + spread across timeline quarters
    video_end = max((w["end"] for w in words), default=0.0)
    video_end = max(video_end, max(float(c.end_sec) for c in clips))
    total_covered = sum(_clip_seconds(c) for c in clips)
    span = min(1.0, total_covered / video_end) if video_end > 0 else 1.0
    quarter = max(1e-6, video_end / 4.0)
    touched = {min(3, int(float(c.start_sec) / quarter)) for c in clips}
    touched |= {min(3, int((float(c.end_sec) - 1e-3) / quarter)) for c in clips}
    coverage = round(0.7 * span + 0.3 * (len(touched) / 4.0), 3)
    if coverage < 0.5:
        issues.append(f"coverage:only {total_covered:.0f}s of {video_end:.0f}s video covered")

    score = round((pacing + overlap_score + variety + hook_score + coverage) / 5.0, 3)
    feedback = " | ".join(dict.fromkeys(issues)) if issues else "all structural checks passed"
    return {"score": score, "feedback": feedback, "issues": issues}


# ── LLM-assisted review ───────────────────────────────────────────────────────

def build_editor_prompt(clips: List[Any]) -> str:
    payload = [
        {
            "start_sec": float(c.start_sec),
            "end_sec": float(c.end_sec),
            "duration_sec": round(_clip_seconds(c), 2),
            "hook_text": getattr(c, "hook_text", ""),
            "zoom_style": getattr(c, "zoom_style", ""),
        }
        for c in clips
    ]
    return (
        "You are a senior short-form editor reviewing a cutting plan.\n"
        f"Plan: {json.dumps(payload)}\n"
        "Would a top editor approve this plan? Reply ONLY JSON: "
        '{"approve": true|false, "score": 0.0-1.0, "feedback": "..."}'
    )


async def review(plan, transcript_words=None,
                 llm_fn: Optional[Callable[[str], Any]] = None) -> dict:
    """
    Structural checks always run; with llm_fn a subjective editor score is
    blended 50/50. Returns {score, feedback, issues}.
    """
    base = heuristic_review(plan, transcript_words)
    score, feedback, issues = base["score"], base["feedback"], list(base["issues"])

    if llm_fn is None:
        return {"score": score, "feedback": feedback, "issues": issues}
    try:
        data = _extract_json(await _ask(llm_fn, build_editor_prompt(_as_clips(plan))))
        if isinstance(data, dict) and "score" in data:
            subjective = _clamp01(data.get("score"), score)
            score = round((score + subjective) / 2.0, 3)
            editor_fb = str(data.get("feedback") or "").strip()
            if editor_fb:
                feedback = " | ".join([editor_fb, feedback])
    except Exception:
        pass  # subjective hop is best-effort; structural verdict stands
    return {"score": score, "feedback": feedback, "issues": issues}
