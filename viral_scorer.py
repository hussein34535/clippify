"""
viral_scorer.py — Viral Score Engine for ClipAI
================================================
Scores every moment in a video for viral potential using multi-signal analysis:

  1. Audio Energy    — RMS energy from audio (loud = exciting)
  2. Speech Rate     — words/second (fast = intense)
  3. Pause Score     — pause before sentence = emphasis
  4. Keyword Weight  — viral keywords (Arabic + English)
  5. Sentiment Peaks — emotional intensity from word patterns

Output: timeline dict {timestamp: score} where score is 0.0-1.0
"""

import os
import math
from typing import Dict, List, Optional, Tuple

# ─────────────────────────────────────────────────────────────────────────────
#  Viral Keyword Lists
# ─────────────────────────────────────────────────────────────────────────────

VIRAL_KEYWORDS_AR = {
    # Very high weight (0.9-1.0)
    "سر": 0.95, "اكبر خطأ": 0.95, "حقيقة": 0.90, "لا يعرفها": 0.90,
    "مليون": 0.88, "مليار": 0.88, "الحقيقة": 0.90, "سرّ": 0.95,
    "خطأ فادح": 0.90, "اكتشفت": 0.85, "كشف": 0.85,
    # High weight (0.7-0.85)
    "لماذا": 0.75, "ليه": 0.75, "الفرق": 0.72, "المشكلة": 0.72,
    "الحل": 0.70, "الطريقة": 0.70, "أهم": 0.72, "أكثر": 0.68,
    "خطير": 0.80, "مذهل": 0.80, "رهيب": 0.80, "لا تصدق": 0.85,
    "الجنون": 0.82, "بجد": 0.72, "فعلاً": 0.70,
    # Medium weight (0.5-0.7)
    "نصيحة": 0.65, "تعلمت": 0.60, "تجربتي": 0.60, "قصة": 0.58,
    "أنا": 0.50, "لو": 0.50, "هتعمل": 0.55, "تعمل": 0.52,
}

VIRAL_KEYWORDS_EN = {
    # Very high weight
    "secret": 0.95, "truth": 0.90, "revealed": 0.92, "exposed": 0.90,
    "million": 0.88, "billion": 0.88, "biggest mistake": 0.95,
    "you won't believe": 0.95, "shocking": 0.90, "insane": 0.88,
    "incredible": 0.85, "unbelievable": 0.88, "never told": 0.92,
    # High weight
    "why": 0.75, "difference": 0.72, "problem": 0.70, "solution": 0.70,
    "actually": 0.68, "honestly": 0.70, "real reason": 0.85,
    "dangerous": 0.80, "amazing": 0.78, "crazy": 0.80,
    # Medium weight
    "tip": 0.65, "trick": 0.65, "hack": 0.68, "learned": 0.60,
    "my story": 0.58, "experience": 0.55, "if you": 0.52,
}

# ─────────────────────────────────────────────────────────────────────────────
#  Signal 1: Audio Energy (RMS)
# ─────────────────────────────────────────────────────────────────────────────

def compute_audio_energy(audio_path: str, window_sec: float = 0.5) -> Dict[float, float]:
    """
    Compute normalized RMS energy at each time window.
    Returns {timestamp: energy_score} where score is 0.0-1.0
    """
    timeline = {}
    try:
        import librosa
        import numpy as np

        y, sr = librosa.load(audio_path, sr=None, mono=True)
        hop_length = int(sr * window_sec)
        rms = librosa.feature.rms(y=y, hop_length=hop_length)[0]

        # Normalize 0-1
        rms_max = float(np.max(rms)) if len(rms) > 0 else 1.0
        if rms_max < 1e-6:
            rms_max = 1.0

        for i, val in enumerate(rms):
            t = (i * hop_length) / sr
            timeline[round(t, 2)] = float(val) / rms_max

        print(f"  [ViralScore] Audio energy: {len(timeline)} windows")
        return timeline

    except ImportError:
        print("  [ViralScore] librosa not installed — using fallback energy")
        return _energy_fallback(audio_path, window_sec)
    except Exception as e:
        print(f"  [ViralScore] Audio energy error: {e}")
        return {}


