"""
director_agent.py — Squad-W1B agentic editing brain.

Turns a timestamped transcript into a DirectorPlan: an ordered set of
ClipCandidates plus the reasoning behind them and the virtual editing
tools invoked along the way (cut_at, add_zoom, add_sfx, add_broll,
set_caption_theme).

    from director_agent import direct, heuristic_direct
    plan = await direct(words, "video.mp4", profile, llm_fn)

`llm_fn(prompt) -> str | dict` is fully injectable (sync or async) so the
caller can wire llm_router.ask / ask_json or any test double. The director
runs a refine loop (max 3 iterations): draft plan -> critic.review ->
refine with feedback until score >= 0.6. Any LLM failure degrades to the
pure-Python `heuristic_direct` fallback, which segments the transcript on
speech pauses and ranks windows by hook-keyword density.
"""

import json
from dataclasses import dataclass, field
from typing import Any, Callable, List, Optional

import critic

# scenario_library.py may be delivered by another squad agent — every touch guarded.
try:
    import scenario_library as _scenario_library  # type: ignore
except ImportError:
    _scenario_library = None


APPROVAL_THRESHOLD = 0.6
MAX_ITERATIONS = 3
PAUSE_GAP_SEC = 0.6
DEFAULT_N_CLIPS = 5
DEFAULT_DURATION_SEC = 60.0
TRANSCRIPT_PROMPT_CHARS = 6000

TOOLS = ("cut_at", "add_zoom", "add_sfx", "add_broll", "set_caption_theme")
ZOOM_CYCLE = ("gentle", "dynamic", "punch_in", "slow")
HOOK_KEYWORDS = (
    "secret", "never", "always", "money", "free", "mistake", "worst", "best",
    "shocking", "truth", "why", "how", "stop", "nobody", "everyone", "warning",
    "proof", "insane", "crazy", "hack", "trick", "fail", "win", "love", "hate",
    "fear", "rich", "poor", "fast", "easy", "million", "algorithm", "retention",
)


@dataclass
class ClipCandidate:
    start_sec: float
    end_sec: float
    hook_text: str = ""
    caption_theme: str = ""
    zoom_style: str = "gentle"
    sfx_queries: List[str] = field(default_factory=list)
    broll_query: str = ""
    viral_score: float = 0.5
    confidence: float = 0.5


@dataclass
class DirectorPlan:
    clips: List[ClipCandidate] = field(default_factory=list)
    reasoning: str = ""
    tool_calls_made: List[str] = field(default_factory=list)


# ── helpers ───────────────────────────────────────────────────────────────────

def _clamp01(value: Any, default: float = 0.0) -> float:
    try:
        value = float(value)
    except (TypeError, ValueError):
        return default
    return max(0.0, min(1.0, value))


def _extract_json(raw: Any) -> Any:
    """Tolerant JSON extraction; prefers llm_config.extract_json when present."""
    if isinstance(raw, dict):
        return raw
    text = str(raw).strip()
    try:
        from llm_config import extract_json  # noqa: PLC0415 — optional dep
        return extract_json(text)
    except ImportError:
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


def _normalize_words(transcript_words) -> List[dict]:
    words = []
    for w in transcript_words or []:
        if not isinstance(w, dict):
            continue
        text = str(w.get("text", "")).strip()
        if not text:
            continue
        try:
            start = float(w.get("start", 0.0))
        except (TypeError, ValueError):
            start = 0.0
        try:
            end = float(w.get("end", start + 0.2))
        except (TypeError, ValueError):
            end = start + 0.2
        if end < start:
            end = start + 0.2
        words.append({"text": text, "start": start, "end": end})
    return words


def _scenario_overrides(profile: dict) -> dict:
    if _scenario_library is None or not isinstance(profile, dict):
        return {}
    name = profile.get("scenario")
    if not name:
        return {}
    data = None
    getter = getattr(_scenario_library, "get_scenario", None)
    try:
        if callable(getter):
            data = getter(name)
        else:
            data = getattr(_scenario_library, "SCENARIOS", {}).get(name)
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def _effective_profile(profile: Optional[dict]) -> dict:
    eff = dict(_scenario_overrides(profile or {}))
    for k, v in (profile or {}).items():
        if v not in (None, ""):
            eff[k] = v
    return eff


