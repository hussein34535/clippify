"""
orchestrator.py — Clippify Pipeline Orchestrator
Drives the full AI editing pipeline:
  1. Transcribe audio
  2. Find the hook sentence (content-type-aware)
  3. Select best clips (AI)
  4. Plan effects per content type
  5. Apply custom instructions
  6. Render each clip
  7. Compile final video
"""

import os
import json
import requests
import threading
from dotenv import load_dotenv

load_dotenv()

from models import EditingPlan, ClipSpec, VideoAnalysis
from ai_engine import (
    generate_subtitles,
    find_semantic_clips,
    generate_ass_for_clip,
    get_emphasis_timestamps,
    get_words_in_range,
    EMOJI_DICT,
)
from editor import export
from content_types import get_type_profile, get_hook_prompt, get_emphasis_sfx
from broll_manager import DEFAULT_PEXELS_KEY

_API_KEY = os.getenv("GEMMA_API_KEY", "")
_LLM_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemma-2-27b-it:generateContent?key="

progress_callback = None


# ─────────────────────────────────────────────────────────────────────────────
#  LLM Helper
# ─────────────────────────────────────────────────────────────────────────────

def _llm_ask(prompt: str, temperature: float = 0.5, max_retries: int = 2) -> str:
    import time
    url = _LLM_URL + _API_KEY
    headers = {"Content-Type": "application/json"}
    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "temperature": temperature,
            "maxOutputTokens": 2000,
        },
    }
    last_err = ""
    for attempt in range(1, max_retries + 1):
        try:
            resp = requests.post(url, json=payload, headers=headers, timeout=120)
            if resp.status_code == 200:
                data = resp.json()
                candidates = data.get("candidates", [])
                if not candidates:
                    raise Exception("No LLM response candidates.")
                parts = candidates[0].get("content", {}).get("parts", [])
                text_parts = [p.get("text", "") for p in parts if not p.get("thought")]
                return "".join(text_parts).strip()
            if resp.status_code >= 500:
                last_err = f"LLM API Error ({resp.status_code}): {resp.text[:200]}"
                if attempt < max_retries:
                    wait = 2 ** attempt
                    print(f"  [LLM] Server error, retrying in {wait}s...")
                    time.sleep(wait)
                    continue
            raise Exception(f"LLM API Error ({resp.status_code}): {resp.text[:300]}")
        except requests.Timeout:
            last_err = "LLM request timeout"
            if attempt < max_retries:
                wait = 2 ** attempt
                print(f"  [LLM] Timeout, retrying in {wait}s...")
                time.sleep(wait)
                continue
            raise Exception(last_err)
    raise Exception(last_err)


# ─────────────────────────────────────────────────────────────────────────────
#  Hook Sentence Finder (content-type aware)
# ─────────────────────────────────────────────────────────────────────────────

