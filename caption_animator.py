# -*- coding: utf-8 -*-
"""
caption_animator.py — Advanced Word-by-Word Caption Animation for Clippify
=========================================================================
5 Professional Animation Modes:
  1. karaoke    — Word-by-word color highlight (TikTok standard)
  2. word_pop   — Each active word scales UP with bounce
  3. typewriter — Letters appear one by one (no, word by word appear)
  4. dual_color — Two-tone: inactive=grey, active=white+glow
  5. cinematic  — Fade in/slide for premium content
"""

import os

# -----------------------------------------------------------------------------
#  ASS Time Formatter
# -----------------------------------------------------------------------------

def _t(seconds: float) -> str:
    """Format seconds to ASS h:mm:ss.cc format."""
    s = max(0.0, seconds)
    h = int(s // 3600)
    m = int((s % 3600) // 60)
    sec = int(s % 60)
    cs = int((s - int(s)) * 100)
    return f"{h}:{m:02d}:{sec:02d}.{cs:02d}"


# -----------------------------------------------------------------------------
#  Color helpers (ASS uses BGR hex &HBBGGRR&)
# -----------------------------------------------------------------------------

def _hex(r, g, b, a=0):
    return f"&H{a:02X}{b:02X}{g:02X}{r:02X}"

# Presets
WHITE       = _hex(255, 255, 255)
YELLOW      = _hex(255, 230, 0)
CYAN        = _hex(0, 230, 255)
HOT_PINK    = _hex(255, 30, 150)
ORANGE      = _hex(255, 140, 0)
RED         = _hex(255, 0, 0)
GREY        = _hex(180, 180, 180)
DARK_GREY   = _hex(100, 100, 100)
BLACK       = _hex(0, 0, 0)
TRANSPARENT = "&H00000000"


# -----------------------------------------------------------------------------
#  Content-type -> style mapping
# -----------------------------------------------------------------------------

CONTENT_TYPE_STYLE = {
    "podcast":     "dual_color",
    "awareness":   "cinematic",
    "comedy":      "word_pop",
    "interview":   "karaoke",
    "motivation":  "word_pop",
    "educational": "karaoke",
}

CONTENT_TYPE_COLOR = {
    "podcast":     (YELLOW,   WHITE),  # Restored the beautiful signature yellow highlight!
    "awareness":   (YELLOW,   WHITE),
    "comedy":      (YELLOW,   HOT_PINK),
    "interview":   (WHITE,    YELLOW),
    "motivation":  (YELLOW,   WHITE),  # Restored yellow highlight!
    "educational": (YELLOW,   WHITE),  # Restored yellow highlight!
}


# -----------------------------------------------------------------------------
#  Chunk builder — groups words into natural display units
# -----------------------------------------------------------------------------

def _build_chunks(words: list, max_chunk_words: int = 3,
                  max_gap_sec: float = 0.6) -> list:
    """
    Group words into display chunks.
    Each chunk is a list of word dicts.
    Rules: max N words per chunk, or break on long pause.
    """
    if not words:
        return []
    chunks = []
    current = [words[0]]
    for w in words[1:]:
        gap = w["start"] - current[-1]["end"]
        if len(current) >= max_chunk_words or gap > max_gap_sec:
            chunks.append(current)
            current = [w]
        else:
            current.append(w)
    if current:
        chunks.append(current)
    return chunks


# -----------------------------------------------------------------------------
#  ASS Script Header
# -----------------------------------------------------------------------------

def _ass_header(styles_block: str, res_x: int = 1080, res_y: int = 1920) -> str:
    return f"""[Script Info]
ScriptType: v4.00+
PlayResX: {res_x}
PlayResY: {res_y}
WrapStyle: 1
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.601

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
{styles_block}

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""


def _dialogue(start, end, style, text, layer=0, mv=None, res_y=1920):
    if mv is None:
        mv = int(res_y * 0.156)
    return f"Dialogue: {layer},{_t(start)},{_t(end)},{style},,0,0,{mv},,{text}"


# -----------------------------------------------------------------------------
#  MODE 1: Karaoke — word-by-word highlight (standard TikTok)
# -----------------------------------------------------------------------------

def detect_emphasis_words(words: list) -> list:
    """
    Dynamically detect words that should be emphasized in subtitles:
    - Numbers & statistics (digits, percent, million, مليار, etc.)
    - Contrast words (but, however, لكن, بس, etc.)
    - Emotional/trigger words
    """
    emphasis = []
    NUMBER_WORDS = {
        "million", "billion", "trillion", "thousand", "percent", "%",
        "مليون", "مليار", "ألف", "بالمئة", "بالمية", "ملايين", "آلاف",
        "واحد", "اثنين", "ثلاثة", "أربعة", "خمسة", "ستة", "سبعة", "ثمانية", "تسعة", "عشرة"
    }
    CONTRAST_WORDS = {
        "but", "however", "although", "nevertheless", "yet", "instead",
        "لكن", "بس", "ولكن", "بل", "بينما", "بدل"
    }
    EMOTIONAL_TRIGGERS = {
        "صدمة", "مصدوم", "خطير", "كارثة", "سر", "أسرار", "حقيقة", "كذب",
        "خطأ", "غلط", "مشكلة", "حل", "فلوس", "موت", "حياة", "مجنون", "عبقري",
        "secret", "shocking", "dangerous", "truth", "lie", "mistake",
        "problem", "solution", "money", "insane", "genius", "crazy", "weird",
        "أكبر", "أصغر", "أفضل", "أسوأ", "لازم", "ممنوع", "خلاص", "تخيل", "صراحة",
        "biggest", "worst", "best", "must", "never", "imagine", "honestly"
    }
    
    for w in words:
        text = w["text"].strip(".,!?;:()\"'")
        text_lower = text.lower()
        
        # Check digits
        has_digits = any(char.isdigit() for char in text)
        
        if (has_digits or
            text_lower in NUMBER_WORDS or
            text_lower in CONTRAST_WORDS or
            text_lower in EMOTIONAL_TRIGGERS):
            emphasis.append(text_lower)
            
    return emphasis


def format_code_switching_word(word: str, font_name: str, current_color: str, target_color: str = CYAN) -> str:
    """
    Detect if a word is English within an Arabic sentence, wrap it with Unicode LTR control,
    and dynamically format it with an English font (Impact) and color to maintain visual hierarchy.
    """
    clean_w = word.strip(".,!?;:()\"'[]{}«»")
    has_english = any('a' <= c <= 'z' or 'A' <= c <= 'Z' for c in clean_w)
    
    if has_english:
        return f"\u200e{{\\fnImpact\\c{target_color}}}{word}{{\\fn{font_name}\\c{current_color}}}\u200e"
    return word


def _highlight_arabic_text(text: str, active_color: str, font_name: str = "Arial", emoji_map: dict = None) -> str:
    """
    In Arabic translation, dynamically highlight numbers, contrast, and trigger words
    by adding ASS color tags. Seamlessly formats mixed English words (Code-Switching)
    and places auto-emojis based on the emoji_map dictionary.
    """
    words = text.split()
    styled_words = []
    
    # Base emoji mapping rules as fallback
    emoji_rules = {
        "مستحيل": "😱", "تخيل": "💡", "والله": "🔥",
        "amazing": "🤯", "money": "💰", "love": "❤️",
        "شاهد": "👀", "مهم": "⚠️", "نجاح": "🏆", "قوة": "⚡", "سر": "🔑",
        "كوميدي": "😂", "مضحك": "🤣", "سيارة": "🚗", "شارع": "🛣️",
        "صدمة": "😱", "خطير": "🚨", "كارثة": "🌋", "حقيقة": "💯",
        "مجنون": "🤪", "فلوس": "💵", "موت": "💀", "حياة": "🌱",
        "عبقري": "🧠", "كذب": "🤥", "غلط": "❌", "صح": "✅"
    }
    
    # Merge custom emoji_map if provided
    if emoji_map:
        emoji_rules.update(emoji_map)

    for w in words:
        clean_w = w.strip(".,!?;:()\"'[]{}«»")
        clean_w_lower = clean_w.lower()
        
        # Check if the word is English (Code-Switching)
        has_english = any('a' <= c <= 'z' or 'A' <= c <= 'Z' for c in clean_w)
        if has_english:
            formatted = format_code_switching_word(w, font_name, WHITE, CYAN)
            # Add emoji if keyword exists in english
            for kw, emo in emoji_rules.items():
                if kw.lower() in clean_w_lower:
                    formatted += f" {emo}"
                    break
            styled_words.append(formatted)
            continue

        # Check digits or common trigger/contrast words
        is_emp = (any(c.isdigit() for c in clean_w) or
                  clean_w in {"مليون", "مليار", "ألف", "لكن", "بس", "سر", "صدمة", "خطير", "كارثة", "حقيقة", "مجنون", "تخيل", "أفضل", "أسوأ"})
        
        # Check emoji match
        matched_emoji = None
        for kw, emo in emoji_rules.items():
            if kw in clean_w:
                matched_emoji = emo
                break

        if is_emp or matched_emoji:
            formatted_w = f"{{\\c{active_color}}}{w}{{\\c{WHITE}}}"
            if matched_emoji:
                formatted_w += f" {matched_emoji}"
            styled_words.append(formatted_w)
        else:
            styled_words.append(w)
            
    return " ".join(styled_words)


def _mode_karaoke(chunks: list, font_name: str,
                  active_color: str, inactive_color: str,
                  hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                  res_x: int = 1080, res_y: int = 1920,
                  emphasis_words: list = None) -> str:
    styles = (
        f"Style: Main,{font_name},92,{WHITE},{active_color},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,6,2,2,10,10,{int(res_y*0.156)},1\n"
        f"Style: Hook,{font_name},108,{active_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,8,3,2,10,10,{int(res_y*0.156)},1"
    )
    events = []
    emphasis_set = set(w.lower().strip(".,!?;:") for w in (emphasis_words or []))
    emp_color = YELLOW if active_color != YELLOW else CYAN

    for chunk in chunks:
        words = chunk
        chunk_texts = [w["text"].upper() for w in words]

        for active_idx, active_word in enumerate(words):
            is_hook = False
            if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                is_hook = (hook_start_sec - 0.05 <= active_word["start"] <= hook_end_sec + 0.05)
            
            c_active = RED if is_hook else active_color
            style = "Hook" if is_hook else "Main"
            
            parts = []
            for i, text in enumerate(chunk_texts):
                w_dict = words[i]
                is_emp = w_dict["text"].lower().strip(".,!?;:") in emphasis_set
                
                if i == active_idx:
                    c_word_active = RED if is_hook else (HOT_PINK if is_emp else active_color)
                    scale_val = 125 if is_emp else 118
                    parts.append(
                        f"{{\\c{c_word_active}\\fscx{scale_val}\\fscy{scale_val}"
                        f"\\t(0,90,\\fscx100\\fscy100)}}"
                        f"{text}{{\\c{inactive_color}\\fscx100\\fscy100}}"
                    )
                else:
                    c_word_inactive = emp_color if is_emp else inactive_color
                    parts.append(f"{{\\c{c_word_inactive}}}{text}")
            line = " ".join(parts)
            alignment = "\\an5" if is_hook else "\\an2"
            events.append(_dialogue(
                active_word["start"], active_word["end"], style,
                f"{{{alignment}}}{line}", res_y=res_y
            ))
    return _ass_header(styles, res_x, res_y) + "\n".join(events)


# -----------------------------------------------------------------------------
#  MODE 2: Word Pop — big bounce scale on active word
# -----------------------------------------------------------------------------

def _mode_word_pop(chunks: list, font_name: str,
                   active_color: str, secondary_color: str,
                   hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                   res_x: int = 1080, res_y: int = 1920,
                   emphasis_words: list = None) -> str:
    styles = (
        f"Style: Main,{font_name},88,{WHITE},{active_color},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,5,2,2,10,10,{int(res_y*0.156)},1\n"
        f"Style: Hook,{font_name},104,{active_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,7,3,2,10,10,{int(res_y*0.156)},1"
    )
    events = []
    emphasis_set = set(w.lower().strip(".,!?;:") for w in (emphasis_words or []))
    emp_color = YELLOW if active_color != YELLOW else CYAN

    for chunk in chunks:
        words = chunk
        chunk_texts = [w["text"].upper() for w in words]

        for active_idx, active_word in enumerate(words):
            is_hook = False
            if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                is_hook = (hook_start_sec - 0.05 <= active_word["start"] <= hook_end_sec + 0.05)
            
            c_active = RED if is_hook else active_color
            style = "Hook" if is_hook else "Main"

            parts = []
            for i, text in enumerate(chunk_texts):
                w_dict = words[i]
                is_emp = w_dict["text"].lower().strip(".,!?;:") in emphasis_set
                
                if i == active_idx:
                    c_word_active = RED if is_hook else (HOT_PINK if is_emp else active_color)
                    scale_val = 165 if is_emp else 155
                    parts.append(
                        f"{{\\c{c_word_active}\\fscx{scale_val}\\fscy{scale_val}"
                        f"\\t(0,120,\\fscx100\\fscy100\\blur0)}}"
                        f"{text}{{\\fscx100\\fscy100\\c{WHITE}}}"
                    )
                else:
                    c_word_inactive = emp_color if is_emp else GREY
                    scale_val = 95 if is_emp else 90
                    parts.append(f"{{\\c{c_word_inactive}\\fscx{scale_val}\\fscy{scale_val}}}{text}{{\\fscx100\\fscy100}}")
            line = " ".join(parts)
            alignment = "\\an5" if is_hook else "\\an2"
            events.append(_dialogue(
                active_word["start"], active_word["end"], style,
                f"{{{alignment}}}{line}", res_y=res_y
            ))
    return _ass_header(styles, res_x, res_y) + "\n".join(events)


# -----------------------------------------------------------------------------
#  MODE 3: Dual Color — grey inactive, white+glow active (minimalist pro)
# -----------------------------------------------------------------------------

def _mode_dual_color(chunks: list, font_name: str,
                     active_color: str, glow_color: str,
                     hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                     res_x: int = 1080, res_y: int = 1920,
                     emphasis_words: list = None) -> str:
    styles = (
        f"Style: Main,{font_name},95,{active_color},{active_color},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,6,3,2,10,10,{int(res_y*0.156)},1\n"
        f"Style: Hook,{font_name},108,{active_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,8,3,2,10,10,{int(res_y*0.156)},1"
    )
    events = []
    emphasis_set = set(w.lower().strip(".,!?;:") for w in (emphasis_words or []))
    emp_color = YELLOW if active_color != YELLOW else CYAN

    for chunk in chunks:
        words = chunk
        chunk_texts = [w["text"].upper() for w in words]

        for active_idx, active_word in enumerate(words):
            is_hook = False
            if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                is_hook = (hook_start_sec - 0.05 <= active_word["start"] <= hook_end_sec + 0.05)
            
            style = "Hook" if is_hook else "Main"

            parts = []
            for i, text in enumerate(chunk_texts):
                w_dict = words[i]
                is_emp = w_dict["text"].lower().strip(".,!?;:") in emphasis_set
                
                if i == active_idx:
                    c_word_active = RED if is_hook else (HOT_PINK if is_emp else active_color)
                    scale_val = 120 if is_emp else 112
                    parts.append(
                        f"{{\\c{c_word_active}\\3c{BLACK}\\blur0"
                        f"\\fscx{scale_val}\\fscy{scale_val}\\t(0,80,\\fscx100\\fscy100)}}"
                        f"{text}{{\\c{active_color}\\3c{BLACK}\\blur0\\fscx100\\fscy100}}"
                    )
                else:
                    c_word_inactive = emp_color if is_emp else active_color
                    parts.append(f"{{\\c{c_word_inactive}}}{text}")
            line = " ".join(parts)
            alignment = "\\an5" if is_hook else "\\an2"
            events.append(_dialogue(
                active_word["start"], active_word["end"], style,
                f"{{{alignment}}}{line}", res_y=res_y
            ))
    return _ass_header(styles, res_x, res_y) + "\n".join(events)


# -----------------------------------------------------------------------------
#  MODE 4: Cinematic — full phrase fade in, elegant (awareness/drama)
# -----------------------------------------------------------------------------

def _mode_cinematic(chunks: list, font_name: str,
                    primary_color: str, secondary_color: str,
                    hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                    res_x: int = 1080, res_y: int = 1920) -> str:
    styles = (
        f"Style: Main,{font_name},84,{WHITE},{primary_color},{BLACK},&H80000000,"
        f"0,0,0,0,100,100,2,0,1,4,0,2,10,10,{int(res_y*0.166)},1\n"
        f"Style: Hook,{font_name},100,{primary_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,2,0,1,6,2,2,10,10,{int(res_y*0.166)},1"
    )
    events = []
    for chunk in chunks:
        words = chunk
        phrase = " ".join(w["text"].upper() for w in words)
        chunk_start = words[0]["start"]
        chunk_end = words[-1]["end"]
        duration_ms = max(50, int((chunk_end - chunk_start) * 1000))
        fade_in = min(150, duration_ms // 4)
        fade_out = min(100, duration_ms // 5)

        is_hook = False
        if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
            is_hook = (hook_start_sec - 0.05 <= chunk_start <= hook_end_sec + 0.05)
        style = "Hook" if is_hook else "Main"

        alignment = "\\an5" if is_hook else "\\an2"
        text = (
            f"{{{alignment}\\fad({fade_in},{fade_out})"
            f"\\t(0,{fade_in},\\fscx100\\fscy100)}}"
            f"{{\\fscx96\\fscy96}}{phrase}"
        )
        events.append(_dialogue(chunk_start, chunk_end, style, text, res_y=res_y))

    return _ass_header(styles, res_x, res_y) + "\n".join(events)


# -----------------------------------------------------------------------------
#  MODE 5: Flash — flash highlight on emphasis words, rest plain
# -----------------------------------------------------------------------------

def _mode_flash(chunks: list, font_name: str,
                flash_color: str, normal_color: str,
                emphasis_words: list = None,
                hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                res_x: int = 1080, res_y: int = 1920) -> str:
    emphasis_set = set(w.lower().strip(".,!?;:") for w in (emphasis_words or []))

    styles = (
        f"Style: Main,{font_name},92,{WHITE},{flash_color},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,6,2,2,10,10,{int(res_y*0.156)},1\n"
        f"Style: Hook,{font_name},108,{flash_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,8,3,2,10,10,{int(res_y*0.156)},1"
    )
    events = []
    for chunk in chunks:
        words = chunk
        chunk_texts = [w["text"].upper() for w in words]

        for active_idx, active_word in enumerate(words):
            parts = []
            for i, (w_dict, text) in enumerate(zip(words, chunk_texts)):
                is_emphasis = w_dict["text"].lower().strip(".,!?;:") in emphasis_set
                if i == active_idx:
                    if is_emphasis:
                        parts.append(
                            f"{{\\c{flash_color}\\fscx135\\fscy135"
                            f"\\t(0,100,\\fscx100\\fscy100\\blur0)}}"
                            f"{text}{{\\c{WHITE}\\fscx100\\fscy100}}"
                        )
                    else:
                        parts.append(
                            f"{{\\c{normal_color}\\fscx115\\fscy115"
                            f"\\t(0,80,\\fscx100\\fscy100)}}"
                            f"{text}{{\\c{WHITE}\\fscx100\\fscy100}}"
                        )
                else:
                    parts.append(f"{{\\c{WHITE}}}{text}")
            line = " ".join(parts)
            is_hook = False
            if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
                is_hook = (hook_start_sec - 0.05 <= active_word["start"] <= hook_end_sec + 0.05)
            style = "Hook" if is_hook else "Main"
            alignment = "\\an5" if is_hook else "\\an2"
            events.append(_dialogue(
                active_word["start"], active_word["end"], style,
                f"{{{alignment}}}{line}", res_y=res_y
            ))
    return _ass_header(styles, res_x, res_y) + "\n".join(events)


# -----------------------------------------------------------------------------
#  Public API
# -----------------------------------------------------------------------------

AVAILABLE_MODES = ["karaoke", "word_pop", "dual_color", "cinematic", "flash"]


def generate_animated_ass(
    words: list,
    output_path: str,
    mode: str = "karaoke",
    font_name: str = "Impact",
    content_type: str = "podcast",
    emphasis_words: list = None,
    translate_to_arabic: bool = False,
    hook_start_sec: float = 0.0,
    hook_end_sec: float = 0.0,
    res_x: int = 1080,
    res_y: int = 1920,
    emoji_map: dict = None,
) -> str:
    """
    Generate an animated ASS subtitle file.
    """
    if not words:
        empty = _ass_header(f"Style: Main,{font_name},92,{WHITE},{CYAN},{BLACK},&H80000000,-1,0,0,0,100,100,0,0,1,6,2,2,10,10,{int(res_y*0.156)},1", res_x, res_y)
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(empty)
        return output_path

    # Dynamic emphasis word extraction
    detected_emp = detect_emphasis_words(words)
    if not emphasis_words:
        emphasis_words = []
    emphasis_words = list(set([w.lower().strip(".,!?;:") for w in emphasis_words] + detected_emp))

    # Handle Arabic translation
    if translate_to_arabic:
        return _generate_arabic_ass(words, output_path, mode, font_name, content_type, hook_start_sec, hook_end_sec, res_x, res_y, emphasis_words, emoji_map)

    # Auto mode selection
    if mode == "auto":
        mode = CONTENT_TYPE_STYLE.get(content_type, "karaoke")

    # Get colors for this content type
    active_color, secondary_color = CONTENT_TYPE_COLOR.get(
        content_type, (CYAN, WHITE)
    )

    # Build word chunks
    chunks = _build_chunks(words, max_chunk_words=3, max_gap_sec=0.5)

    # Generate ASS based on mode
    if mode == "karaoke":
        content = _mode_karaoke(chunks, font_name, active_color, secondary_color, hook_start_sec, hook_end_sec, res_x, res_y, emphasis_words)
    elif mode == "word_pop":
        content = _mode_word_pop(chunks, font_name, active_color, secondary_color, hook_start_sec, hook_end_sec, res_x, res_y, emphasis_words)
    elif mode == "dual_color":
        content = _mode_dual_color(chunks, font_name, active_color, secondary_color, hook_start_sec, hook_end_sec, res_x, res_y, emphasis_words)
    elif mode == "cinematic":
        content = _mode_cinematic(chunks, font_name, active_color, secondary_color, hook_start_sec, hook_end_sec, res_x, res_y)
    elif mode == "flash":
        content = _mode_flash(chunks, font_name, active_color, secondary_color, emphasis_words, hook_start_sec, hook_end_sec, res_x, res_y)
    else:
        content = _mode_karaoke(chunks, font_name, active_color, secondary_color, hook_start_sec, hook_end_sec, res_x, res_y, emphasis_words)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    return output_path


def _generate_arabic_ass(words: list, output_path: str, mode: str,
                          font_name: str, content_type: str,
                          hook_start_sec: float = 0.0, hook_end_sec: float = 0.0,
                          res_x: int = 1080, res_y: int = 1920,
                          emphasis_words: list = None,
                          emoji_map: dict = None) -> str:
    """Generate Arabic-translated beautifully animated ASS."""
    try:
        from ai_engine import translate_chunks_to_arabic
    except ImportError:
        return generate_animated_ass(words, output_path, mode, font_name,
                                     content_type, translate_to_arabic=False,
                                     hook_start_sec=hook_start_sec, hook_end_sec=hook_end_sec,
                                     res_x=res_x, res_y=res_y, emphasis_words=emphasis_words,
                                     emoji_map=emoji_map)

    active_color, secondary_color = CONTENT_TYPE_COLOR.get(content_type, (CYAN, WHITE))

    chunks = _build_chunks(words, max_chunk_words=4)  # Arabic: slightly more words per chunk
    chunk_texts = [" ".join(w["text"] for w in c) for c in chunks]
    translated = translate_chunks_to_arabic(chunk_texts)

    # Premium TikTok style: white text, outline 6, shadow 3, alignment 2 (centered bottom)
    styles = (
        f"Style: Main,{font_name},95,{WHITE},{active_color},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,6,3,2,10,10,{int(res_y*0.156)},1\n"
        f"Style: Hook,{font_name},110,{active_color},{WHITE},{BLACK},&H80000000,"
        f"-1,0,0,0,100,100,0,0,1,8,4,2,10,10,{int(res_y*0.156)},1"
    )
    events = []
    for ci, chunk in enumerate(chunks):
        arabic_text = translated[ci] if ci < len(translated) else " ".join(w["text"] for w in chunk)
        chunk_start = chunk[0]["start"]
        chunk_end = chunk[-1]["end"]
        
        is_hook = False
        if hook_start_sec is not None and hook_end_sec is not None and hook_end_sec > hook_start_sec:
            is_hook = (hook_start_sec - 0.05 <= chunk_start <= hook_end_sec + 0.05)
        style = "Hook" if is_hook else "Main"
        
        # Color transition and scale pop
        c = RED if is_hook else active_color
        alignment = "\\an5" if is_hook else "\\an2"
        
        # Dynamic coloring inside the Arabic phrase
        styled_arabic = _highlight_arabic_text(arabic_text, active_color, font_name, emoji_map)
        text = f"{{{alignment}\\fscx115\\fscy115\\t(0,100,\\fscx100\\fscy100)\\c{c}}}{styled_arabic}"
        events.append(_dialogue(chunk_start, chunk_end, style, text, res_y=res_y))

    content = _ass_header(styles, res_x, res_y) + "\n".join(events)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)
    return output_path


def get_mode_for_content_type(content_type: str) -> str:
    """Get the recommended animation mode for a content type."""
    return CONTENT_TYPE_STYLE.get(content_type, "karaoke")


def get_available_modes() -> list:
    """Return list of all available animation modes."""
    return AVAILABLE_MODES.copy()

