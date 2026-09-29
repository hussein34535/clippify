"""
style_dna.py — Clone a creator's editing fingerprint from transcript + metadata.

    from style_dna import StyleDNA, extract_style_dna, style_dna_to_prompt
    from style_dna import heuristic_style_dna, save_dna, load_dna

    dna = await extract_style_dna(words, clip_meta, llm_router.ask_json)
    prompt_fragment = style_dna_to_prompt(dna)   # feed to the Director Agent

extract_style_dna sends the transcript + clip metadata (durations, gaps,
text overlays) to the injected llm_fn (sync or async — e.g.
llm_router.ask_json) and parses its JSON into a validated StyleDNA.
Fields the LLM omits or garbles fall back to the pure-Python
heuristic_style_dna estimate; a total LLM failure returns the heuristic
unchanged.

heuristic_style_dna needs no LLM:
    cut_rhythm           = len(clips) / (total_duration / 60)
    avg_clip_duration    = mean of clip durations
    hook_style           = "question" if first clip starts with question words
    pacing_acceleration  = later clips are shorter than earlier ones
plus caption case/emoji density, b-roll ratio, SFX density and transition
preference derived from overlay/sfx/broll keys in clip_metadata.

save_dna/load_dna persist fingerprints to style_dna_library/{name}.json
so creators' styles can be reused across sessions.

Word input is tolerant: each item may be a dict {"word"/"text", "start",
"end"} or a (start, end, text) tuple — same contract as narrative_parser.
Clip input is tolerant: each dict may carry "duration" directly or
"start"/"end"; optional "text_overlay(s)", "sfx", "broll", "transition",
"gap", "color_mood"/"mood" keys refine the heuristic.
"""

import asyncio
import json
import os
import re
from dataclasses import asdict, dataclass

# ─────────────────────────────────────────────────────────────────────────────
#  Tunables
# ─────────────────────────────────────────────────────────────────────────────

LIBRARY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "style_dna_library")
MAX_PROMPT_WORDS = 400        # cap tokens of transcript sent to the LLM
QUESTION_WORDS = ("what", "why", "how", "who", "when", "where", "which",
                  "whose", "do you", "did you", "have you", "can you",
                  "could you", "will you", "are you", "is it", "is this",
                  "ever wondered")
SHOCK_WORDS = ("insane", "crazy", "shocking", "unbelievable", "nobody",
               "warning", "stop doing", "worst", "never do", "you won't")
STORY_STARTERS = ("so ", "one day", "back when", "story time",
                  "yesterday", "last week", "last year", "when i was")
_EMOJI_RE = re.compile(
    "[\U0001F300-\U0001FAFF\U0001F000-\U0001F0FF\u2600-\u27BF\u2B00-\u2BFF"
    "\U0001F900-\U0001F9FF\ufe0f]"
)

VALID_HOOKS = ("question", "statement", "shock", "story")
VALID_CASES = ("upper", "lower", "mixed")
VALID_MOODS = ("warm", "cool", "neutral", "high_contrast")
VALID_TRANSITIONS = ("cut", "fade", "whip")


# ─────────────────────────────────────────────────────────────────────────────
#  Data model
# ─────────────────────────────────────────────────────────────────────────────

@dataclass
class StyleDNA:
    """A creator's editing fingerprint."""
    cut_rhythm: float = 0.0            # cuts per minute
    avg_clip_duration: float = 0.0     # seconds
    hook_style: str = "statement"      # question | statement | shock | story
    caption_emoji_density: float = 0.0  # 0-1 emoji chars per caption char
    caption_case: str = "mixed"        # upper | lower | mixed
    color_mood: str = "neutral"        # warm | cool | neutral | high_contrast
    pacing_acceleration: bool = False  # pacing increases toward the end?
    sfx_density: float = 0.0           # sound effects per minute
    broll_ratio: float = 0.0           # 0-1 share of clips that are b-roll
    transition_preference: str = "cut"  # cut | fade | whip


def _as_float(value, default=None):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp01(value):
    return max(0.0, min(1.0, value))


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


