"""
content_types.py — Content Type System for ClipAI
Each content type defines its full editing profile:
  - hook_strategy: how to find the best hook sentence
  - sfx_library: categorized sound effects
  - color_grade: visual style
  - caption_theme: subtitle style
  - music_mood: background music type
  - outro_style: ending animation
"""

from dataclasses import dataclass, field
from typing import List, Optional


# ─────────────────────────────────────────────────────────────────────────────
#  SFX Libraries — per content type
# ─────────────────────────────────────────────────────────────────────────────

# Hook transition sounds (played at the 3-second slam)
HOOK_SFX = {
    "podcast":     ["soft swoosh", "deep bass impact", "soft thud"],
    "awareness":   ["epic orchestra hit", "deep impact dramatic", "cinematic tension hit"],
    "comedy":      ["vine boom", "boing comedy", "cartoon slide whistle"],
    "interview":   ["cinematic whoosh", "news sting", "soft swoosh"],
    "motivation":  ["epic rise impact", "crowd cheer stadium", "power hit impact"],
    "educational": ["soft notification ping", "magical sparkle", "level up sound"],
}

# Transition sounds (between speaker cuts)
TRANSITION_SFX = {
    "podcast":     ["soft swoosh", "soft whoosh"],
    "awareness":   ["cinematic swoosh", "tension rise", "dramatic whoosh"],
    "comedy":      ["slide whistle down", "boing spring", "funny whoosh"],
    "interview":   ["news swoosh", "camera shutter", "clean whoosh"],
    "motivation":  ["power swoosh", "epic whoosh", "fast swoosh"],
    "educational": ["page turn", "soft whoosh", "notification sound"],
}

# Emphasis sounds (on key words)
# NOTE: For podcast/awareness/interview/motivation/educational, these are only
# used as fallback labels — sfx_synth.py generates the actual sounds locally.
# Only comedy uses myinstants.com.
EMPHASIS_SFX = {
    "podcast":     ["low thud", "soft chime"],
    "awareness":   ["cinematic boom", "dramatic sting", "bass thud"],
    "comedy":      ["vine boom", "bruh sound effect", "anime wow", "fart sound", "crickets"],
    "interview":   ["news sting", "subtle boom", "deep thud"],
    "motivation":  ["epic boom", "power rise", "cinematic hit"],
    "educational": ["soft chime", "bell ding", "soft bell"],
}

# Trending generic SFX — only for comedy content
# Professional content uses sfx_synth.py for local synthesis
TRENDING_SFX = [
    "vine boom",
    "whoosh transition",
    "rizz sound effect",
    "sigma bass",
    "tiktok dramatic sting",
    "anime wow",
    "bruh",
    "npc sound",
    "ohio rizz",
    "skibidi",
]

# ─────────────────────────────────────────────────────────────────────────────
#  Color Grade Profiles — matched to content type
# ─────────────────────────────────────────────────────────────────────────────

COLOR_GRADE_PROFILE = {
    "podcast":     "none",          # natural, no heavy grading
    "awareness":   "cinematic_cool", # dark, dramatic, high contrast
    "comedy":      "vibrant",       # saturated, bright, fun
    "interview":   "cinematic_warm", # warm, professional
    "motivation":  "cinematic_warm", # golden, epic
    "educational": "none",          # clean, natural
}

# ─────────────────────────────────────────────────────────────────────────────
#  Caption / Subtitle Theme — matched to content type
# ─────────────────────────────────────────────────────────────────────────────

CAPTION_THEME_PROFILE = {
    "podcast":     "Minimalist Clean",
    "awareness":   "Cyberpunk Neon",
    "comedy":      "TikTok Yellow",
    "interview":   "Minimalist Clean",
    "motivation":  "TikTok Yellow",
    "educational": "Minimalist Clean",
}

# ─────────────────────────────────────────────────────────────────────────────
#  Hook Strategy — what kind of sentence to look for as the hook
# ─────────────────────────────────────────────────────────────────────────────

