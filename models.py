from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class ClipSpec:
    index: int
    start_sec: float
    end_sec: float
    hook: str = ""
    reason: str = ""
    caption_theme: str = "TikTok"
    zoom_style: str = "gentle"
    transition: str = "crossfade"
    emphasis_words: List[str] = field(default_factory=list)
    music_volume: float = 0.06
    color_grade: str = "none"
    sfx_queries: List[str] = field(default_factory=list)
    # New: per-clip hook sentence (used if this is the first clip)
    hook_sentence: str = ""
    hook_sentence_start: float = 0.0
    hook_sentence_end: float = 3.0
    planned_brolls: List[dict] = field(default_factory=list)
    hook_options: List[str] = field(default_factory=list)
    # Phase 8: Dynamic Pacing & Retiming
    slow_motion_start: float = 0.0
    slow_motion_end: float = 0.0
    slow_motion_speed: float = 1.0
    # Phase 11: Semantic Multi-Clip Narrative (The 3-Act Structure)
    narrative_acts: List[dict] = field(default_factory=list)



@dataclass
class VideoAnalysis:
    duration: float
    total_words: int
    has_audio: bool
    key_moments: List[dict] = field(default_factory=list)


@dataclass
class EditingPlan:
    video_path: str
    n_clips: int
    duration_sec: float
    analysis: Optional[VideoAnalysis] = None
    clips: List[ClipSpec] = field(default_factory=list)
    plan_review_callback: Optional[object] = None
    compile_clips: bool = True
    global_music: bool = True
    global_vocal_mastering: bool = True
    global_ending_cta: str = ""
    music_path: str = ""

    # ── NEW: Content Type System ─────────────────────────────────────
    # One of: "podcast", "awareness", "comedy", "interview", "motivation", "educational"
    content_type: str = "podcast"

    # ── NEW: Custom Instructions ──────────────────────────────────────
    # Free-text instructions the user typed (Arabic or English)
    # e.g. "حط في المنتصف اشتركوا في القناة"
    custom_instructions: str = ""

    # ── NEW: Hook Mode ────────────────────────────────────────────────
    # If True, the system will extract a 3-second dramatic hook teaser
    # before the main clip, using the content-type-specific strategy
    hook_mode: bool = True

    # ── NEW: Outro ────────────────────────────────────────────────────
    # Enable cinematic outro (circle on face + fade to black + CTA)
    outro_enabled: bool = True

    # ── NEW: Framing & Crop Strategy ──────────────────────────────────
    # One of: "split_screen", "speaker_tracking", "no_crop"
    framing_strategy: str = "speaker_tracking"

    # ── NEW: Custom Font name ─────────────────────────────────────────
    font_name: str = "Impact"

    # ── NEW: Export Quality ───────────────────────────────────────────
    # One of: "Low", "Medium", "High"
    export_quality: str = "High"

    # ── NEW: Custom Logo / Watermark ──────────────────────────────────
    logo_path: str = ""

    # ── NEW: Auto Translate Subtitles to Arabic ───────────────────────
    translate_to_arabic: bool = False

    # ── NEW: Caption Animation Mode ───────────────────────────────────────
    # One of: "auto", "karaoke", "word_pop", "dual_color", "cinematic", "flash", "classic"
    # "auto" = picks best mode based on content_type
    caption_animation_mode: str = "auto"

    # ── Phase 7 & 8: New AI Features ───────────────────────────────────────
    gemma_multimodal: bool = False
    auto_broll: bool = False
    pexels_api_key: str = ""
    pixabay_api_key: str = ""
    api_key: str = ""
    sfx_mode: str = "normal"  # One of: "none", "hook_only", "sparse", "normal"
    use_scene_captioning: bool = False
    use_local_captioning: bool = True
    export_mode: str = "ffmpeg"  # One of: "ffmpeg", "davinci"

    # ── Phase 9: Manual Mode ───────────────────────────────────────────────
    manual_clip_bounds: tuple = None  # (start_sec, end_sec) if manually trimmed