def _energy_fallback(audio_path: str, window_sec: float) -> Dict[float, float]:
    """Fallback energy computation using pydub (no librosa needed)."""
    try:
        from pydub import AudioSegment
        import numpy as np

        audio = AudioSegment.from_file(audio_path)
        if audio.channels > 1:
            audio = audio.set_channels(1)

        samples = np.array(audio.get_array_of_samples()).astype(np.float32)
        sr = audio.frame_rate
        hop = int(sr * window_sec)
        timeline = {}

        rms_vals = []
        for i in range(0, len(samples) - hop, hop):
            chunk = samples[i:i + hop]
            rms = float(np.sqrt(np.mean(chunk ** 2))) if len(chunk) > 0 else 0.0
            rms_vals.append(rms)

        rms_max = max(rms_vals) if rms_vals else 1.0
        if rms_max < 1e-6:
            rms_max = 1.0

        for i, rms in enumerate(rms_vals):
            t = round((i * hop) / sr, 2)
            timeline[t] = rms / rms_max

        return timeline
    except Exception as e:
        print(f"  [ViralScore] Fallback energy error: {e}")
        return {}


# ─────────────────────────────────────────────────────────────────────────────
#  Signal 2: Speech Rate (words/second)
# ─────────────────────────────────────────────────────────────────────────────

def compute_speech_rate(words: list, window_sec: float = 3.0) -> Dict[float, float]:
    """
    Compute words-per-second in sliding windows.
    Fast speech = exciting. Returns normalized 0-1 score.
    """
    if not words:
        return {}

    total_dur = words[-1]["end"]
    if total_dur < 1.0:
        return {}

    timeline = {}
    rates = []

    t = 0.0
    step = window_sec / 2  # 50% overlap
    while t < total_dur:
        window_words = [w for w in words if t <= w["start"] < t + window_sec]
        rate = len(window_words) / window_sec
        timeline[round(t, 2)] = rate
        rates.append(rate)
        t += step

    # Normalize 0-1
    rate_max = max(rates) if rates else 1.0
    if rate_max < 0.1:
        rate_max = 1.0

    for k in timeline:
        timeline[k] = min(1.0, timeline[k] / rate_max)

    return timeline


# ─────────────────────────────────────────────────────────────────────────────
#  Signal 3: Pause Score (silence before = emphasis)
# ─────────────────────────────────────────────────────────────────────────────

def compute_pause_score(words: list) -> Dict[float, float]:
    """
    Words preceded by a pause get higher scores.
    Long pause (>0.5s) before a word = dramatic emphasis.
    """
    if len(words) < 2:
        return {}

    timeline = {}
    for i in range(1, len(words)):
        prev = words[i - 1]
        curr = words[i]
        pause = curr["start"] - prev["end"]

        # Score: longer pause = higher score (capped at 2s)
        score = min(1.0, pause / 2.0)
        timeline[round(curr["start"], 2)] = score

    return timeline


# ─────────────────────────────────────────────────────────────────────────────
#  Signal 4: Keyword Weight
# ─────────────────────────────────────────────────────────────────────────────

def compute_keyword_score(words: list, lang: str = "auto") -> Dict[float, float]:
    """
    Score each word moment based on viral keyword presence.
    Checks both Arabic and English keyword lists.
    """
    timeline = {}

    # Auto-detect language from first few words
    if lang == "auto":
        sample = " ".join(w["text"] for w in words[:20])
        ar_count = sum(1 for c in sample if "\u0600" <= c <= "\u06ff")
        lang = "ar" if ar_count > len(sample) * 0.3 else "en"

    keywords = VIRAL_KEYWORDS_AR if lang == "ar" else VIRAL_KEYWORDS_EN

    # Build text window for multi-word phrases
    for i, word in enumerate(words):
        best_score = 0.0
        clean = word["text"].lower().strip(".,!?;:\"'()")

        # Check single word
        for kw, weight in keywords.items():
            if clean == kw or kw in clean:
                best_score = max(best_score, weight)

        # Check 2-word phrase
        if i + 1 < len(words):
            phrase2 = f"{clean} {words[i+1]['text'].lower().strip('.,!?;:')}"
            for kw, weight in keywords.items():
                if kw in phrase2:
                    best_score = max(best_score, weight)

        # Check 3-word phrase
        if i + 2 < len(words):
            phrase3 = f"{clean} {words[i+1]['text'].lower()} {words[i+2]['text'].lower()}"
            for kw, weight in keywords.items():
                if kw in phrase3:
                    best_score = max(best_score, weight)

        if best_score > 0:
            timeline[round(word["start"], 2)] = best_score

    return timeline