HOOK_STRATEGY = {
    "podcast": {
        "description": "أقوى جملة هادئة تشد المشاهد — سؤال مثير أو كشف مفاجئ",
        "llm_prompt_hint": (
            "Find the single most compelling sentence from this podcast transcript "
            "that would make someone stop scrolling. Prefer questions, shocking facts, "
            "or counterintuitive statements. Return only the sentence text."
        ),
    },
    "awareness": {
        "description": "أقوى جملة توعوية أو دينية أو تحذيرية تحرك المشاعر",
        "llm_prompt_hint": (
            "Find the single most emotionally impactful or spiritually moving sentence "
            "from this awareness/religious video transcript. "
            "Prefer sentences that trigger deep reflection or urgency. Return only the sentence."
        ),
    },
    "comedy": {
        "description": "أضحك جملة أو لحظة ذروة كوميدية",
        "llm_prompt_hint": (
            "Find the single funniest or most absurd sentence from this comedy transcript. "
            "Prefer punchlines, unexpected twists, or the peak comedic moment. Return only the sentence."
        ),
    },
    "interview": {
        "description": "أقوى إجابة أو اعتراف صادم من المقابلة",
        "llm_prompt_hint": (
            "Find the single most interesting, controversial, or revealing answer "
            "from this interview transcript. Prefer confessions, strong opinions, or surprising facts. "
            "Return only the sentence."
        ),
    },
    "motivation": {
        "description": "أقوى جملة تشحن وتحفز",
        "llm_prompt_hint": (
            "Find the single most powerful, energizing, motivational sentence from this speech transcript. "
            "Prefer calls to action, bold statements, or emotional peaks. Return only the sentence."
        ),
    },
    "educational": {
        "description": "أهم معلومة أو حقيقة مثيرة للتعلم",
        "llm_prompt_hint": (
            "Find the single most surprising or valuable piece of information from this educational "
            "transcript. Prefer 'Did you know' style facts or counterintuitive insights. Return only the sentence."
        ),
    },
}

# ─────────────────────────────────────────────────────────────────────────────
#  Outro Style — ending animation type
# ─────────────────────────────────────────────────────────────────────────────

OUTRO_STYLE = {
    "podcast":     "circle_fade",    # دائرة على الوجه + fade
    "awareness":   "black_fade",     # fade to black مع نص تأملي
    "comedy":      "freeze_zoom",    # freeze frame + zoom in comic
    "interview":   "circle_fade",    # دائرة على الوجه
    "motivation":  "epic_fade",      # fade مع نص شعاري
    "educational": "slide_out",      # slide out text
}

# ─────────────────────────────────────────────────────────────────────────────
#  Zoom Style — matched to content type
# ─────────────────────────────────────────────────────────────────────────────

ZOOM_STYLE_PROFILE = {
    "podcast":     "gentle",
    "awareness":   "slow_push",
    "comedy":      "punch",
    "interview":   "gentle",
    "motivation":  "dynamic",
    "educational": "gentle",
}

# ─────────────────────────────────────────────────────────────────────────────
#  Complete Content Type Profile — all settings in one dict
# ─────────────────────────────────────────────────────────────────────────────

