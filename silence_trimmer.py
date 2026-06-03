from typing import List, Dict, Any, Tuple

class SilenceTrimmingMode:
    WORD_GAP     = "word"      # gap > 0.15s between words
    SENTENCE_GAP = "sentence"  # gap > 0.4s between sentences
    PARAGRAPH    = "paragraph" # gap > 1.0s between paragraphs
    NATURAL      = "natural"   # 0.25s between words, 0.5s between sentences
    AGGRESSIVE   = "aggressive" # 0.1s gap — very punchy, chops almost all silence

def get_trimming_params(mode: str) -> Tuple[float, float]:
    """
    Returns (min_gap_to_trim, padding_sec) for a given mode.
    """
    if mode == SilenceTrimmingMode.AGGRESSIVE:
        return 0.1, 0.05
    elif mode == SilenceTrimmingMode.WORD_GAP:
        return 0.15, 0.07
    elif mode == SilenceTrimmingMode.NATURAL:
        return 0.25, 0.12
    elif mode == SilenceTrimmingMode.SENTENCE_GAP:
        return 0.4, 0.15
    elif mode == SilenceTrimmingMode.PARAGRAPH:
        return 1.0, 0.3
    else:
        # Default fallback: NATURAL
        return 0.25, 0.12

def get_recommended_mode(content_type: str, speech_rate: float = 140.0) -> str:
    """
    Recommends the best trimming mode based on the content type and speech rate.
    """
    c_lower = content_type.lower()
    if "comedy" in c_lower or "react" in c_lower:
        return SilenceTrimmingMode.AGGRESSIVE
    elif "motivation" in c_lower or "educational" in c_lower or speech_rate > 160:
        return SilenceTrimmingMode.WORD_GAP
    elif "awareness" in c_lower:
        return SilenceTrimmingMode.SENTENCE_GAP
    elif "podcast" in c_lower or "interview" in c_lower:
        return SilenceTrimmingMode.NATURAL
    return SilenceTrimmingMode.NATURAL

def compute_active_segments(
    words: List[Dict[str, Any]], 
    start_sec: float, 
    end_sec: float, 
    content_type: str = "podcast",
    trim_mode: str = "auto",
    speech_rate: float = 140.0
) -> List[Tuple[float, float]]:
    """
    Calculates the exact sub-segments of a video clip to keep, 
    removing silent periods based on the chosen trimming mode.
    """
    if not words:
        return [(start_sec, end_sec)]

    # 1. Determine the mode
    if trim_mode == "auto":
        mode = get_recommended_mode(content_type, speech_rate)
    else:
        mode = trim_mode

    min_gap, padding = get_trimming_params(mode)

    # Filter words inside the clip boundary
    clip_words = [w for w in words if w['end'] >= start_sec and w['start'] <= end_sec]
    if not clip_words:
        return [(start_sec, end_sec)]

    segments = []
    current_start = start_sec

    for idx, w in enumerate(clip_words):
        if idx + 1 < len(clip_words):
            next_w = clip_words[idx+1]
            gap = next_w['start'] - w['end']
            
            if gap > min_gap:
                # We close the current active segment
                # Keep some buffer (padding) after the word ends
                seg_end = min(end_sec, w['end'] + padding)
                if seg_end > current_start + 0.05:
                    segments.append((current_start, seg_end))
                
                # Start next active segment just before the next word starts
                current_start = max(start_sec, next_w['start'] - padding)

    # Append the last segment to the end of the clip
    if end_sec > current_start + 0.05:
        segments.append((current_start, end_sec))

    # Fallback to full segment if calculations resulted in empty lists
    if not segments:
        return [(start_sec, end_sec)]

    return segments