def _profile_params(profile: dict):
    eff = _effective_profile(profile)
    try:
        n_clips = int(eff.get("n_clips") or eff.get("default_n_clips") or DEFAULT_N_CLIPS)
    except (TypeError, ValueError):
        n_clips = DEFAULT_N_CLIPS
    n_clips = max(1, min(12, n_clips))
    try:
        duration = float(eff.get("clip_duration_sec") or eff.get("default_duration")
                         or DEFAULT_DURATION_SEC)
    except (TypeError, ValueError):
        duration = DEFAULT_DURATION_SEC
    duration = max(5.0, min(180.0, duration))
    return n_clips, duration, eff


# ── prompt building ───────────────────────────────────────────────────────────

def _transcript_summary(transcript_words, max_chars: int = TRANSCRIPT_PROMPT_CHARS) -> str:
    lines = [f"[{w['start']:.1f}s] {w['text']}" for w in transcript_words]
    text = "\n".join(lines)
    return text[:max_chars]


def build_prompt(transcript_words, profile: Optional[dict] = None,
                 feedback: Optional[str] = None) -> str:
    n_clips, duration, eff = _profile_params(profile)
    theme = eff.get("caption_theme") or "auto (match content type)"
    zoom = eff.get("zoom_style") or "gentle"
    content_type = eff.get("content_type") or "podcast"
    parts = [
        "You are the Director of a short-form clipping studio.",
        f"Content type: {content_type} | Target clips: {n_clips} | "
        f"Duration per clip: ~{duration:.0f}s | Caption theme: {theme} | "
        f"Default zoom: {zoom}",
        f"Available tools: {', '.join(TOOLS)}",
        "Timestamped transcript:",
        _transcript_summary(transcript_words),
        "Return ONLY JSON in this exact shape:",
        '{"clips": [{"start_sec": 0.0, "end_sec": 30.0, "hook_text": "...", '
        '"caption_theme": "...", "zoom_style": "none|gentle|dynamic|punch_in", '
        '"sfx_queries": ["..."], "broll_query": "...", "viral_score": 0.0-1.0, '
        '"confidence": 0.0-1.0}], "reasoning": "..."}',
        "Rules: clips must NOT overlap; each clip 15-90s; the first 2s must open "
        "with a question or a bold statement; vary zoom_style across clips; "
        "cover different regions of the video.",
    ]
    if feedback:
        parts.append(f"The critic rejected the previous attempt — fix these issues: {feedback}")
    return "\n".join(parts)


# ── LLM plan parsing ──────────────────────────────────────────────────────────

def candidate_from_dict(data: dict, profile: Optional[dict] = None) -> ClipCandidate:
    profile = profile or {}
    try:
        start = float(data.get("start_sec", data.get("start", 0.0)) or 0.0)
    except (TypeError, ValueError):
        start = 0.0
    try:
        end = float(data.get("end_sec", data.get("end", start)) or start)
    except (TypeError, ValueError):
        end = start
    if end < start:
        start, end = end, start
    sfx = data.get("sfx_queries") or []
    if isinstance(sfx, str):
        sfx = [sfx]
    return ClipCandidate(
        start_sec=round(start, 2),
        end_sec=round(end, 2),
        hook_text=str(data.get("hook_text") or data.get("hook") or ""),
        caption_theme=str(data.get("caption_theme") or profile.get("caption_theme") or ""),
        zoom_style=str(data.get("zoom_style") or profile.get("zoom_style") or "gentle"),
        sfx_queries=[str(s) for s in sfx],
        broll_query=str(data.get("broll_query") or data.get("broll") or ""),
        viral_score=_clamp01(data.get("viral_score"), 0.5),
        confidence=_clamp01(data.get("confidence"), 0.5),
    )