def _find_hook_sentence(words: list, content_type: str) -> dict:
    """
    Use AI to find the best hook sentence for the given content type.
    Returns: {"text": str, "start_sec": float, "end_sec": float}
    Duration is fully automatic — matches the natural length of the hook sentence.
    Min: 1.5s, Max: 12s (safety cap for very long sentences).
    """
    if not words:
        return {"text": "", "start_sec": 0.0, "end_sec": 3.0}

    # Identify first sentence boundary to skip it so hook is never the first sentence
    first_sentence_end_time = 0.0
    for i, w in enumerate(words):
        text_w = w["text"].strip()
        is_punc = text_w and text_w[-1] in '.!?'
        is_pause = False
        if i < len(words) - 1:
            is_pause = (words[i+1]["start"] - w["end"]) > 0.4
        
        # Enforce that the first sentence has some minimal duration to avoid skipping single tiny words
        if (is_punc or is_pause) and w["end"] >= 1.5:
            first_sentence_end_time = w["end"]
            break
        if w["end"] >= 4.0:  # Cap the first sentence skip at 4.0 seconds max
            first_sentence_end_time = w["end"]
            break
            
    # Default minimum skip of 3.0 seconds if no clear sentence end was found early
    if first_sentence_end_time < 3.0:
        first_sentence_end_time = 3.0
        
    eligible_words = [w for w in words if w["start"] >= first_sentence_end_time]
    if not eligible_words or len(eligible_words) < 3:
        # Fallback if the clip is too short or all words are in the first sentence
        eligible_words = [w for w in words if w["start"] >= 1.5]
    if not eligible_words:
        eligible_words = words  # Absolute fallback

    max_time = words[-1]["end"]
    HOOK_MAX_SEC = 5.5   # Stricter cap to prevent long hooks
    HOOK_MIN_SEC = 2.0   # Minimum hook duration

    # ── Phase 2: Pre-score hook candidates locally ────────────────────
    # Extract all sentences from eligible words
    sentences = []
    current_sentence_words = []
    for i, w in enumerate(eligible_words):
        current_sentence_words.append(w)
        text_w = w["text"].strip()
        is_sentence_end = text_w and text_w[-1] in '.!?'
        is_pause = False
        if i < len(eligible_words) - 1:
            is_pause = (eligible_words[i+1]["start"] - w["end"]) > 0.4
        
        if (is_sentence_end or is_pause) and len(current_sentence_words) >= 2:
            sent_text = " ".join(sw["text"] for sw in current_sentence_words)
            sent_start = current_sentence_words[0]["start"]
            sent_end = current_sentence_words[-1]["end"]
            sent_dur = sent_end - sent_start
            
            # Only consider sentences between 2-6 seconds
            if HOOK_MIN_SEC <= sent_dur <= HOOK_MAX_SEC + 0.5:
                sentences.append({
                    "text": sent_text,
                    "start": sent_start,
                    "end": sent_end,
                    "duration": sent_dur,
                    "words": list(current_sentence_words),
                })
            current_sentence_words = []

    # Score each sentence as a hook candidate
    _CURIOSITY_WORDS_AR = {"سر", "لكن", "بس", "المشكلة", "الحقيقة", "تخيل", "مستحيل", "لو", "ليش", "كيف"}
    _CURIOSITY_WORDS_EN = {"secret", "but", "however", "problem", "truth", "imagine", "impossible", "if", "why", "how", "actually"}
    _STRONG_OPINION_AR = {"غلط", "خطأ", "أبدا", "لازم", "ممنوع", "والله", "صراحة", "بصراحة"}
    _STRONG_OPINION_EN = {"wrong", "never", "must", "always", "honestly", "absolutely", "exactly"}

    scored_candidates = []
    for sent in sentences:
        score = 0.0
        score_breakdown = []  # شرح تفصيلي لكل نقطة
        words_lower = [w["text"].strip(".,!?;:()\'\"'").lower() for w in sent["words"]]

        # Curiosity Gap Score: creates unanswered tension
        curiosity_hits = [w for w in words_lower if w in _CURIOSITY_WORDS_AR or w in _CURIOSITY_WORDS_EN]
        for w in curiosity_hits:
            score += 3.0
        if curiosity_hits:
            score_breakdown.append(f"فجوة فضول (+{3.0*len(curiosity_hits):.0f}): {curiosity_hits}")

        # Controversy/Strong Opinion Score
        opinion_hits = [w for w in words_lower if w in _STRONG_OPINION_AR or w in _STRONG_OPINION_EN]
        for w in opinion_hits:
            score += 2.5
        if opinion_hits:
            score_breakdown.append(f"رأي قوي (+{2.5*len(opinion_hits):.0f}): {opinion_hits}")

        # Question Score: questions are inherently hooky
        if sent["text"].strip().endswith("?"):
            score += 4.0
            score_breakdown.append("جملة استفهامية (+4.0)")

        # Exclamation Score: emotional intensity
        if sent["text"].strip().endswith("!"):
            score += 2.0
            score_breakdown.append("تعجب عاطفي (+2.0)")

        # Brevity Bonus: shorter = punchier (sweet spot ~3s)
        if 2.5 <= sent["duration"] <= 4.0:
            score += 2.0
            score_breakdown.append(f"طول مثالي ({sent['duration']:.1f}ث) (+2.0)")
        elif sent["duration"] <= 2.5:
            score += 1.0
            score_breakdown.append(f"قصيرة جداً ({sent['duration']:.1f}ث) (+1.0)")
        else:
            score_breakdown.append(f"طويلة ({sent['duration']:.1f}ث) لا مكافأة")

        # Standalone Clarity Penalty: check for dangling references
        first_word = words_lower[0] if words_lower else ""
        if first_word in {"he", "she", "it", "they", "this", "that", "هو", "هي", "هذا", "دا", "ده", "دي"}:
            score -= 3.0
            score_breakdown.append(f"ضمير مبهم في البداية '{first_word}' (-3.0)")

        scored_candidates.append({**sent, "hook_score": round(score, 1), "_score_breakdown": score_breakdown})

    scored_candidates.sort(key=lambda x: x["hook_score"], reverse=True)
    top_candidates = scored_candidates[:5]  # Send only top 5 to AI

    # طباعة شرح الترشيح للهوك
    print(f"  [تحليل الهوك] تم تقييم {len(sentences)} جملة مترشحة:")
    for i, c in enumerate(top_candidates):
        reasons = " | ".join(c.get("_score_breakdown", ["لا توجد معطيات"]))
        print(f"    [{i+1}] سكور={c['hook_score']:+.1f} | '{c['text'][:50]}' | سبب: {reasons}")

    # ── Build prompt with pre-scored candidates ───────────────────────
    hook_prompt_hint = get_hook_prompt(content_type)

    if top_candidates:
        candidates_text = "\n".join(
            f"  [{i+1}] (score={c['hook_score']}) [{c['start']:.1f}s-{c['end']:.1f}s] \"{c['text']}\""
            for i, c in enumerate(top_candidates)
        )
        prompt = f"""{hook_prompt_hint}

Here are the top 5 hook candidates pre-scored by our AI engagement system:
{candidates_text}

RULES:
1. Pick the BEST hook from the candidates above. You MAY pick any of them based on your editorial judgment.
2. If NONE of the candidates make a good hook (e.g. they are boring, out of context, or inappropriate), you MUST return "NO_HOOK" for the sentence.
3. The hook MUST make sense on its own (a viewer seeing ONLY this sentence should feel curious).
4. Prefer sentences with curiosity gaps, surprising claims, or strong opinions.
5. Return ONLY a JSON object: {{"sentence": "<the hook text or NO_HOOK>", "start_sec": <float or 0>, "end_sec": <float or 0>}}
No markdown, no backticks, no explanation — ONLY the JSON object."""
    else:
        # Fallback: no good candidates, send raw transcript
        sample_size = min(len(eligible_words), 1500)
        step = max(1, len(eligible_words) // sample_size)
        sampled_words = eligible_words[::step][:sample_size]
        transcript_lines = [f"[{w['start']:.1f}s] {w['text']}" for w in sampled_words]
        ts_sample = "\n".join(transcript_lines[:300])
        
        prompt = f"""{hook_prompt_hint}

Transcript (with timestamps):
{ts_sample}

RULES:
1. Pick the BEST SHORT hook sentence (MUST NOT be the first sentence). Pick a high-impact, punchy sentence.
2. The sentence MUST be naturally brief (3-5 seconds). Do NOT pick long sentences.
3. The sentence MUST make sense on its own without context.
4. Return ONLY: {{"sentence": "<text>", "start_sec": <float>, "end_sec": <float>}}
No markdown, no backticks, no explanation."""

    try:
        result = _llm_ask(prompt, temperature=0.7)
        # Clean any markdown wrapping
        if "```" in result:
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        result = result.strip()
        parsed = json.loads(result)
        text = parsed.get("sentence", "")
        if text == "NO_HOOK":
            print("  [هوك] الذكاء الاصطناعي اختار تجاوز الهوك (لا يوجد مرشح قوي).")
            return {"text": "", "start_sec": 0.0, "end_sec": 0.0}

        start_sec = float(parsed.get("start_sec", eligible_words[0]["start"]))
        ai_end_sec = float(parsed.get("end_sec", 0.0))

        # Validate start timestamp is in range
        start_sec = max(eligible_words[0]["start"], min(start_sec, max_time - 1.0))

        # --- Smart end_sec: use word-level alignment for precision ---
        import re
        def normalize_text(t: str) -> str:
            if not t:
                return ""
            t = t.lower()
            # Normalize Arabic letters to prevent mismatch due to spelling variations
            t = re.sub(r"[أإآا]", "ا", t)
            t = re.sub(r"[يى]", "ي", t)
            t = re.sub(r"[ةه]", "ه", t)
            # Strip punctuation
            t = re.sub(r"[.,!?;:()\"'«»\-]", "", t)
            return t.strip()

        hook_words_lower = text.lower().split()
        if hook_words_lower and len(hook_words_lower) >= 2:
            # Find words in transcript near the AI's start_sec
            search_start = max(0.0, start_sec - 1.0)
            search_end = min(max_time, start_sec + HOOK_MAX_SEC + 2.0)
            candidate_words = [w for w in eligible_words
                               if search_start <= w["start"] <= search_end]
            
            # Match the last word of the hook sentence with Arabic normalization
            last_hook_word_norm = normalize_text(hook_words_lower[-1])
            aligned_end = None
            for w in reversed(candidate_words):
                wt_norm = normalize_text(w["text"])
                if (wt_norm == last_hook_word_norm or 
                    (len(last_hook_word_norm) > 2 and last_hook_word_norm in wt_norm) or 
                    (len(wt_norm) > 2 and wt_norm in last_hook_word_norm)):
                    # Add a tail of 0.3 seconds so the last word is fully completed naturally
                    aligned_end = w["end"] + 0.3
                    break

            if aligned_end:
                end_sec = aligned_end
            elif ai_end_sec > start_sec:
                end_sec = ai_end_sec
            else:
                # Count words in hook sentence and estimate duration
                word_count = len(hook_words_lower)
                estimated_dur = max(HOOK_MIN_SEC, word_count * 0.35)  # ~0.35s per word
                end_sec = start_sec + estimated_dur
        else:
            end_sec = ai_end_sec if ai_end_sec > start_sec else start_sec + HOOK_MIN_SEC

        # Apply min/max caps
        duration = end_sec - start_sec
        if duration < HOOK_MIN_SEC:
            end_sec = start_sec + HOOK_MIN_SEC
        if duration > HOOK_MAX_SEC:
            end_sec = start_sec + HOOK_MAX_SEC
        end_sec = min(end_sec, max_time)

        # فلتر نهائي: لو الهوك يحتوي على محتوى غير لائق، ابحث عن بديل
        _BAD_WORDS_HOOK = {"shit", "fuck", "damn", "ass", "crap", "bitch", "wtf", "bastard"}
        ai_words_lower = text.lower().split()
        if any(bw in ai_words_lower for bw in _BAD_WORDS_HOOK):
            print(f"  [هوك] الذكاء اختار جملة تحتوي محتوى غير لائق. جاري البحث عن بديل نظيف...")
            for cand in scored_candidates:
                cand_words = cand['text'].lower().split()
                if not any(bw in cand_words for bw in _BAD_WORDS_HOOK):
                    text = cand['text']
                    start_sec = cand['start']
                    end_sec = min(cand['end'] + 0.3, max_time)
                    dur_c = end_sec - start_sec
                    if dur_c < HOOK_MIN_SEC:
                        end_sec = start_sec + HOOK_MIN_SEC
                    if dur_c > HOOK_MAX_SEC:
                        end_sec = start_sec + HOOK_MAX_SEC
                    print(f"  [هوك] تم الاستبدال ببديل نظيف: '{text[:50]}'")
                    break

        print(f"  [هوك] تم اختياره: \"{text[:60]}\" @ {start_sec:.1f}ث-{end_sec:.1f}ث ({end_sec-start_sec:.1f}ث) | سبب: الذكاء الاصطناعي اختاره من بين المرشحين الأعلى تقييماً")
        return {"text": text, "start_sec": start_sec, "end_sec": end_sec}

    except Exception as e:
        print(f"  [هوك] فشل الذكاء الاصطناعي ({e})، جاري الكشف التلقائي عن أول جملة مناسبة...")
        # Smart fallback: find the end of the first natural sentence in eligible_words
        # Look for sentence-ending punctuation or a natural pause
        sentence_end_words = []
        found_sentence_end = False
        for w in eligible_words:
            if w["start"] > (eligible_words[0]["start"] + HOOK_MAX_SEC):
                break  # Don't go beyond max
            sentence_end_words.append(w)
            text_w = w["text"].strip()
            # Detect sentence end: punctuation or a pause of > 0.3s
            if text_w and text_w[-1] in '.!?,;:':
                next_words = [x for x in eligible_words if x["start"] > w["end"]]
                if next_words:
                    pause = next_words[0]["start"] - w["end"]
                    if pause > 0.3 or text_w[-1] in '.!?':
                        found_sentence_end = True
                        break
                else:
                    found_sentence_end = True
                    break

        if sentence_end_words and found_sentence_end:
            fb_text = " ".join(w["text"] for w in sentence_end_words)
            fb_start = sentence_end_words[0]["start"]
            fb_end = sentence_end_words[-1]["end"] + 0.15
            fb_end = max(fb_end, fb_start + HOOK_MIN_SEC)
        else:
            # Last resort: first 4 seconds of eligible_words
            fb_start = eligible_words[0]["start"]
            fb_words = [w for w in eligible_words if w["start"] < (fb_start + 4.0)]
            fb_text = " ".join(w["text"] for w in fb_words) if fb_words else ""
            fb_end = min(fb_start + 4.0, max_time)

        # فلتر المحتوى غير اللائق من الـ fallback
        _BAD_WORDS = {"shit", "fuck", "damn", "ass", "crap", "bitch", "hell", "wtf", "bastard"}
        fb_words_list = fb_text.lower().split()
        if any(bw in fb_words_list for bw in _BAD_WORDS):
            # ابحث عن جملة بديلة نظيفة
            for sent in scored_candidates:
                candidate_words_lower = [w["text"].lower().strip(".,!?;:()\'\"")
                                         for w in sent.get("words", [])]
                if not any(bw in candidate_words_lower for bw in _BAD_WORDS):
                    fb_text = sent["text"]
                    fb_start = sent["start"]
                    fb_end = sent["end"] + 0.15
                    fb_end = max(fb_end, fb_start + HOOK_MIN_SEC)
                    break

        safe_text = fb_text[:50].encode('ascii', 'replace').decode('ascii')
        print(f"  [HOOK] فولباك: '{safe_text}' @ {fb_start:.1f}ث-{fb_end:.1f}ث")

        return {"text": fb_text, "start_sec": fb_start, "end_sec": fb_end}



# ─────────────────────────────────────────────────────────────────────────────
#  Custom Instructions Parser
# ─────────────────────────────────────────────────────────────────────────────

def _parse_custom_instructions(instructions: str, total_duration: float) -> dict:
    """
    Parse the user's custom instructions (Arabic or English) using AI.
    Returns a structured dict of actions to apply.
    """
    if not instructions or not instructions.strip():
        return {}

    prompt = f"""You are a video editor assistant. Parse the following user instructions for a video that is {total_duration:.0f} seconds long.

User instructions: "{instructions}"

Return ONLY a JSON object with these possible fields (include only the ones mentioned):
{{
  "overlay_text": "<text to show on screen>",
  "overlay_position": "top" | "center" | "bottom",
  "overlay_time_start": <float seconds>,
  "overlay_time_end": <float seconds>,
  "slow_motion_start": <float seconds>,
  "slow_motion_end": <float seconds>,
  "slow_motion_speed": <float, e.g. 0.5 for half speed>,
  "split_screen": true | false,
  "face_circle": true | false,
  "extra_cta": "<call to action text>"
}}

If the user said something like "حط في المنتصف" that means overlay_position = "center".
If the user said "اشتركوا" or "follow" that means extra_cta = "اشتركوا في القناة".
No markdown, no backticks, no explanation — ONLY the JSON object."""

    try:
        result = _llm_ask(prompt, temperature=0.3)
        if "```" in result:
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        parsed = json.loads(result.strip())
        print(f"  [INSTRUCTIONS] Parsed: {parsed}")
        return parsed
    except Exception as e:
        print(f"  [INSTRUCTIONS] Failed to parse ({e}), ignoring custom instructions")
        return {}


# ─────────────────────────────────────────────────────────────────────────────
#  Clip Selection (with content type context)
# ─────────────────────────────────────────────────────────────────────────────

def _select_clips_with_ai(words: list, n_clips: int, duration_sec: float,
                          content_type: str = "podcast",
                          viral_context: str = "",
                          custom_instructions: str = "") -> list:
    semantic = find_semantic_clips(words, max(n_clips * 3, n_clips + 5), duration_sec)

    if not semantic:
        return []

    # ── Build structured context for each candidate clip ───────────────
    def _annotate_clip(clip_words):
        """Create rich annotations for a clip's content."""
        annotations = []
        for i, w in enumerate(clip_words):
            clean = w['text'].strip(".,!?;:()\"'").lower()
            prefix = ""
            # Detect questions
            if w['text'].strip().endswith('?') or clean in {"هل", "ليش", "ليه", "كيف", "why", "how", "what"}:
                prefix = "❓"
            # Detect emotional intensity (exclamations or trigger words)
            elif w['text'].strip().endswith('!'):
                prefix = "🔥"
            # Detect dramatic pauses
            if i > 0 and (w['start'] - clip_words[i-1]['end']) > 0.5:
                prefix = "⏸️" + prefix
            if prefix:
                annotations.append(f"[{prefix} {w['start']:.1f}s]")
        return " ".join(annotations) if annotations else "(neutral tone)"

    clips_summary_parts = []
    for i, c in enumerate(semantic):
        clip_words = [w for w in words if c['start_sec'] <= w['start'] <= c['end_sec']]
        text_preview = " ".join(w['text'] for w in clip_words[:30])
        annotations = _annotate_clip(clip_words)
        clips_summary_parts.append(
            f"  Clip {i+1}: {c['start_sec']:.1f}s-{c['end_sec']:.1f}s "
            f"(engagement={c['score']:.1f})\n"
            f"    Text: \"{text_preview[:150]}...\"\n"
            f"    Signals: {annotations}"
        )
    clips_summary = "\n".join(clips_summary_parts)

    type_context = {
        "podcast":     "engaging conversation moments, debates, laughs, surprising facts",
        "awareness":   "emotional, spiritual, or deeply impactful moments",
        "comedy":      "funniest moments, punchlines, awkward pauses, peak comedic timing",
        "interview":   "strong answers, personal stories, controversial opinions",
        "motivation":  "peak energy moments, calls to action, emotional crescendos",
        "educational": "key facts, surprising insights, important definitions",
    }.get(content_type, "engaging, high-energy moments")

    total_duration = words[-1]['end'] if words else 0
    
    scenario_instruction = ""
    if custom_instructions:
        scenario_instruction = f"\nCRITICAL INSTRUCTION (SCENARIO): The user requested: '{custom_instructions}'. You MUST prioritize finding clips that match this topic/scenario over generic viral moments.\n"

    prompt = f"""You are a professional video editor specializing in {content_type} content for TikTok/Reels.
Given a video transcript with {len(words)} words over {total_duration:.0f}s, select EXACTLY {n_clips} clips
(each exactly ~{duration_sec:.0f}s long) for a high-impact short-form video montage.

For {content_type} content, prioritize: {type_context}{scenario_instruction}
INTELLIGENCE RULES (think like a senior editor):
1. You MUST return EXACTLY {n_clips} clips — no more, no less.
2. Each clip must be ~{duration_sec:.0f}s. Set end_sec = start_sec + {duration_sec:.0f}.
3. NEVER pick overlapping clips. Spread them throughout the entire video.
4. PREFER clips with high engagement scores (shown below).
5. PREFER clips marked with ❓ (questions), 🔥 (emotional intensity), or ⏸️ (dramatic pauses).
6. AVOID clips that are just normal conversation with no emotional peaks.
7. AVOID picking two clips about the same topic — maximize variety.
8. Each clip should tell a mini-story. For Clip 1, you can optionally plan a "3-Act Narrative Stitched Story" to compose a highly compelling 45-second story from non-contiguous parts of the transcript. To do this, specify a list of exactly 3 non-contiguous segments in the "narrative_acts" field (Act 1: Setup ~10s, Act 2: Conflict ~20s, Act 3: Resolution ~15s). The start_sec and end_sec of the main clip should span the entire range, and "narrative_acts" will be stitched automatically.

Candidate clips (ranked by AI engagement score):
{clips_summary}{viral_context}

Return ONLY a JSON array of EXACTLY {n_clips} objects:
[{{\"index\": <1..{n_clips}>, \"start_sec\": <float>, \"end_sec\": <float>, \"hook_options\": [\"Title Option 1 (Short, punchy)\", \"Title Option 2 (Curiosity gap)\", \"Title Option 3 (High impact)\"], \"reason\": \"<why this clip>\", \"narrative_acts\": [{{\"name\": \"Setup\", \"start_sec\": <float>, \"end_sec\": <float>}}, {{\"name\": \"Conflict\", \"start_sec\": <float>, \"end_sec\": <float>}}, {{\"name\": \"Resolution\", \"start_sec\": <float>, \"end_sec\": <float>}}]}}]
No markdown, no backticks, no explanation."""

    try:
        result = _llm_ask(prompt, temperature=0.6)
        if "```" in result:
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        chosen = json.loads(result.strip())
        if isinstance(chosen, list) and len(chosen) > 0:
            # ✅ FIX: strictly return exactly n_clips, trim or repeat if needed
            chosen = chosen[:n_clips]
            # Fix indices to be sequential and enforce duration
            for i, c in enumerate(chosen):
                c["index"] = i + 1
                # Enforce clip duration matches user setting
                if c.get("end_sec", 0) - c.get("start_sec", 0) < 1.0:
                    c["end_sec"] = c["start_sec"] + duration_sec

            # ── Clip Boundary Auto-Correction ─────────────────────────
            # Snap start/end to nearest sentence boundaries
            for c in chosen:
                clip_words = [w for w in words if c["start_sec"] - 1.0 <= w["start"] <= c["end_sec"] + 1.0]
                if clip_words:
                    # Snap start to the beginning of the nearest sentence
                    for w in clip_words:
                        if w['start'] >= c['start_sec'] - 0.5:
                            w_idx = next((idx for idx, ww in enumerate(words) if ww is w), -1)
                            if w_idx > 0:
                                gap = w['start'] - words[w_idx - 1]['end']
                                if gap > 0.3:
                                    c['start_sec'] = max(0.0, w['start'] - 0.15)
                                    break
                            elif w_idx == 0:
                                c['start_sec'] = max(0.0, w['start'] - 0.15)
                                break

                    # Snap end to end of nearest complete sentence
                    target_end = c['start_sec'] + duration_sec
                    best_end = target_end
                    for w in reversed(clip_words):
                        if w['end'] <= target_end + 1.0:
                            text = w['text'].strip()
                            if text and text[-1] in '.!?,;:':
                                best_end = w['end'] + 0.15
                                break
                            w_idx = next((idx for idx, ww in enumerate(words) if ww is w), -1)
                            if 0 <= w_idx < len(words) - 1:
                                gap = words[w_idx + 1]['start'] - w['end']
                                if gap > 0.4:
                                    best_end = w['end'] + 0.15
                                    break
                    c['end_sec'] = best_end

            return chosen
    except Exception as e:
        print(f"  [AI SELECT] LLM fallback ({e}), using semantic top {n_clips}")

    # ✅ فولباك محسّن: اختيار أفضل كليبات باستخدام النتائج الدلالية + تصفية الصمت
    _BAD_WORDS_FALLBACK = {"shit", "fuck", "damn", "ass", "crap", "bitch", "wtf", "bastard"}

    def _speech_ratio(clip_dict):
        """Calculate speech ratio of a semantic clip (higher = more talking)."""
        cw = [w for w in words if clip_dict['start_sec'] <= w['start'] <= clip_dict['start_sec'] + duration_sec]
        if not cw:
            return 0.0
        speech_dur = sum(w['end'] - w['start'] for w in cw)
        return speech_dur / max(duration_sec, 1.0)

    # ترتيب الكليبات: أولاً بدجة نسبة كلام >50%، ثم بالدرجة
    scored_fallback = []
    for c in semantic:
        sr = _speech_ratio(c)
        combined_score = c.get('score', 0.0) * 0.4 + sr * 0.6
        clip_words = [w for w in words if c['start_sec'] <= w['start'] <= c['start_sec'] + duration_sec]
        clip_text = " ".join(w['text'] for w in clip_words).lower()
        has_bad = any(bw in clip_text.split() for bw in _BAD_WORDS_FALLBACK)
        scored_fallback.append({**c, '_speech_ratio': sr, '_combined': combined_score, '_has_bad': has_bad})

    # تفضيل كليبات نظيفة بنسبة كلام >40%
    clean_clips = [c for c in scored_fallback if c['_speech_ratio'] >= 0.4 and not c['_has_bad']]
    if len(clean_clips) < n_clips:
        # لو مافيشش بدائل كافية، اقبل كليبات بنسبة >0% بدون كلمات سيئة
        clean_clips = [c for c in scored_fallback if not c['_has_bad']]
    if not clean_clips:
        clean_clips = scored_fallback  # آخر ملجأ

    clean_clips.sort(key=lambda x: x['_combined'], reverse=True)
    fallback = clean_clips[:n_clips]

    result_clips = []
    for i, c in enumerate(fallback):
        clip_words = [w for w in words if c['start_sec'] <= w['start'] <= c['start_sec'] + duration_sec]
        clip_text = " ".join(w['text'] for w in clip_words[:8])
        base = clip_text[:30].strip() or "لحظة مميزة"
        # توليد hook options تلقائياً
        is_arabic = any(ord(ch) > 1200 for ch in clip_text)
        if is_arabic:
            hooks = [
                f"🤔 اسمع كويس لما قاله هنا!",
                f"⚠️ لازم تشوف اللحظة دي!",
                f"🔥 مومنت قوي والله!"
            ]
        else:
            hooks = [
                f"🤔 You need to hear this!",
                f"⚠️ This moment is WILD!",
                f"🔥 They said WHAT?!"
            ]
        print(f"  [AI SELECT فولباك] كليب {i+1}: {c['start_sec']:.1f}ث→{c['start_sec']+duration_sec:.1f}ث | كلام={c['_speech_ratio']*100:.0f}% | درجة={c['_combined']:.2f}")
        result_clips.append({
            "index": i + 1,
            "start_sec": c['start_sec'],
            "end_sec": c['start_sec'] + duration_sec,
            "hook_options": hooks,
            "reason": f"فولباك دلالي: نسبة كلام {c['_speech_ratio']*100:.0f}%، درجة {c['_combined']:.2f}"
        })
    return result_clips


# ─────────────────────────────────────────────────────────────────────────────
#  Effects Planner (content type aware)
# ─────────────────────────────────────────────────────────────────────────────

def _plan_effects_with_ai(clip_texts: list, content_type: str = "podcast",
                          auto_broll: bool = False, clip_words_list: list = None,
                          viral_timeline: dict = None, clips: list = None) -> list:
    """Plan effects using emotion-mapped intelligence.
    
    clip_words_list: list of word-lists per clip (for emotion analysis).
    """
    from content_types import get_type_profile, get_emphasis_sfx
    profile = get_type_profile(content_type)

    type_vibe = {
        "podcast":     "calm and conversational, professional",
        "awareness":   "deep, emotional, cinematic and dramatic",
        "comedy":      "funny, energetic, absurd and chaotic",
        "interview":   "clean, professional, news-style",
        "motivation":  "epic, high-energy, powerful and inspiring",
        "educational": "clear, clean, informative",
    }.get(content_type, "energetic")

    # ── Build emotion timeline per clip ────────────────────────────────
    def _build_emotion_arc(clip_words):
        """Analyze a clip's words and return an emotion arc description."""
        if not clip_words or len(clip_words) < 5:
            return "(insufficient data for analysis)"
        
        total_dur = clip_words[-1]['end'] - clip_words[0]['start']
        if total_dur <= 0:
            return "(no duration)"
        
        phase_dur = total_dur / 4
        base_time = clip_words[0]['start']
        phases = []
        phase_labels = ["INTRO", "BUILD", "PEAK", "RESOLVE"]
        
        for phase_idx in range(4):
            t_start = base_time + phase_idx * phase_dur
            t_end = t_start + phase_dur
            phase_words = [w for w in clip_words if t_start <= w['start'] < t_end]
            
            if not phase_words:
                phases.append(f"  {phase_labels[phase_idx]}: (silence)")
                continue
            
            # Speech rate (words per second)
            p_dur = max(0.1, phase_words[-1]['end'] - phase_words[0]['start'])
            speech_rate = len(phase_words) / p_dur
            
            # Question detection
            has_question = any(w['text'].strip().endswith('?') for w in phase_words)
            
            # Exclamation detection  
            has_exclamation = any(w['text'].strip().endswith('!') for w in phase_words)
            
            # Determine energy level
            if speech_rate > 3.5 or has_exclamation:
                energy = "🔥 HIGH"
            elif speech_rate > 2.0:
                energy = "📈 RISING" if phase_idx < 2 else "📉 FALLING"
            elif has_question:
                energy = "❓ CURIOUS"
            else:
                energy = "😌 CALM"
            
            preview = " ".join(w['text'] for w in phase_words[:8])
            phases.append(f"  {phase_labels[phase_idx]} ({energy}): \"{preview}...\"")
        
        return "\n".join(phases)

    # Build rich context for each clip
    clips_with_context = []
    for i, text in enumerate(clip_texts):
        emotion_arc = "(no word data)"
        if clip_words_list and i < len(clip_words_list):
            emotion_arc = _build_emotion_arc(clip_words_list[i])
        clips_with_context.append(
            f"  Clip {i+1}:\n"
            f"    Text: \"{text[:200]}\"\n"
            f"    Emotion Arc:\n{emotion_arc}"
        )
    clips_context = "\n".join(clips_with_context)

    sfx_options = ", ".join(f'"{s}"' for s in get_emphasis_sfx(content_type)[:5])

    broll_instructions = ""
    broll_json_field = ""
    if auto_broll:
        broll_instructions = (
            "- brolls: An OPTIONAL list of B-roll overlays (MAX 2 per clip). Rules:\n"
            "  * NEVER add B-roll during the first 5 seconds (hook zone).\n"
            "  * NEVER add B-roll during HIGH energy moments (speaker emotion is engaging enough).\n"
            "  * DO add B-roll during CALM moments if the speaker mentions a specific visual concept.\n"
            "  * DO add B-roll as a 2-3s bridge between topics.\n"
            "  * Return an EMPTY list [] if the speaker is visually engaging throughout.\n"
            "  Each: {\"keyword\": \"<english Pexels search>\", \"start_offset\": <float>, \"duration\": <2.0-4.0>}\n"
        )
        broll_json_field = ', "brolls": []'

    prompt = f"""You are a senior {content_type} video editor for TikTok/Reels.
For each clip below, plan effects that ENHANCE the emotion, not fight it.

SMART ZOOM RULES (think cinematically):
- "none" = default for calm/conversational moments. USE THIS MOST of the time.
- "punch" = ONLY on the single most impactful word/moment in the clip. Max 1 per clip.
- "slow_push" = ONLY when building tension toward a reveal.
- "gentle" = safe default for slightly dynamic moments.
- "dynamic" = ONLY for comedy or motivation HIGH energy peaks.
- NEVER zoom in the first 2 seconds (let viewer orient).
- NEVER use more than 1 zoom per 60s clip.

SFX BUDGET (less is more):
- Max 2 SFX per clip. Pick the 1-2 MOST impactful moments.
- NEVER add SFX during emotional/serious moments (awareness, motivational peaks).
- Choose from: [{sfx_options}]

DYNAMIC RETIMING & PACING RULES:
- Identify if there is a single most dramatic peak emotional punchline or shocking revelation in the clip's text.
- If so, plan a 0.5x slow-motion effect for EXACTLY 1.5 seconds right on that punchline.
- Specify: "slow_motion_start": <float seconds relative to clip start, e.g. 12.5>, "slow_motion_end": <slow_motion_start + 1.5>, "slow_motion_speed": 0.5.
- If no slow-motion is needed, set them to: "slow_motion_start": 0.0, "slow_motion_end": 0.0, "slow_motion_speed": 1.0.
- Max 1 slow-motion moment per clip.

{broll_instructions}
{clips_context}

Fixed values for all clips:
- caption_theme: "{profile['caption_theme']}"
- color_grade: "{profile['color_grade']}"

Return ONLY a JSON list:
[{{"index":1,"caption_theme":"...","zoom_style":"...","transition":"...","color_grade":"...","emphasis_words":["..."],"sfx_queries":["..."]{broll_json_field},"slow_motion_start":0.0,"slow_motion_end":0.0,"slow_motion_speed":1.0}}]
No markdown, no backticks."""

    try:
        result = _llm_ask(prompt, temperature=0.5)
        if "```" in result:
            result = result.split("```")[1]
            if result.startswith("json"):
                result = result[4:]
        effects = json.loads(result.strip())
        
        # ── Post-validation: enforce rules the AI might ignore ─────────
        if isinstance(effects, list):
            for i, eff in enumerate(effects):
                clip_idx = eff.get("index", i+1)

                # Enforce SFX budget: max 2
                sfx = eff.get("sfx_queries", [])
                if len(sfx) > 2:
                    print(f"  [تحقق] كليب {clip_idx}: تم تقليص المؤثرات الصوتية من {len(sfx)} إلى 2 | سبب: الحد الأقصى المسموح به")
                    eff["sfx_queries"] = sfx[:2]

                # Slow motion decision log
                slo_start = eff.get("slow_motion_start", 0.0)
                slo_end = eff.get("slow_motion_end", 0.0)
                slo_speed = eff.get("slow_motion_speed", 1.0)
                if slo_start > 0 or slo_end > 0:
                    print(f"  [سلوموشن] كليب {clip_idx}: {slo_start:.1f}ث→{slo_end:.1f}ث بسرعة {slo_speed}x | سبب: تم اكتشاف لحظة درامية تستحق التأخير")
                else:
                    print(f"  [سلوموشن] كليب {clip_idx}: لا يوجد | سبب: لم يجد الذكاء لحظة درامية كافية")

                # Enforce B-roll budget: max 2
                brolls = eff.get("brolls", [])
                removed_early = [br for br in brolls if br.get("start_offset", 0) < 5.0]
                if removed_early:
                    print(f"  [بي-رول] كليب {clip_idx}: تم حذف {len(removed_early)} بي-رول في أول 5ث | سبب: منطقة الهوك محمية")
                if len(brolls) > 2:
                    print(f"  [بي-رول] كليب {clip_idx}: تم تقليص البي-رولز من {len(brolls)} إلى 2 | سبب: الحد الأقصى")
                    eff["brolls"] = brolls[:2]
                # Remove B-rolls in first 5 seconds
                eff["brolls"] = [br for br in eff.get("brolls", []) if br.get("start_offset", 0) >= 5.0]

                # Phase 5: Remove B-rolls in high-energy emotional moments (using viral timeline)
                if viral_timeline and clips and i < len(clips):
                    clip_obj = clips[i]
                    valid_brolls = []
                    for br in eff.get("brolls", []):
                        start_offset = br.get("start_offset", 0.0)
                        abs_time = clip_obj.start_sec + start_offset
                        # Find nearest score in viral_timeline
                        nearest_time = min(viral_timeline.keys(), key=lambda t: abs(t - abs_time), default=None)
                        if nearest_time is not None and viral_timeline[nearest_time] > 0.75:
                            print(f"  [بي-رول] تم حذف بي-رول عند {start_offset:.1f}ث | سبب: طاقة عالية من المتحدث (viral_score={viral_timeline[nearest_time]:.2f} > 0.75) - المتحدث أكثر جاذبية من أي بي-رول")
                            continue
                        valid_brolls.append(br)
                    eff["brolls"] = valid_brolls
        
        return effects
    except Exception:
        return []


def validate_pre_render(clip, words, ass_path, plan_duration):
    """
    Validate clip inputs before rendering.
    Returns (is_valid, warnings_list).
    """
    warnings = []
    
    # 1. Clip duration check (tolerance +/- 2s)
    clip_dur = clip.end_sec - clip.start_sec
    if abs(clip_dur - plan_duration) > 2.0:
        warnings.append(f"Clip duration ({clip_dur:.1f}s) deviates from requested duration ({plan_duration}s) by >2s.")
        
    # 2. Hook sentence check
    if getattr(clip, "hook_sentence", None):
        hook_start = getattr(clip, "hook_sentence_start", 0.0)
        hook_end = getattr(clip, "hook_sentence_end", 0.0)
        if hook_start < 0.0 or hook_end > clip_dur:
            warnings.append(f"Hook sentence ({hook_start:.1f}s-{hook_end:.1f}s) is out of clip boundaries (0.0s-{clip_dur:.1f}s).")
            
    # 3. Caption ASS file validation
    if not os.path.exists(ass_path) or os.path.getsize(ass_path) == 0:
        warnings.append(f"Caption ASS file {os.path.basename(ass_path)} is missing or empty.")
        
    # 4. Speech percentage check
    cw = get_words_in_range(words, clip.start_sec, clip.end_sec)
    if cw:
        speech_dur = sum(w["end"] - w["start"] for w in cw)
        speech_ratio = speech_dur / clip_dur
        if speech_ratio < 0.50:
            warnings.append(f"Low speech ratio in clip ({speech_ratio*100:.0f}%). Clip contains a lot of silence/dead air.")
    else:
        warnings.append("No transcript words found inside clip boundaries.")
        
    # 5. Boundary alignment check
    if words:
        start_diffs = [abs(w["start"] - clip.start_sec) for w in words]
        end_diffs = [abs(w["end"] - clip.end_sec) for w in words]
        if min(start_diffs) > 0.5:
            warnings.append(f"Clip start ({clip.start_sec:.2f}s) is far from nearest word start ({min(start_diffs):.2f}s). Possible mid-word cut.")
        if min(end_diffs) > 0.5:
            warnings.append(f"Clip end ({clip.end_sec:.2f}s) is far from nearest word end ({min(end_diffs):.2f}s). Possible mid-word cut.")
            
    return len(warnings) == 0, warnings


def validate_post_render(output_path, expected_duration):
    """
    Validate output video file after rendering.
    Returns (is_valid, warnings_list).
    """
    warnings = []
    
    # 1. Check file existence and size
    if not os.path.exists(output_path):
        return False, ["Rendered video file does not exist."]
    if os.path.getsize(output_path) < 100 * 1024:
        warnings.append(f"Rendered video size is very small ({os.path.getsize(output_path)/1024:.1f} KB). Might be corrupted.")
        
    # 2. Check actual video duration using ffprobe
    try:
        from video_analyzer import _get_ffmpeg
        ffmpeg = _get_ffmpeg()
        ffprobe = ffmpeg.replace("ffmpeg", "ffprobe")
        if not os.path.isfile(ffprobe):
            ffprobe = "ffprobe"
            
        import subprocess
        result = subprocess.run(
            [ffprobe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=noprint_wrappers=1:nokey=1", output_path],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            actual_dur = float(result.stdout.strip())
            if abs(actual_dur - expected_duration) > 2.0:
                warnings.append(f"Actual video duration ({actual_dur:.1f}s) differs from expected duration ({expected_duration:.1f}s) by >2s.")
        else:
            print(f"  [Validation Warning] ffprobe failed with code {result.returncode}. Skipping duration check.")
    except Exception as e:
        # Convert this into a soft/silent console warning instead of failing the validation gate
        print(f"  [Validation Warning] Could not verify video duration with ffprobe (ffprobe not in PATH): {e}")
        
    return len(warnings) == 0, warnings


# ─────────────────────────────────────────────────────────────────────────────
#  Main Pipeline
# ─────────────────────────────────────────────────────────────────────────────

def run_editing_plan(plan: EditingPlan, status_callback=None, sound_fx: bool = False) -> list:
    global progress_callback
    progress_callback = status_callback

    content_type = getattr(plan, "content_type", "podcast")
    hook_mode = getattr(plan, "hook_mode", True)
    custom_instructions = getattr(plan, "custom_instructions", "")

    # ── UGC Campaign Automation Integration (Zero-Touch Mode) ────────────────
    try:
        from campaign import load_campaign
        campaign = load_campaign()
        if campaign:
            import sys
            # Simple logging setup for campaign activation
            sys.stdout.write(f"\n  📢 [Campaign Active] Applying strict automated rules for: '{campaign.name}'\n")
            
            # 1. Disable background music if forbidden by campaign
            if not getattr(campaign, "allow_bg_music", True):
                setattr(plan, "global_music", False)
                setattr(plan, "music_path", "")
                sys.stdout.write("    -> [Campaign Constraint] Background music is strictly forbidden. Disabled global music.\n")
                
            # 2. Disable B-rolls if forbidden by campaign
            if not getattr(campaign, "allow_broll", True):
                setattr(plan, "auto_broll", False)
                sys.stdout.write("    -> [Campaign Constraint] Stock B-rolls are strictly forbidden. Disabled auto B-roll.\n")
                
            # 3. Disable translation to Arabic if English/specific language required
            if not getattr(campaign, "translate_to_arabic", False):
                setattr(plan, "translate_to_arabic", False)
                sys.stdout.write("    -> [Campaign Constraint] Translation disabled (English content required).\n")
                
            # 4. Enforce minimum duration compliance (ONLY if slider wasn't explicitly changed)
            slider_duration = getattr(plan, "duration_sec", 60.0)
            if slider_duration < campaign.min_duration and slider_duration == 60.0:
                setattr(plan, "duration_sec", float(campaign.min_duration))
                sys.stdout.write(f"    -> [Campaign Constraint] Adjusted target duration to campaign minimum: {campaign.min_duration}s\n")
    except Exception as ex:
        import sys
        sys.stdout.write(f"  ⚠️ [Campaign Integration Warning] Failed to apply automated constraints: {ex}\n")

    # Load content type profile
    from content_types import get_type_profile
    ct_profile = get_type_profile(content_type)

    def log(msg):
        import sys
        try:
            sys.stdout.reconfigure(encoding='utf-8')
        except Exception:
            pass
        try:
            print(msg)
        except Exception:
            try:
                print(msg.encode('ascii', errors='replace').decode('ascii'))
            except Exception:
                pass
        if progress_callback:
            try:
                progress_callback(msg)
            except Exception:
                pass

    # Count steps: transcribe + select + effects + custom_parse + (per clip: captions+render) + compile
    # Hook is now found AFTER clip selection (within clip 1), not as a global pre-step
    extra_steps = 1 if hook_mode else 0  # hook find within clip 1
    total_steps = 4 + extra_steps + plan.n_clips * 2 + 1
    step = 0

    # ── PHASE 9: Background Audio Pre-extraction for 10x Viral Scorer Speedup ─
    pre_extracted_audio = None
    def pre_extract_audio_worker():
        nonlocal pre_extracted_audio
        try:
            import tempfile, subprocess, imageio_ffmpeg
            fd, temp_wav = tempfile.mkstemp(suffix="_pre_extract.wav")
            os.close(fd)
            ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
            subprocess.run(
                [ffmpeg, "-y", "-i", plan.video_path,
                 "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                 temp_wav],
                capture_output=True, timeout=120
            )
            if os.path.exists(temp_wav):
                pre_extracted_audio = temp_wav
                log("  [Pre-extract] Background audio extraction finished successfully!")
        except Exception as e:
            log(f"  [Pre-extract] Background audio extraction skipped: {e}")

    import threading
    audio_thread = threading.Thread(target=pre_extract_audio_worker, daemon=True)
    audio_thread.start()

    def pstep(msg):
        nonlocal step
        step += 1
        pct = int(step / total_steps * 100)
        log(f"[{step}/{total_steps}] {msg} ({pct}%)")

    # ── Step 1: Transcribe ────────────────────────────────────────────────────
    pstep("🧠 Transcribing audio with faster-whisper (Fast mode)...")
    words = generate_subtitles(plan.video_path)
    if not words:
        raise Exception("Transcription returned no words.")
    log(f"  → {len(words)} words, {words[-1]['end']:.0f}s duration")

    total_duration = words[-1]['end']
    plan.analysis = VideoAnalysis(
        duration=total_duration, total_words=len(words),
        has_audio=True, key_moments=[]
    )

    # ── Auto-Genre Detection (Phase 14) ──
    if content_type == "auto":
        pstep("🔍 Auto-detecting video genre/content type...")
        # Get first 60 seconds of words
        sample_words = [w["text"] for w in words if w["start"] < 60.0]
        sample_text = " ".join(sample_words)
        
        prompt = f"""Analyze this video transcript segment and classify the video into one of these genres:
- "podcast" (conversational, discussion, two or more people talking, podcast style)
- "awareness" (deep, motivational, emotional, story-telling, serious)
- "comedy" (funny, humorous, light-hearted, entertainment)
- "interview" (Q&A format, news interview)
- "motivation" (inspiring, high energy, speech)
- "educational" (explaining a concept, tutorial, teaching)

Transcript: "{sample_text}"

Return ONLY one word from the list above (lowercase, no punctuation, no explanation)."""
        try:
            detected = _llm_ask(prompt, temperature=0.3).strip().lower()
            if detected in ["podcast", "awareness", "comedy", "interview", "motivation", "educational"]:
                content_type = detected
                log(f"  🎯 اكتشف الذكاء الاصطناعي النوع: {content_type.upper()} | سبب: تحليل أول 60 ثانية من المحتوى")
            else:
                content_type = "podcast"
                log(f"  ⚠️ الكشف أعاد نوعاً غير معروف: '{detected}'. سيتم استخدام PODCAST افتراضياً.")
        except Exception as e:
            content_type = "podcast"
            log(f"  ⚠️ فشل كشف النوع التلقائي ({e}). سيتم استخدام PODCAST افتراضياً.")

        # Re-initialize content type profile and settings based on newly detected genre
        from content_types import get_type_profile
        ct_profile = get_type_profile(content_type)

    # ── Phase A3: Content DNA Extraction ──
    pstep("🧬 Extracting Content DNA characteristics...")
    from content_dna import extract_content_dna
    content_dna = extract_content_dna(words, llm_fn=_llm_ask)
    log(f"  🧬 Content DNA extracted: {content_dna}")

    # ── Step 2: Hook will be found WITHIN first clip after clip selection ───────
    # (moved below clip selection to use correct clip boundaries and local timestamps)
    hook_info = {"text": "", "start_sec": 0.0, "end_sec": 3.0}

    # ── Step 3: Parse Custom Instructions ────────────────────────────────────
    custom_actions = {}
    if custom_instructions and custom_instructions.strip():
        pstep("💬 Parsing your custom instructions...")
        custom_actions = _parse_custom_instructions(custom_instructions, total_duration)
        log(f"  -> Custom actions: {custom_actions}")

    # ── Step 3.5: Viral Score Engine ─────────────────────────────────────────
    viral_timeline = {}
    try:
        from viral_scorer import get_viral_timeline, get_top_moments, format_viral_summary
        pstep("🔥 Computing viral score for every moment...")
        # Join background audio extraction thread (timeout 10s to keep UX snappy)
        audio_thread.join(timeout=10.0)
        viral_timeline = get_viral_timeline(plan.video_path, words, audio_path=pre_extracted_audio)
        if viral_timeline:
            top = get_top_moments(viral_timeline, n=plan.n_clips + 2, min_gap_sec=8.0)
            log(format_viral_summary(viral_timeline, top_n=5))
    except Exception as e:
        log(f"  -> Viral scorer skipped: {e}")

    # ── Step 4: Select Best Clips ────────────────────────────────────────────
    ai_clips = []
    
    # ── Phase 9: Manual Trim Mode ───────────────────────────────────────────
    if getattr(plan, "manual_clip_bounds", None) is not None:
        pstep("✂️ Manual Trim Mode: Using your exact clip selection...")
        start_s, end_s = plan.manual_clip_bounds
        ai_clips = [{
            "index": 1,
            "start_sec": start_s,
            "end_sec": end_s,
            "hook_options": ["المقطع المخصص", "شاهد هذا المقطع", "لحظة مميزة"],
            "reason": "تم التحديد يدوياً من قبل المستخدم"
        }]
    else:
        # ── Phase 7: Gemma Video Multimodal Analysis ──────────────────────────
        use_gemma_multimodal = getattr(plan, "gemma_multimodal", False)
            
        if use_gemma_multimodal:
            pstep("🎯 AI selecting best clips via Gemma Multimodal Video API (Phase 7)...")
            try:
                from gemma_multimodal import upload_and_analyze_video
                api_key = getattr(plan, "api_key", "") or _API_KEY
                use_scene_captioning = getattr(plan, "use_scene_captioning", False)
                use_local_captioning = getattr(plan, "use_local_captioning", True)
                
                ai_clips = upload_and_analyze_video(
                    video_path=plan.video_path,
                    api_key=api_key,
                    n_clips=plan.n_clips,
                    duration_sec=plan.duration_sec,
                    content_type=content_type,
                    words=words,
                    use_scene_captioning=use_scene_captioning,
                    use_local_captioning=use_local_captioning,
                )
                if ai_clips:
                    log(f"  ✅ Gemma Multimodal successfully planned {len(ai_clips)} clips!")
                else:
                    log("  ⚠️ Gemma Multimodal returned no clips, falling back to local ASR transcript planning...")
            except Exception as e:
                log(f"  ⚠️ Gemma Multimodal analysis failed ({e}), falling back to local ASR transcript planning...")

    # Fallback to local Gemma 4 ASR transcript selection
    if not ai_clips:
        pstep("🎯 AI selecting best clip moments (calling Gemma 4 local transcript)...")
        # Build viral context string for Gemma (top moments as hints)
        viral_context = ""
        if viral_timeline:
            try:
                from viral_scorer import get_top_moments
                top_moments = get_top_moments(viral_timeline, n=8, min_gap_sec=5.0)
                if top_moments:
                    hints = [f"{t:.1f}s (score={s:.2f})" for t, s in sorted(top_moments)]
                    viral_context = f"\n\nViral Score Hints (highest engagement moments): {', '.join(hints)}"
            except Exception:
                pass
        ai_clips = _select_clips_with_ai(words, plan.n_clips, plan.duration_sec, content_type, viral_context=viral_context, custom_instructions=getattr(plan, "custom_instructions", ""))

    if ai_clips:
        log(f"  [قرار الذكاء] تم اختيار {len(ai_clips)} كليب من المحتوى. تفاصيل كل كليب:")
        for c in ai_clips:
            # Annotate each clip with its viral score
            clip_score = 0.0
            if viral_timeline:
                try:
                    from viral_scorer import get_segment_score
                    clip_score = get_segment_score(viral_timeline, c.get("start_sec", 0), c.get("end_sec", 0))
                except Exception:
                    pass
            reason = c.get('reason', 'لا يوجد سبب')
            log(f"  └► كليب {c.get('index')}: {c.get('start_sec',0):.1f}ث → {c.get('end_sec',0):.1f}ث | درجة فيرال={clip_score:.2f} | سبب الذكاء: {reason}")
    else:
        log("  [قرار الذكاء] لم يتم اختيار أي كليب!")
        return []

    plan.clips = []
    for c in ai_clips:
        options = c.get("hook_options", [])
        if not options:
            hook_val = c.get("hook", "")
            if hook_val:
                options = [
                    hook_val,
                    f"السر وراء {hook_val}",
                    f"احذر من هذا {hook_val}"
                ]
            else:
                options = ["السيناريو الاول المقترح", "السيناريو الثاني البديل", "السيناريو الثالث البديل"]
        
        clip = ClipSpec(
            index=c.get("index"),
            start_sec=c.get("start_sec", 0),
            end_sec=c.get("end_sec", plan.duration_sec),
            hook=options[0],
            reason=c.get("reason", ""),
            # Apply content-type defaults
            caption_theme=ct_profile["caption_theme"],
            zoom_style=ct_profile["zoom_style"],
            color_grade=ct_profile["color_grade"],
            hook_options=options,
        )
        # Store planned B-rolls inside clip if returned by Gemma Multimodal
        clip.planned_brolls = c.get("brolls", [])
        clip.narrative_acts = c.get("narrative_acts", [])
        
        plan.clips.append(clip)

    # ── Phase 2: Scenario Selection Interactive Step ──────────────────────────
    review_cb = getattr(plan, "plan_review_callback", None)
    if review_cb:
        log("💡 Presenting AI Scenarios and titles to the user for review...")
        review_cb(plan.clips, words)

    # ── Step 4.5: Find Hook WITHIN First Clip (local timestamps) ─────────────
    if hook_mode and plan.clips:
        first_clip = plan.clips[0]
        clip_dur = first_clip.end_sec - first_clip.start_sec
        # Get only the words within the first clip's time range
        clip_words_abs = get_words_in_range(words, first_clip.start_sec, first_clip.end_sec)
        hook_info = {"text": "", "start_sec": 0.0, "end_sec": 3.0}
        if clip_words_abs:
            # Convert to LOCAL time (relative to clip start = 0)
            clip_words_local = [
                {**w,
                 "start": max(0.0, w["start"] - first_clip.start_sec),
                 "end":   max(0.0, w["end"]   - first_clip.start_sec)}
                for w in clip_words_abs
            ]
            pstep(f"🎭 البحث عن أفضل لحظة هوك داخل الكليب 1 ({clip_dur:.0f}ث) لنوع محتوى: {content_type}...")
            hook_info = _find_hook_sentence(clip_words_local, content_type)
            # Ensure the hook is NOT from the very start of the clip (>2s in)
            # If AI returned start=0 (beginning), nudge it to find a better moment
            if hook_info["start_sec"] < 2.0 and clip_dur > 10.0:
                log(f"  [هوك] الذكاء اختار بداية الكليب (قبل 2ث) وهو مبكر جداً. جاري البحث عن لحظة أقوى بعد 2ث...")
                later_words = [w for w in clip_words_local if w["start"] >= 2.0]
                if later_words and len(later_words) > 5:
                    hook_info_later = _find_hook_sentence(later_words, content_type)
                    if hook_info_later["text"]:
                        hook_info = hook_info_later
                        log(f"  [هوك] تم تحديث الهوك بلحظة أفضل: \"{hook_info['text'][:50]}\"")
            # Clamp to clip boundaries
            hook_info["start_sec"] = max(0.0, min(hook_info["start_sec"], clip_dur - 1.5))
            hook_info["end_sec"]   = max(hook_info["start_sec"] + 1.5, min(hook_info["end_sec"], clip_dur))
            log(f"  [هوك نهائي] لحظة {hook_info['start_sec']:.1f}ث–{hook_info['end_sec']:.1f}ث: \"{hook_info['text'][:60]}\" | سبب: أعلى جملة في نظام التقييم")
        else:
            log("  ⚠️ [هوك] لا توجد كلمات داخل الكليب 1. سبب: لا يوجد نص منطوق في هذا الجزء.")
        # Attach local-time hook info to first clip
        first_clip.hook_sentence       = hook_info["text"]
        first_clip.hook_sentence_start = hook_info["start_sec"]  # LOCAL time
        first_clip.hook_sentence_end   = hook_info["end_sec"]    # LOCAL time

    # ── Step 5: Plan Effects ─────────────────────────────────────────────────
    pstep("🎬 AI planning effects (captions, zooms, transitions, color grades)...")
    clip_texts = []
    clip_words_list = []
    for c in plan.clips:
        cw = get_words_in_range(words, c.start_sec, c.end_sec)
        clip_texts.append(" ".join(w['text'] for w in cw)[:200])
        clip_words_list.append(cw)

    import random
    effects = _plan_effects_with_ai(clip_texts, content_type,
                                     auto_broll=getattr(plan, "auto_broll", False),
                                     clip_words_list=clip_words_list,
                                     viral_timeline=viral_timeline,
                                     clips=plan.clips)
    if effects:
        log("  ✅ تم استلام تأثيرات الذكاء الاصطناعي، تفاصيل القرارات لكل كليب:")
        for eff in effects:
            idx = eff.get("index", 0)
            for clip in plan.clips:
                if clip.index == idx:
                    prev_theme = clip.caption_theme
                    prev_zoom = clip.zoom_style
                    prev_grade = clip.color_grade
                    clip.caption_theme = eff.get("caption_theme", ct_profile["caption_theme"])
                    clip.zoom_style = eff.get("zoom_style", ct_profile["zoom_style"])
                    clip.transition = eff.get("transition", "crossfade")
                    clip.color_grade = eff.get("color_grade", ct_profile["color_grade"])
                    clip.emphasis_words = eff.get("emphasis_words", [])
                    clip.sfx_queries = eff.get("sfx_queries", get_emphasis_sfx(content_type)[:2])
                    clip.planned_brolls = eff.get("brolls", [])
                    clip.slow_motion_start = float(eff.get("slow_motion_start", 0.0))
                    clip.slow_motion_end = float(eff.get("slow_motion_end", 0.0))
                    clip.slow_motion_speed = float(eff.get("slow_motion_speed", 1.0))
                    log(f"  ├─ كليب {idx}: ثيم={clip.caption_theme}({prev_theme}→) | زوم={clip.zoom_style}({prev_zoom}→) | لون={clip.color_grade}({prev_grade}→) | انتقال={clip.transition} | سلومو={clip.slow_motion_speed}x | تأكيد={clip.emphasis_words}")
    else:
        log("  ⚠️ AI effects unavailable, using content-type smart defaults...")
        _TRANSITIONS = ["crossfade", "slide_left", "slide_up", "zoom_in", "fadewhite"]
        for i, clip in enumerate(plan.clips):
            clip.zoom_style = ct_profile["zoom_style"]
            clip.color_grade = ct_profile["color_grade"]
            clip.transition = _TRANSITIONS[i % len(_TRANSITIONS)]
            cw = get_words_in_range(words, clip.start_sec, clip.end_sec)
            clip.emphasis_words = list(set(
                w['text'].strip(".,!?;:()\"'").lower()
                for w in cw
                if w['text'].strip(".,!?;:()\"'").lower() in EMOJI_DICT
            ))[:5]
            clip.sfx_queries = get_emphasis_sfx(content_type)[:len(clip.emphasis_words)]
            log(f"  → Clip {clip.index}: zoom={clip.zoom_style}, grade={clip.color_grade}, trans={clip.transition}")

    # ── Steps 6+: Render Clips in Parallel (Dual English & Arabic Versions) ───
    output_dir = os.path.join(os.path.dirname(plan.video_path), "clips_output")
    os.makedirs(output_dir, exist_ok=True)

    import concurrent.futures
    from concurrent.futures import ThreadPoolExecutor

    def render_single_language_task(idx, clip, language):
        clip_label = f"clip_{idx+1:02d}"
        is_first_clip = (idx == 0)
        hook_sentence = clip.hook_sentence if (hook_mode and is_first_clip) else ""
        hook_start = clip.hook_sentence_start if (hook_mode and is_first_clip) else 0.0
        hook_end = clip.hook_sentence_end if (hook_mode and is_first_clip) else 0.0

        if language == "main":
            ass_path = os.path.join(output_dir, f"{clip_label}_main.ass")
            clip_output = os.path.join(output_dir, f"{clip_label}_main.mp4")
            translate = False
            sfx_on = sound_fx
        else:
            ass_path = os.path.join(output_dir, f"{clip_label}_arabic.ass")
            clip_output = os.path.join(output_dir, f"{clip_label}_arabic.mp4")
            translate = True
            sfx_on = False  # Arabic avoids duplicate SFX
            
        caption_anim_mode = getattr(plan, "caption_animation_mode", "classic")

        # ── 1. Video intelligence scene analysis ──
        smart_crop_filter = None
        scene_data = {"scene_type": "studio", "n_persons": 1}
        try:
            beats = []
            music_path = plan.music_path if plan.global_music else None
            if music_path and os.path.exists(music_path):
                try:
                    from editor import detect_beats
                    beats = detect_beats(music_path)
                except Exception as ex:
                    log(f"  [BEAT SYNC] Beat detection failed: {ex}")

            from video_analyzer import quick_scene_type
            scene_data = quick_scene_type(
                plan.video_path,
                clip.start_sec,
                clip.end_sec,
                framing_strategy=getattr(plan, "framing_strategy", "split_screen"),
                content_type=content_type,
                viral_timeline=viral_timeline,
                beats=beats,
                zoom_style=getattr(clip, "zoom_style", "none")
            )
            smart_crop_filter = scene_data["crop_filter"]
            scene_info = f"نوع={scene_data.get('scene_type','?')}, أشخاص={scene_data.get('n_persons','?')}"
            log(f"  [تحليل مشهد] الكليب {idx+1}: {scene_info} | الحصاد: smart_crop={'مفعّل' if smart_crop_filter else 'أوف'} | سبب: نوع المحتوى={content_type}")
        except Exception as e:
            log(f"  ⚠️ [تحليل] quick_scene_type فشل: {e}")

        # ── 2. Autonomous AI Director Decisions ──
        emoji_map = {}
        try:
            from ai_director import generate_director_decisions
            director_dec = generate_director_decisions(
                clip_index=clip.index,
                start_sec=clip.start_sec,
                end_sec=clip.end_sec,
                content_dna=content_dna,
                scene_data=scene_data,
                words=words,
                llm_fn=_llm_ask
            )
            log(f"  🧠 [مخرج ذكي] قرارات الكليب {clip.index}:"
                f" زوم={director_dec.zoom_style}, تأطير={director_dec.framing},"
                f" تأثيراتصوت={len(director_dec.sfx_plan)}, صمت={director_dec.silence_mode}"
                f" | سبب: تحليل نوع المشهد ({scene_data.get('scene_type','?')}) والحمض الجيني ({content_dna})")
            
            # Apply decisions
            clip.zoom_style = director_dec.zoom_style
            emoji_map = director_dec.caption_emoji_map
            if emoji_map:
                clip.emphasis_words = list(emoji_map.keys())
        except Exception as ed:
            log(f"  ⚠️ [AI Director] Decisions failed: {ed}")

        # A. Generate Subtitles ASS file
        res_x = 1080
        res_y = 1920
        framing_strat = getattr(plan, "framing_strategy", "split_screen")
        if framing_strat == "no_crop":
            try:
                from video_analyzer import _get_video_dimensions
                res_x, res_y = _get_video_dimensions(plan.video_path)
            except Exception:
                pass

        # Determine pacing speedup factor (if slow speech rate detected)
        pacing_speed = 1.0
        clip_dur = clip.end_sec - clip.start_sec
        if words and clip_dur > 0.0:
            clip_words = [w for w in words if w['end'] >= clip.start_sec and w['start'] <= clip.end_sec]
            if clip_words:
                words_per_sec = len(clip_words) / clip_dur
                if words_per_sec < 2.0:
                    pacing_speed = 1.1

        generate_ass_for_clip(
            words,
            clip.start_sec,
            clip.end_sec,
            ass_path,
            theme=clip.caption_theme,
            font_name=getattr(plan, "font_name", None),
            translate_to_arabic=translate,
            animation_mode=caption_anim_mode,
            content_type=content_type,
            emphasis_words=clip.emphasis_words if clip.emphasis_words else [],
            hook_start_sec=hook_start,
            hook_end_sec=hook_end,
            res_x=res_x,
            res_y=res_y,
            pacing_speed=pacing_speed,
            slow_motion_start=getattr(clip, "slow_motion_start", 0.0),
            slow_motion_end=getattr(clip, "slow_motion_end", 0.0),
            slow_motion_speed=getattr(clip, "slow_motion_speed", 1.0),
            narrative_acts=getattr(clip, "narrative_acts", None),
            emoji_map=emoji_map,
        )

        # B. Prepare B-Rolls (if enabled)
        brolls_to_render = []
        if getattr(plan, "auto_broll", False):
            # Fix: use planned_brolls (correct attribute name from ClipSpec)
            planned_brolls = getattr(clip, "planned_brolls", []) or []
            if planned_brolls:
                broll_cache_dir = os.path.join(os.path.dirname(plan.video_path), "broll_cache")
                pexels_key = getattr(plan, "pexels_api_key", "") or DEFAULT_PEXELS_KEY
                pixabay_key = getattr(plan, "pixabay_api_key", "")
                for br in planned_brolls:
                    keyword = br.get("keyword")
                    if not keyword:
                        continue
                    start_offset = br.get("start_offset", 0.0)
                    dur = br.get("duration", 3.0)
                    from broll_manager import download_pexels_broll
                    local_path = download_pexels_broll(
                        keyword,
                        broll_cache_dir,
                        pexels_api_key=pexels_key,
                        gemma_api_key=api_key,
                        pixabay_api_key=pixabay_key
                    )
                    if local_path and os.path.exists(local_path):
                        brolls_to_render.append({
                            "local_path": local_path,
                            "start_offset": start_offset,
                            "duration": dur
                        })

        emphasis = get_emphasis_timestamps(words, clip.start_sec, clip.end_sec)
        if not emphasis and clip.emphasis_words:
            cw = get_words_in_range(words, clip.start_sec, clip.end_sec)
            for w in cw:
                clean = w['text'].strip(".,!?;:()\"'").lower()
                if any(ew.lower() in clean for ew in clip.emphasis_words):
                    emphasis.append((
                        max(0.0, w['start'] - clip.start_sec),
                        max(0.0, w['end'] - clip.start_sec)
                    ))

        # Determine ending CTA
        ending_cta = plan.global_ending_cta
        if custom_actions.get("extra_cta"):
            ending_cta = custom_actions["extra_cta"]

        # Determine overlay text from custom instructions
        overlay_text = custom_actions.get("overlay_text", "")
        overlay_position = custom_actions.get("overlay_position", "center")
        overlay_time_start = custom_actions.get("overlay_time_start", 0)
        overlay_time_end = custom_actions.get("overlay_time_end", 0)

        # Pre-render Validation Gate
        is_pre_valid, pre_warnings = validate_pre_render(clip, words, ass_path, plan.duration_sec)
        if not is_pre_valid:
            log(f"  ⚠️ [تحقق مسبق] الكليب {idx+1} لم يجتز بعض فحوصات الجودة:")
            for w in pre_warnings:
                log(f"    - {w}")
        else:
            log(f"  [تحقق مسبق] الكليب {idx+1} اجتاز جميع الفحوصات.")

        _auto_director = True

        log(f"  [تصدير] بدء تصدير الكليب رقم {idx+1}...")
        export(
            video_path=plan.video_path,
            start_sec=clip.start_sec,
            end_sec=clip.end_sec,
            output_path=clip_output,
            clip_index=clip.index,
            ass_path=ass_path,
            words=words,
            trim_silence=True,  # Activated to use new advanced silence_trimmer!
            scale_punches=False,
            auto_director=_auto_director,
            emphasis_timestamps=emphasis,
            theme=clip.caption_theme,
            music_path=plan.music_path if plan.global_music else None,
            audio_ducking=True,
            color_grade=clip.color_grade,
            sound_fx=sfx_on,
            sfx_queries=getattr(clip, "sfx_queries", None),
            content_type=content_type,
            ending_cta=ending_cta,
            overlay_text=overlay_text,
            overlay_position=overlay_position,
            overlay_time_start=float(overlay_time_start),
            overlay_time_end=float(overlay_time_end),
            hook_sentence=hook_sentence,
            hook_start_sec=hook_start,
            hook_end_sec=hook_end,
            outro_enabled=getattr(plan, "outro_enabled", True),
            smart_crop_filter=smart_crop_filter,
            export_quality=getattr(plan, "export_quality", "High"),
            logo_path=getattr(plan, "logo_path", None),
            brolls=brolls_to_render,
            sfx_mode=getattr(plan, "sfx_mode", "normal"),
            zoom_style=getattr(clip, "zoom_style", "none"),
            slow_motion_start=getattr(clip, "slow_motion_start", 0.0),
            slow_motion_end=getattr(clip, "slow_motion_end", 0.0),
            slow_motion_speed=getattr(clip, "slow_motion_speed", 1.0),
            narrative_acts=getattr(clip, "narrative_acts", None),
        )
        log(f"  ✅ [تصدير] انتهى تصدير الكليب رقم {idx+1} بنجاح.")

        # ── Phase 9: AI Content Scoring & Title Generation (A/B Testing) ──
        hook_variants = getattr(clip, "hook_options", []) or []
        hook_variants = [hv.strip() for hv in hook_variants if hv and hv.strip()]

        if (not hook_variants or len(hook_variants) < 3) and is_first_clip:
            try:
                cw_words = [w["text"] for w in words if clip.start_sec <= w["start"] <= clip.end_sec]
                cw_text = " ".join(cw_words)
                if not cw_text:
                    cw_text = clip.reason or "Short clip"
                from orchestrator import generate_hook_alternatives
                api_key = getattr(plan, "api_key", "") or os.environ.get("GEMMA_API_KEY", "")
                hook_variants = generate_hook_alternatives(cw_text, content_type, api_key=api_key)
            except Exception as e:
                log(f"  [A/B تيستينج] فشل توليد بدائل الهوك أوفلاين: {e}")

        if False and hook_variants and len(hook_variants) >= 3 and is_first_clip: # DISABLED per user request
            angles = ["خطأ", "سر", "قصة"]
            log(f"  [A/B تيستينج] جاري تصدير 3 نسخ نفسية للكليب رقم {idx+1}...")
            for v_idx, hv in enumerate(hook_variants[:3]):
                variant_output = clip_output.replace(".mp4", f"_AB_{angles[v_idx]}.mp4")
                log(f"  [A/B تيستينج] تصدير نسخة '{angles[v_idx]}' -> {variant_output}")
                try:
                    export(
                        video_path=plan.video_path,
                        start_sec=clip.start_sec,
                        end_sec=clip.end_sec,
                        output_path=variant_output,
                        clip_index=clip.index,
                        ass_path=ass_path,
                        words=words,
                        trim_silence=True,
                        scale_punches=False,
                        auto_director=_auto_director,
                        emphasis_timestamps=emphasis,
                        theme=clip.caption_theme,
                        music_path=plan.music_path if plan.global_music else None,
                        audio_ducking=True,
                        color_grade=clip.color_grade,
                        sound_fx=sfx_on,
                        sfx_queries=getattr(clip, "sfx_queries", None),
                        content_type=content_type,
                        ending_cta=ending_cta,
                        overlay_text=hv,  # عنوان نفسي للـ title card الأولى
                        overlay_position="top",
                        overlay_time_start=0.0,
                        overlay_time_end=3.5,  # title card تظهر في أول 3.5 ثانية
                        hook_sentence=hook_sentence,
                        hook_start_sec=hook_start,
                        hook_end_sec=hook_end,
                        outro_enabled=getattr(plan, "outro_enabled", True),
                        smart_crop_filter=smart_crop_filter,
                        export_quality=getattr(plan, "export_quality", "High"),
                        logo_path=getattr(plan, "logo_path", None),
                        brolls=brolls_to_render,
                        sfx_mode=getattr(plan, "sfx_mode", "normal"),
                        zoom_style=getattr(clip, "zoom_style", "none"),
                        slow_motion_start=getattr(clip, "slow_motion_start", 0.0),
                        slow_motion_end=getattr(clip, "slow_motion_end", 0.0),
                        slow_motion_speed=getattr(clip, "slow_motion_speed", 1.0),
                        narrative_acts=getattr(clip, "narrative_acts", None),
                    )
                    log(f"  ✅ [A/B تيستينج] اكتملت نسخة '{angles[v_idx]}'.")
                except Exception as ex:
                    log(f"  ⚠️ [A/B تيستينج] تم تخطي نسخة '{angles[v_idx]}': {ex}")

        # Post-render Validation Gate
        expected_dur = clip.end_sec - clip.start_sec
        is_post_valid, post_warnings = validate_post_render(clip_output, expected_dur)
        if not is_post_valid:
            log(f"  ❌ [تحقق] الكليب {idx+1} فشل في فحص الجودة:")
            for w in post_warnings:
                log(f"    - {w}")
        else:
            log(f"  ✅ [تحقق] الكليب {idx+1} اجتاز فحص الجودة بنجاح.")

        return idx, language, clip_output

    # Prepare tasks list
    if getattr(plan, "export_mode", "ffmpeg") == "davinci":
        pstep("🎬 وضع DaVinci Resolve: جاري بناء مشروع الـ Timeline...")
        from resolve_exporter import export_fcp_xml
        clips_data = [{"start_sec": c.start_sec, "end_sec": c.end_sec} for c in plan.clips]
        xml_path = os.path.join(output_dir, "DaVinci_Clippify_Project.xml")
        export_fcp_xml(plan.video_path, clips_data, xml_path)
        pstep(f"🎉 اكتمل تصدير المشروع! اسحب ملف الـ XML داخل DaVinci Resolve.")
        return [xml_path]

    tasks_to_submit = []
    for idx, clip in enumerate(plan.clips):
        tasks_to_submit.append((idx, clip, "main"))  # اللغة الأصلية للمحتوى
        if getattr(plan, "translate_to_arabic", False):
            tasks_to_submit.append((idx, clip, "arabic"))

    # Dynamically select optimal thread count (max 4 concurrent renders)
    max_threads = min(os.cpu_count() or 4, len(tasks_to_submit), 4)
    pstep(f"🚀 تشغيل خوارزمية التصدير المتوازي باستخدام {max_threads} خيط متزامن...")
    
    main_clip_paths_ordered = [None] * len(plan.clips)
    arabic_clip_paths_ordered = [None] * len(plan.clips)
    
    with ThreadPoolExecutor(max_workers=max_threads) as executor:
        futures = {executor.submit(render_single_language_task, idx, clip, lang): (idx, lang) for idx, clip, lang in tasks_to_submit}
        for future in concurrent.futures.as_completed(futures):
            idx, lang = futures[future]
            try:
                idx_res, lang_res, clip_out = future.result()
                if lang_res == "main":
                    main_clip_paths_ordered[idx_res] = clip_out
                else:
                    arabic_clip_paths_ordered[idx_res] = clip_out
                pstep(f"🎉 اكتمل تصدير الكليب {idx_res+1} بنجاح!")
            except Exception as e:
                log(f"  ❌ فشل التصدير المتوازي للكليب {idx+1}: {e}")
                raise e

    # بناء قوائم المسارات النهائية
    main_clip_paths = [path for path in main_clip_paths_ordered if path]
    arabic_clip_paths = [path for path in arabic_clip_paths_ordered if path]

    # ── دمج الكليبات النهائية ──────────────────────────────────────────────
    compiled_main_path = None
    compiled_arabic_path = None
    
    if plan.compile_clips and len(main_clip_paths) > 1:
        # أ. دمج الكليبات الأصلية
        pstep("🔗 جاري دمج الكليبات مع انتقالات احترافية...")
        compiled_main_path = os.path.join(output_dir, "compiled_final.mp4")
        trans_list = [plan.clips[i+1].transition for i in range(len(plan.clips)-1)]
        log(f"  → الانتقالات: {trans_list}")
        from editor import compile_clips
        compile_clips(main_clip_paths, compiled_main_path,
                      transitions=trans_list, transition_duration=0.4,
                      jl_cut="none", export_quality=getattr(plan, "export_quality", "High"))
        clip_size = os.path.getsize(compiled_main_path) / 1024
        log(f"  ✅ اكتمل الدمج ({clip_size:.0f} كيلوبايت)")
        
        # ب. دمج الكليبات العربية (فقط إذا كان الترجمة مفعّلة)
        if getattr(plan, "translate_to_arabic", False) and len(arabic_clip_paths) > 1:
            pstep("🔗 جاري دمج الكليبات العربية...")
            compiled_arabic_path = os.path.join(output_dir, "compiled_final_arabic.mp4")
            compile_clips(arabic_clip_paths, compiled_arabic_path,
                          transitions=trans_list, transition_duration=0.4,
                          jl_cut="none", export_quality=getattr(plan, "export_quality", "High"))
            clip_size = os.path.getsize(compiled_arabic_path) / 1024
            log(f"  ✅ اكتمل دمج الكليبات العربية ({clip_size:.0f} كيلوبايت)")

    elif plan.compile_clips and len(main_clip_paths) >= 1:
        compiled_main_path = os.path.join(output_dir, "compiled_final.mp4")
        import shutil
        shutil.copy2(main_clip_paths[0], compiled_main_path)
        log(f"  → كليب واحد، تم نسخه كملف مدمج")
        
        if getattr(plan, "translate_to_arabic", False) and len(arabic_clip_paths) >= 1:
            compiled_arabic_path = os.path.join(output_dir, "compiled_final_arabic.mp4")
            shutil.copy2(arabic_clip_paths[0], compiled_arabic_path)
            log(f"  → نسخة عربية: تم نسخها كملف مدمج")

    # تجميع كل المسارات للإرجاع
    all_output_paths = []
    all_output_paths.extend(main_clip_paths)
    all_output_paths.extend(arabic_clip_paths)
    if compiled_main_path:
        all_output_paths.append(compiled_main_path)
    if compiled_arabic_path:
        all_output_paths.append(compiled_arabic_path)

    log(f"[{total_steps}/{total_steps}] ✅ Pipeline complete! {len(all_output_paths)} file(s) ready (100%)")

    # Clean up background pre-extracted audio file if exists
    if pre_extracted_audio and os.path.exists(pre_extracted_audio):
        try:
            os.remove(pre_extracted_audio)
            log("  [Pre-extract] Cleaned up temporary background audio file.")
        except Exception:
            pass

    return all_output_paths


def generate_hook_alternatives(clip_text: str, content_type: str, api_key: str = None) -> list:
    """Generate 3 alternative viral hooks for a clip using Gemma (if online) or smart local generator (if offline)."""
    # 1. Online Gemma Generator
    if api_key:
        try:
            from google import genai
            from google.genai import types
            client = genai.Client(api_key=api_key)
            
            prompt = f"""You are a professional social media viral editor.
Analyze this video transcript snippet:
"{clip_text}"

Generate EXACTLY 3 extremely engaging, creative, and viral hook titles/sentences (mostly in Arabic if the text is Arabic, or English if English) that would serve as a powerful teaser for a short-form video (TikTok/Reels/Shorts).
Return ONLY a valid JSON list of EXACTLY 3 strings, with no markdown wrapping, no backticks, and no explanation. Example:
["Hook Option 1", "Hook Option 2", "Hook Option 3"]"""

            response = client.models.generate_content(
                model="gemma-2-27b-it",
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.85,
                    response_mime_type="application/json"
                )
            )
            import json
            res = json.loads(response.text.strip())
            if isinstance(res, list) and len(res) >= 3:
                return [str(x) for x in res[:3]]
        except Exception as e:
            print(f"  [Orchestrator] Gemma hook regeneration failed ({e}), falling back to local generator...")

    # 2. Smart Local Rule-based Generator (Fully Offline)
    words = [w.strip(".,!?;:()\"'") for w in clip_text.split() if len(w.strip(".,!?;:()\"'")) > 2]
    keywords = words[:5] if words else ["المقطع"]
    base_phrase = " ".join(keywords[:3]) if len(keywords) >= 3 else keywords[0]

    is_arabic = any(ord(char) > 1200 for char in clip_text)
    if is_arabic:
        return [
            f"🤔 السر الصادم وراء {base_phrase}!",
            f"⚠️ أكبر خطأ تقع فيه عند {base_phrase}!",
            f"💡 لو عايز تنجح في {base_phrase}، اسمع ده فوراً! 👇"
        ]
    else:
        return [
            f"🤔 The shocking secret behind {base_phrase}!",
            f"⚠️ The #1 mistake people make when it comes to {base_phrase}!",
            f"💡 If you want to master {base_phrase}, watch this immediately! 👇"
        ]