ALL_TYPES = {
    "podcast": {
        "label": "📻 بودكاست",
        "description": "محادثة / برنامج حواري",
        "color": "#6366F1",   # indigo
        "hook_strategy": HOOK_STRATEGY["podcast"],
        "hook_sfx": HOOK_SFX["podcast"],
        "transition_sfx": TRANSITION_SFX["podcast"],
        "emphasis_sfx": EMPHASIS_SFX["podcast"],
        "color_grade": COLOR_GRADE_PROFILE["podcast"],
        "caption_theme": CAPTION_THEME_PROFILE["podcast"],
        "zoom_style": ZOOM_STYLE_PROFILE["podcast"],
        "outro_style": OUTRO_STYLE["podcast"],
        "default_n_clips": 5,
        "default_duration": 60,
    },
    "awareness": {
        "label": "🕌 توعية / ديني",
        "description": "محتوى توعوي أو ديني أو تأملي",
        "color": "#10B981",   # emerald
        "hook_strategy": HOOK_STRATEGY["awareness"],
        "hook_sfx": HOOK_SFX["awareness"],
        "transition_sfx": TRANSITION_SFX["awareness"],
        "emphasis_sfx": EMPHASIS_SFX["awareness"],
        "color_grade": COLOR_GRADE_PROFILE["awareness"],
        "caption_theme": CAPTION_THEME_PROFILE["awareness"],
        "zoom_style": ZOOM_STYLE_PROFILE["awareness"],
        "outro_style": OUTRO_STYLE["awareness"],
        "default_n_clips": 4,
        "default_duration": 50,
    },
    "comedy": {
        "label": "😂 كوميدي",
        "description": "محتوى مضحك أو ردود أفعال",
        "color": "#F59E0B",   # amber
        "hook_strategy": HOOK_STRATEGY["comedy"],
        "hook_sfx": HOOK_SFX["comedy"],
        "transition_sfx": TRANSITION_SFX["comedy"],
        "emphasis_sfx": EMPHASIS_SFX["comedy"],
        "color_grade": COLOR_GRADE_PROFILE["comedy"],
        "caption_theme": CAPTION_THEME_PROFILE["comedy"],
        "zoom_style": ZOOM_STYLE_PROFILE["comedy"],
        "outro_style": OUTRO_STYLE["comedy"],
        "default_n_clips": 6,
        "default_duration": 30,
    },
    "interview": {
        "label": "🎙️ مقابلة",
        "description": "مقابلة صحفية أو يوتيوب",
        "color": "#3B82F6",   # blue
        "hook_strategy": HOOK_STRATEGY["interview"],
        "hook_sfx": HOOK_SFX["interview"],
        "transition_sfx": TRANSITION_SFX["interview"],
        "emphasis_sfx": EMPHASIS_SFX["interview"],
        "color_grade": COLOR_GRADE_PROFILE["interview"],
        "caption_theme": CAPTION_THEME_PROFILE["interview"],
        "zoom_style": ZOOM_STYLE_PROFILE["interview"],
        "outro_style": OUTRO_STYLE["interview"],
        "default_n_clips": 5,
        "default_duration": 45,
    },
    "motivation": {
        "label": "⚡ تحفيز",
        "description": "خطاب تحفيزي أو TED Talk",
        "color": "#EF4444",   # red
        "hook_strategy": HOOK_STRATEGY["motivation"],
        "hook_sfx": HOOK_SFX["motivation"],
        "transition_sfx": TRANSITION_SFX["motivation"],
        "emphasis_sfx": EMPHASIS_SFX["motivation"],
        "color_grade": COLOR_GRADE_PROFILE["motivation"],
        "caption_theme": CAPTION_THEME_PROFILE["motivation"],
        "zoom_style": ZOOM_STYLE_PROFILE["motivation"],
        "outro_style": OUTRO_STYLE["motivation"],
        "default_n_clips": 4,
        "default_duration": 55,
    },
    "educational": {
        "label": "🎓 تعليمي",
        "description": "درس أو محاضرة أو شرح",
        "color": "#8B5CF6",   # violet
        "hook_strategy": HOOK_STRATEGY["educational"],
        "hook_sfx": HOOK_SFX["educational"],
        "transition_sfx": TRANSITION_SFX["educational"],
        "emphasis_sfx": EMPHASIS_SFX["educational"],
        "color_grade": COLOR_GRADE_PROFILE["educational"],
        "caption_theme": CAPTION_THEME_PROFILE["educational"],
        "zoom_style": ZOOM_STYLE_PROFILE["educational"],
        "outro_style": OUTRO_STYLE["educational"],
        "default_n_clips": 4,
        "default_duration": 50,
    },
    # ── New Podcast Sub-types ──────────────────────────────────────────
    "podcast_car": {
        "label": "🚗 بودكاست سيارة",
        "description": "بودكاست تم تصويره داخل سيارة — زووم خفيف، لقطات أوسع",
        "color": "#10B981",   # emerald
        "hook_strategy": HOOK_STRATEGY["podcast"],
        "hook_sfx": HOOK_SFX["podcast"],
        "transition_sfx": TRANSITION_SFX["podcast"],
        "emphasis_sfx": EMPHASIS_SFX["podcast"],
        "color_grade": "none",
        "caption_theme": "Minimalist Clean",
        "zoom_style": "gentle",
        "outro_style": "circle_fade",
        "default_n_clips": 4,
        "default_duration": 45,
    },
    "podcast_studio": {
        "label": "🎙️ بودكاست استوديو",
        "description": "استوديو احترافي متعدد الكاميرات — split screen ذكي",
        "color": "#6366F1",   # indigo
        "hook_strategy": HOOK_STRATEGY["podcast"],
        "hook_sfx": HOOK_SFX["podcast"],
        "transition_sfx": TRANSITION_SFX["podcast"],
        "emphasis_sfx": EMPHASIS_SFX["podcast"],
        "color_grade": "cinematic_warm",
        "caption_theme": "Minimalist Clean",
        "zoom_style": "gentle",
        "outro_style": "circle_fade",
        "default_n_clips": 5,
        "default_duration": 60,
    },
    "podcast_street": {
        "label": "🎤 مقابلات الشارع",
        "description": "مقابلات الشارع والجمهور — تتبع قوي ومونتاج ديناميكي",
        "color": "#F59E0B",   # amber
        "hook_strategy": HOOK_STRATEGY["interview"],
        "hook_sfx": HOOK_SFX["interview"],
        "transition_sfx": TRANSITION_SFX["interview"],
        "emphasis_sfx": EMPHASIS_SFX["interview"],
        "color_grade": "vibrant",
        "caption_theme": "TikTok Yellow",
        "zoom_style": "dynamic",
        "outro_style": "circle_fade",
        "default_n_clips": 5,
        "default_duration": 45,
    },
    "podcast_react": {
        "label": "🎭 بودكاست ردود فعل",
        "description": "ريأكشن وردود فعل — زووم مفاجئ وتأثيرات درامية",
        "color": "#EF4444",   # red
        "hook_strategy": HOOK_STRATEGY["comedy"],
        "hook_sfx": HOOK_SFX["comedy"],
        "transition_sfx": TRANSITION_SFX["comedy"],
        "emphasis_sfx": EMPHASIS_SFX["comedy"],
        "color_grade": "vibrant",
        "caption_theme": "TikTok Yellow",
        "zoom_style": "punch",
        "outro_style": "freeze_zoom",
        "default_n_clips": 6,
        "default_duration": 30,
    },
    "podcast_solo": {
        "label": "👤 بودكاست فردي (سولو)",
        "description": "شخص واحد يتحدث مباشرة للكاميرا — تتبع ثابت وتركيز بصري",
        "color": "#8B5CF6",   # violet
        "hook_strategy": HOOK_STRATEGY["motivation"],
        "hook_sfx": HOOK_SFX["motivation"],
        "transition_sfx": TRANSITION_SFX["motivation"],
        "emphasis_sfx": EMPHASIS_SFX["motivation"],
        "color_grade": "cinematic_cool",
        "caption_theme": "Minimalist Clean",
        "zoom_style": "slow_push",
        "outro_style": "epic_fade",
        "default_n_clips": 5,
        "default_duration": 50,
    },
    "podcast_roundtable": {
        "label": "👥 طاولة مستديرة",
        "description": "مناقشة بين 3 أشخاص أو أكثر — تخطيط شاشة متعدد ذكي",
        "color": "#3B82F6",   # blue
        "hook_strategy": HOOK_STRATEGY["podcast"],
        "hook_sfx": HOOK_SFX["podcast"],
        "transition_sfx": TRANSITION_SFX["podcast"],
        "emphasis_sfx": EMPHASIS_SFX["podcast"],
        "color_grade": "none",
        "caption_theme": "Minimalist Clean",
        "zoom_style": "gentle",
        "outro_style": "circle_fade",
        "default_n_clips": 4,
        "default_duration": 60,
    },
}


def get_type_profile(content_type: str) -> dict:
    """Get the full profile for a content type. Falls back to podcast."""
    return ALL_TYPES.get(content_type, ALL_TYPES["podcast"])


def get_hook_sfx(content_type: str) -> list:
    return HOOK_SFX.get(content_type, HOOK_SFX["podcast"])


def get_transition_sfx(content_type: str) -> list:
    return TRANSITION_SFX.get(content_type, TRANSITION_SFX["podcast"])


def get_emphasis_sfx(content_type: str) -> list:
    return EMPHASIS_SFX.get(content_type, EMPHASIS_SFX["podcast"])


def get_hook_prompt(content_type: str) -> str:
    profile = HOOK_STRATEGY.get(content_type, HOOK_STRATEGY["podcast"])
    return profile["llm_prompt_hint"]