def plan_from_llm(raw: Any, profile: Optional[dict] = None) -> DirectorPlan:
    data = _extract_json(raw)
    if isinstance(data, list):
        data = {"clips": data}
    if not isinstance(data, dict) or not data.get("clips"):
        raise ValueError("LLM plan JSON missing 'clips'")
    clips = [candidate_from_dict(c, profile) for c in data["clips"]
             if isinstance(c, dict)]
    if not clips:
        raise ValueError("LLM plan produced zero valid clips")
    return DirectorPlan(
        clips=clips,
        reasoning=str(data.get("reasoning") or ""),
        tool_calls_made=infer_tool_calls(clips),
    )


def infer_tool_calls(clips: List[ClipCandidate]) -> List[str]:
    found = set()
    for c in clips:
        found.add("cut_at")
        if (getattr(c, "zoom_style", "none") or "none") != "none":
            found.add("add_zoom")
        if getattr(c, "sfx_queries", None):
            found.add("add_sfx")
        if getattr(c, "broll_query", ""):
            found.add("add_broll")
        if getattr(c, "caption_theme", ""):
            found.add("set_caption_theme")
    return [t for t in TOOLS if t in found]


# ── heuristic fallback (no LLM) ───────────────────────────────────────────────

def _split_on_pauses(words: List[dict]) -> List[List[dict]]:
    segments, current = [], [words[0]]
    for prev, w in zip(words, words[1:]):
        if w["start"] - prev["end"] > PAUSE_GAP_SEC:
            segments.append(current)
            current = []
        current.append(w)
    segments.append(current)
    return segments


def _build_windows(words: List[dict], target_dur: float) -> List[List[dict]]:
    windows, buf = [], []
    for seg in _split_on_pauses(words):
        buf.extend(seg)
        if buf[-1]["end"] - buf[0]["start"] >= target_dur:
            windows.append(buf)
            buf = []
    if buf:
        windows.append(buf)
    return windows


def _window_metrics(window: List[dict]) -> dict:
    text = " ".join(w["text"] for w in window)
    low = text.lower()
    hits = sum(1 for k in HOOK_KEYWORDS if k in low) + text.count("?")
    dur = max(0.1, window[-1]["end"] - window[0]["start"])
    density = min(1.0, (len(window) / dur) / 2.5)
    kw_score = min(1.0, hits / 4.0)
    return {
        "text": text, "hits": hits, "duration": dur, "density": density,
        "score": 0.65 * kw_score + 0.35 * density,
    }


def _extract_hook(window: List[dict]) -> str:
    phrase: List[str] = []
    for w in window:
        phrase.append(w["text"])
        if w["text"].endswith(("?", "!")) and len(phrase) >= 3:
            return " ".join(phrase)
        if len(phrase) >= 8:
            break
    return " ".join(phrase[:8])