# ─────────────────────────────────────────────────────────────────────────────
#  Signal 5: Emotional Intensity (pattern-based)
# ─────────────────────────────────────────────────────────────────────────────

EXCLAMATION_PATTERNS = {"!", "!!", "!?", "؟!", "!؟"}
QUESTION_PATTERNS    = {"?", "؟", "!!?"}
CAPS_THRESHOLD       = 0.7  # >70% uppercase = shouting

def compute_sentiment_score(words: list) -> Dict[float, float]:
    """
    Detect emotional intensity from punctuation and capitalization patterns.
    """
    timeline = {}
    for word in words:
        text = word["text"]
        score = 0.0

        # Exclamation = high energy
        if any(p in text for p in EXCLAMATION_PATTERNS):
            score += 0.6

        # Question = curiosity hook
        if any(p in text for p in QUESTION_PATTERNS):
            score += 0.4

        # ALL CAPS = shouting/emphasis
        alpha_chars = [c for c in text if c.isalpha()]
        if alpha_chars and len(alpha_chars) > 1:
            caps_ratio = sum(1 for c in alpha_chars if c.isupper()) / len(alpha_chars)
            if caps_ratio >= CAPS_THRESHOLD:
                score += 0.3

        # Repeated characters ("Amazing!!!" vs "Amazing")
        if len(text) > 3:
            for char in "!؟.":
                if text.count(char) >= 3:
                    score += 0.2
                    break

        if score > 0:
            timeline[round(word["start"], 2)] = min(1.0, score)

    return timeline


# ─────────────────────────────────────────────────────────────────────────────
#  Combined Viral Score
# ─────────────────────────────────────────────────────────────────────────────

# Signal weights (must sum to 1.0)
WEIGHTS = {
    "energy":    0.30,  # Audio loudness
    "speech":    0.15,  # Speech rate
    "pause":     0.20,  # Pauses = drama
    "keyword":   0.25,  # Viral keywords
    "sentiment": 0.10,  # Emotional intensity
}


def _interpolate_timeline(timeline: Dict[float, float],
                           target_times: list,
                           default: float = 0.0) -> Dict[float, float]:
    """Map a sparse timeline to target timestamps using nearest-neighbor lookup."""
    if not timeline:
        return {t: default for t in target_times}

    import bisect
    sorted_keys = sorted(timeline.keys())
    result = {}
    for t in target_times:
        idx = bisect.bisect_left(sorted_keys, t)
        if idx == 0:
            nearest = sorted_keys[0]
        elif idx == len(sorted_keys):
            nearest = sorted_keys[-1]
        else:
            before = sorted_keys[idx - 1]
            after = sorted_keys[idx]
            nearest = after if (after - t) < (t - before) else before

        if abs(nearest - t) <= 2.0:  # Within 2 seconds
            result[t] = timeline[nearest]
        else:
            result[t] = default
    return result