def _clip_field(clip, *names):
    for n in names:
        if n in clip:
            return clip[n]
    return None


def _clip_durations(clips):
    """Durations in seconds from dicts carrying duration or start/end."""
    durations = []
    if not isinstance(clips, (list, tuple)):
        return durations
    for c in clips:
        if not isinstance(c, dict):
            continue
        d = _as_float(_clip_field(c, "duration"))
        if d is None:
            start, end = _as_float(c.get("start")), _as_float(c.get("end"))
            d = (end - start) if (start is not None and end is not None
                                  and end > start) else None
        if d is not None and d >= 0:
            durations.append(d)
    return durations


def _overlay_texts(clips):
    texts = []
    if not isinstance(clips, (list, tuple)):
        return texts
    for c in clips:
        if not isinstance(c, dict):
            continue
        raw = (_clip_field(c, "text_overlays", "text_overlay")
               or _clip_field(c, "overlays", "caption") or "")
        items = raw if isinstance(raw, (list, tuple)) else [raw]
        for t in items:
            t = str(t).strip()
            if t:
                texts.append(t)
    return texts


# ─────────────────────────────────────────────────────────────────────────────
#  Pure-Python heuristic fallback (no LLM)
# ─────────────────────────────────────────────────────────────────────────────

def _classify_hook(opening_text):
    t = opening_text.lower().strip()
    if any(t.startswith(w) or w in t[:40] for w in QUESTION_WORDS):
        return "question"
    if any(w in t[:40] for w in SHOCK_WORDS):
        return "shock"
    if any(t.startswith(s) for s in STORY_STARTERS):
        return "story"
    return "statement"