def heuristic_direct(transcript_words, profile=None, reason: str = "") -> DirectorPlan:
    """No-LLM fallback: pause segmentation + keyword/density scoring, pick top-N."""
    words = _normalize_words(transcript_words)
    suffix = f" ({reason})" if reason else ""
    if not words:
        return DirectorPlan(clips=[], reasoning=f"empty transcript; nothing to direct{suffix}",
                            tool_calls_made=[])
    n_clips, duration, eff = _profile_params(profile)
    theme = str(eff.get("caption_theme") or "TikTok Yellow")
    emphasis = eff.get("emphasis_sfx")
    emphasis_sfx = emphasis[0] if isinstance(emphasis, (list, tuple)) and emphasis else "whoosh"

    windows = _build_windows(words, duration)
    metrics = [_window_metrics(w) for w in windows]
    order = sorted(range(len(windows)),
                   key=lambda i: (-metrics[i]["score"], windows[i][0]["start"]))
    taken: List[int] = []
    for idx in order:
        if any(idx == j for j in taken):
            continue
        w_start, w_end = windows[idx][0]["start"], windows[idx][-1]["end"]
        if any(windows[j][0]["start"] < w_end and w_start < windows[j][-1]["end"]
               for j in taken):
            continue
        taken.append(idx)
        if len(taken) >= n_clips:
            break
    taken.sort(key=lambda i: windows[i][0]["start"])

    clips = []
    for pos, idx in enumerate(taken):
        m = metrics[idx]
        win = windows[idx]
        sfx = [emphasis_sfx] if m["hits"] >= 2 else []
        confidence = 0.5
        if m["hits"]:
            confidence += 0.15
        if m["hits"] >= 3:
            confidence += 0.15
        if m["density"] > 0.5:
            confidence += 0.1
        clips.append(ClipCandidate(
            start_sec=round(win[0]["start"], 2),
            end_sec=round(win[-1]["end"], 2),
            hook_text=_extract_hook(win),
            caption_theme=theme,
            zoom_style=ZOOM_CYCLE[pos % len(ZOOM_CYCLE)],
            sfx_queries=sfx,
            broll_query="",
            viral_score=round(min(1.0, m["score"]), 3),
            confidence=round(min(0.9, confidence), 2),
        ))
    reasoning = (
        f"heuristic fallback: {len(windows)} pause-delimited windows scored by "
        f"hook-keyword density; selected top {len(clips)}{suffix}"
    )
    return DirectorPlan(clips=clips, reasoning=reasoning,
                        tool_calls_made=infer_tool_calls(clips))


# ── main entry point ──────────────────────────────────────────────────────────

async def direct(transcript_words, video_path: str = "", profile: Optional[dict] = None,
                 llm_fn: Optional[Callable[[str], Any]] = None, *,
                 max_iterations: int = MAX_ITERATIONS) -> DirectorPlan:
    """
    Agentic directing loop: ask the LLM for a plan, submit it to the critic,
    refine with the critic's feedback until score >= APPROVAL_THRESHOLD or the
    iteration budget runs out, then return the best plan seen.
    """
    if llm_fn is None or not _normalize_words(transcript_words):
        return heuristic_direct(transcript_words, profile,
                                reason="no llm_fn" if llm_fn is None else "no transcript")

    feedback: Optional[str] = None
    best_plan: Optional[DirectorPlan] = None
    best_score = -1.0
    notes: List[str] = []

    for iteration in range(1, max_iterations + 1):
        prompt = build_prompt(transcript_words, profile, feedback=feedback)
        try:
            plan = plan_from_llm(await _ask(llm_fn, prompt), profile)
        except Exception as exc:
            notes.append(f"iteration{iteration}:llm_failed({type(exc).__name__})")
            break

        try:
            verdict = await critic.review(plan, transcript_words, llm_fn)
        except Exception as exc:
            verdict = {"score": 0.0, "feedback": f"critic crashed: {exc}",
                       "issues": ["critic_error"]}
        score = _clamp01(verdict.get("score"), 0.0)
        plan.tool_calls_made = infer_tool_calls(plan.clips)
        notes.append(f"iteration{iteration}:score={score:.2f}")

        if score > best_score:
            best_plan, best_score = plan, score
        if score >= APPROVAL_THRESHOLD:
            plan.reasoning = (
                f"{plan.reasoning} | approved at iteration {iteration}/{max_iterations} "
                f"(critic score={score:.2f})"
            ).strip(" |")
            return plan

        fb = str(verdict.get("feedback") or "").strip()
        issues = [i for i in (verdict.get("issues") or []) if i]
        feedback = " | ".join(dict.fromkeys(([fb] if fb else []) + issues))

    if best_plan is not None:
        best_plan.reasoning = (
            f"{best_plan.reasoning} | returned best-of-{max_iterations} "
            f"(critic score={best_score:.2f}); notes: {'; '.join(notes)}"
        ).strip(" |")
        return best_plan
    return heuristic_direct(transcript_words, profile, reason="; ".join(notes) or "no plan produced")