def get_viral_timeline(
    video_path: str,
    words: list,
    audio_path: Optional[str] = None,
    window_sec: float = 0.5,
) -> Dict[float, float]:
    """
    Compute a combined viral score timeline.

    Args:
        video_path:  Path to video file
        words:       List of word dicts with {text, start, end}
        audio_path:  Optional separate audio file (if None, extracts from video)
        window_sec:  Time resolution for scoring

    Returns:
        Dict mapping timestamp -> viral_score (0.0-1.0)
    """
    print("  [ViralScore] Computing viral timeline...")

    if not words:
        return {}

    # Extract audio if needed
    _audio_path = audio_path
    _temp_audio = None
    if not _audio_path or not os.path.exists(_audio_path):
        try:
            import tempfile, subprocess, imageio_ffmpeg
            fd, _temp_audio = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
            subprocess.run(
                [ffmpeg, "-y", "-i", video_path,
                 "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
                 _temp_audio],
                capture_output=True, timeout=120
            )
            _audio_path = _temp_audio
        except Exception as e:
            print(f"  [ViralScore] Could not extract audio: {e}")

    # Build target timestamps from word timings
    target_times = sorted(set(round(w["start"], 1) for w in words))

    # Compute all signals
    print("  [ViralScore] -> Computing audio energy...")
    energy_tl = compute_audio_energy(_audio_path, window_sec) if _audio_path else {}

    print("  [ViralScore] -> Computing speech rate...")
    speech_tl = compute_speech_rate(words, window_sec=3.0)

    print("  [ViralScore] -> Computing pause scores...")
    pause_tl = compute_pause_score(words)

    print("  [ViralScore] -> Computing keyword scores...")
    kw_tl = compute_keyword_score(words)

    print("  [ViralScore] -> Computing sentiment scores...")
    sent_tl = compute_sentiment_score(words)

    # Interpolate all signals to target times
    energy_map  = _interpolate_timeline(energy_tl,  target_times)
    speech_map  = _interpolate_timeline(speech_tl,  target_times)
    pause_map   = _interpolate_timeline(pause_tl,   target_times)
    kw_map      = _interpolate_timeline(kw_tl,      target_times)
    sent_map    = _interpolate_timeline(sent_tl,    target_times)

    # Combine with weights
    combined = {}
    for t in target_times:
        score = (
            WEIGHTS["energy"]    * energy_map.get(t, 0.0) +
            WEIGHTS["speech"]    * speech_map.get(t, 0.0) +
            WEIGHTS["pause"]     * pause_map.get(t, 0.0) +
            WEIGHTS["keyword"]   * kw_map.get(t, 0.0) +
            WEIGHTS["sentiment"] * sent_map.get(t, 0.0)
        )
        combined[t] = round(min(1.0, score), 3)

    # Cleanup temp audio
    if _temp_audio and os.path.exists(_temp_audio):
        try:
            os.remove(_temp_audio)
        except Exception:
            pass

    print(f"  [ViralScore] Done! {len(combined)} timestamps scored.")
    return combined


# ─────────────────────────────────────────────────────────────────────────────
#  Helper: Get best N moments from timeline
# ─────────────────────────────────────────────────────────────────────────────

def get_top_moments(
    timeline: Dict[float, float],
    n: int = 5,
    min_gap_sec: float = 10.0,
) -> List[Tuple[float, float]]:
    """
    Get the top N highest-scoring moments, ensuring min_gap_sec between them.
    Returns list of (timestamp, score) sorted by score descending.
    """
    if not timeline:
        return []

    sorted_moments = sorted(timeline.items(), key=lambda x: x[1], reverse=True)
    selected = []

    for t, score in sorted_moments:
        # Check min gap from already-selected moments
        if all(abs(t - sel_t) >= min_gap_sec for sel_t, _ in selected):
            selected.append((t, score))
        if len(selected) >= n:
            break

    return selected


def get_segment_score(
    timeline: Dict[float, float],
    start_sec: float,
    end_sec: float,
) -> float:
    """Compute average viral score for a given time segment."""
    if not timeline:
        return 0.0
    segment_scores = [
        score for t, score in timeline.items()
        if start_sec <= t < end_sec
    ]
    return sum(segment_scores) / len(segment_scores) if segment_scores else 0.0


def format_viral_summary(timeline: Dict[float, float], top_n: int = 5) -> str:
    """Return a formatted string summary of top viral moments."""
    if not timeline:
        return "No viral data available."

    top = get_top_moments(timeline, n=top_n)
    lines = ["Top Viral Moments:"]
    for i, (t, score) in enumerate(sorted(top, key=lambda x: x[0])):
        filled = int(score * 10)
        bar = "#" * filled + "-" * (10 - filled)
        lines.append(f"  [{i+1}] {t:.1f}s  |{bar}|  {score:.2f}")
    return "\n".join(lines)