def heuristic_style_dna(transcript_words, clip_metadata=None) -> StyleDNA:
    """
    No-LLM editing-fingerprint estimate. Always returns a fully populated
    StyleDNA (defaults for empty/degenerate input).
    """
    clips = clip_metadata if isinstance(clip_metadata, list) else []
    words = _norm_words(transcript_words)
    durations = _clip_durations(clips)
    overlays = _overlay_texts(clips)

    total_duration = sum(durations)
    minutes = total_duration / 60.0
    dna = StyleDNA()

    # ── rhythm ──
    if minutes > 0:
        dna.cut_rhythm = round(len(durations) / minutes, 3)
    if durations:
        dna.avg_clip_duration = round(total_duration / len(durations), 3)

    # ── hook: what does the video open with? ──
    opening_parts = []
    if clips and isinstance(clips[0], dict):
        first_overlay = _overlay_texts([clips[0]])
        if first_overlay:
            opening_parts.extend(first_overlay)
    opening_parts.extend(w["text"] for w in words[:8])
    if opening_parts:
        dna.hook_style = _classify_hook(" ".join(opening_parts))

    # ── captions ──
    joined = " ".join(overlays)
    letters = re.sub(r"[^a-zA-Z]", "", joined)
    if letters:
        if letters.isupper():
            dna.caption_case = "upper"
        elif letters.islower():
            dna.caption_case = "lower"
        else:
            dna.caption_case = "mixed"
        emojis = len(_EMOJI_RE.findall(joined))
        dna.caption_emoji_density = round(
            _clamp01(emojis / max(len(joined), 1)), 4)

    # ── color mood (explicit metadata only; visuals are invisible here) ──
    for c in clips:
        mood = (_clip_field(c, "color_mood", "mood") if isinstance(c, dict)
                else None)
        if mood and str(mood).strip().lower() in VALID_MOODS:
            dna.color_mood = str(mood).strip().lower()
            break

    # ── pacing acceleration: later clips shorter than earlier ones? ──
    if len(durations) >= 2:
        mid = max(len(durations) // 2, 1)
        early, late = durations[:mid], durations[mid:]
        if late and (sum(late) / len(late)) < (sum(early) / len(early)):
            dna.pacing_acceleration = True

    # ── sfx density ──
    sfx_count = 0
    for c in clips:
        if not isinstance(c, dict):
            continue
        sfx = c.get("sfx")
        if isinstance(sfx, (list, tuple)):
            sfx_count += len(sfx)
        elif sfx:
            sfx_count += 1
    if minutes > 0 and sfx_count:
        dna.sfx_density = round(sfx_count / minutes, 3)

    # ── b-roll ratio ──
    flagged = [c for c in clips
               if isinstance(c, dict) and c.get("broll")]
    if clips:
        dna.broll_ratio = round(_clamp01(len(flagged) / len(clips)), 3)

    # ── transitions: most frequent valid marker wins ──
    counts = {}
    for c in clips:
        t = c.get("transition") if isinstance(c, dict) else None
        t = str(t).strip().lower() if t else None
        if t in VALID_TRANSITIONS:
            counts[t] = counts.get(t, 0) + 1
    if counts:
        dna.transition_preference = max(counts, key=counts.get)

    return dna


# ─────────────────────────────────────────────────────────────────────────────
#  LLM path
# ─────────────────────────────────────────────────────────────────────────────

def _build_prompt(transcript_words, clip_metadata):
    words = _norm_words(transcript_words)
    lines = [f"[{w['start']:.2f}-{w['end']:.2f}] {w['text']}"
             for w in words[:MAX_PROMPT_WORDS]]
    compact_clips = []
    for c in (clip_metadata if isinstance(clip_metadata, list) else []):
        if isinstance(c, dict):
            compact_clips.append({
                k: c[k] for k in sorted(c)
                if k in ("duration", "start", "end", "gap", "text_overlay",
                         "text_overlays", "overlays", "sfx", "broll",
                         "transition", "color_mood", "mood")
            })
    meta_block = json.dumps(compact_clips, ensure_ascii=False)
    schema = (
        "{\n"
        '  "cut_rhythm": 0.0,\n'
        '  "avg_clip_duration": 0.0,\n'
        '  "hook_style": "question|statement|shock|story",\n'
        '  "caption_emoji_density": 0.0,\n'
        '  "caption_case": "upper|lower|mixed",\n'
        '  "color_mood": "warm|cool|neutral|high_contrast",\n'
        '  "pacing_acceleration": false,\n'
        '  "sfx_density": 0.0,\n'
        '  "broll_ratio": 0.0,\n'
        '  "transition_preference": "cut|fade|whip"\n'
        "}\n"
    )
    return (
        "You are a senior video editor analyzing another creator's editing "
        "style fingerprint. Below are a word-level transcript (seconds) and "
        "the resulting clip metadata (durations, gaps, text overlays, sfx, "
        "b-roll flags, transitions). Infer their editing DNA and respond with "
        "ONLY valid JSON (no markdown, no commentary) shaped exactly like "
        "this:\n" + schema +
        "Rules: cut_rhythm = cuts per minute; avg_clip_duration in seconds; "
        "caption_emoji_density and broll_ratio are floats in [0,1]; "
        "pacing_acceleration is true when clips get shorter toward the end.\n\n"
        "CLIP METADATA:\n" + meta_block + "\n\n"
        "TRANSCRIPT:\n" + "\n".join(lines)
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


async def _maybe_await(fn_result):
    if asyncio.isfuture(fn_result) or asyncio.iscoroutine(fn_result):
        return await fn_result
    return fn_result


def _merge_llm_into(base, data):
    """Apply valid LLM fields on top of a heuristic base StyleDNA."""
    if not isinstance(data, dict):
        return base
    v = data.get("cut_rhythm")
    f = _as_float(v)
    if f is not None and f >= 0:
        base.cut_rhythm = round(f, 3)
    v = data.get("avg_clip_duration")
    f = _as_float(v)
    if f is not None and f >= 0:
        base.avg_clip_duration = round(f, 3)
    v = str(data.get("hook_style") or "").strip().lower()
    if v in VALID_HOOKS:
        base.hook_style = v
    v = _as_float(data.get("caption_emoji_density"))
    if v is not None:
        base.caption_emoji_density = round(_clamp01(v), 4)
    v = str(data.get("caption_case") or "").strip().lower()
    if v in VALID_CASES:
        base.caption_case = v
    v = str(data.get("color_mood") or "").strip().lower()
    if v in VALID_MOODS:
        base.color_mood = v
    v = data.get("pacing_acceleration")
    if isinstance(v, bool):
        base.pacing_acceleration = v
    v = _as_float(data.get("sfx_density"))
    if v is not None and v >= 0:
        base.sfx_density = round(v, 3)
    v = _as_float(data.get("broll_ratio"))
    if v is not None:
        base.broll_ratio = round(_clamp01(v), 3)
    v = str(data.get("transition_preference") or "").strip().lower()
    if v in VALID_TRANSITIONS:
        base.transition_preference = v
    return base


async def extract_style_dna(transcript_words, clip_metadata: list,
                            llm_fn) -> StyleDNA:
    """
    Analyze editing patterns via llm_fn (sync or async, JSON string or
    dict). Any LLM/parsing failure — or invalid field values — falls back
    per-field to heuristic_style_dna(transcript_words, clip_metadata).
    """
    fallback = heuristic_style_dna(transcript_words, clip_metadata)
    prompt = _build_prompt(transcript_words, clip_metadata)
    try:
        raw = await _maybe_await(llm_fn(prompt))
        data = _extract_json(raw)
    except Exception:
        return fallback
    return _merge_llm_into(fallback, data)


# ─────────────────────────────────────────────────────────────────────────────
#  Director Agent bridge + persistence
# ─────────────────────────────────────────────────────────────────────────────

def style_dna_to_prompt(dna: StyleDNA) -> str:
    """Render a StyleDNA as a prompt fragment for the Director Agent."""
    accel = ("accelerates — cuts get shorter toward the end"
             if dna.pacing_acceleration else "steady throughout")
    emoji = ("no emojis in captions"
             if dna.caption_emoji_density <= 0.001 else
             f"sparse emojis in captions (density {dna.caption_emoji_density})"
             if dna.caption_emoji_density < 0.05 else
             f"frequent emojis in captions (density {dna.caption_emoji_density})")
    broll_pct = int(round(dna.broll_ratio * 100))
    return (
        "EDITING STYLE DNA — clone this creator's fingerprint:\n"
        f"- Pacing: {dna.cut_rhythm} cuts/min, average clip length "
        f"{dna.avg_clip_duration}s; tempo {accel}.\n"
        f"- Hook: open with a {dna.hook_style}.\n"
        f"- Captions: {dna.caption_case.upper()} case, {emoji}.\n"
        f"- Look: {dna.color_mood} color mood.\n"
        f"- Sound: {dna.sfx_density} SFX hits per minute.\n"
        f"- B-roll: use b-roll on ~{broll_pct}% of clips.\n"
        f"- Transitions: prefer hard '{dna.transition_preference}' cuts."
    )


def _library_path(name: str) -> str:
    raw = str(name).strip()
    if not raw or raw.startswith(".") or any(sep in raw for sep in ("/", "\\")):
        raise ValueError("style DNA name must be a bare filename fragment")
    safe = "".join(ch for ch in raw if ch.isalnum() or ch in "-_ ")
    safe = safe.strip().replace(" ", "_")
    if not safe:
        raise ValueError("style DNA name must contain word characters")
    return os.path.join(LIBRARY_DIR, safe + ".json")


def save_dna(dna: StyleDNA, name: str) -> None:
    """Persist a fingerprint to LIBRARY_DIR/{name}.json."""
    os.makedirs(LIBRARY_DIR, exist_ok=True)
    with open(_library_path(name), "w", encoding="utf-8") as fh:
        json.dump(asdict(dna), fh, ensure_ascii=False, indent=2)


def load_dna(name: str) -> StyleDNA:
    """Load a previously saved fingerprint; raises FileNotFoundError if absent."""
    with open(_library_path(name), encoding="utf-8") as fh:
        data = json.load(fh)
    known = set(StyleDNA.__dataclass_fields__)
    return StyleDNA(**{k: v for k, v in data.items() if k in known})
