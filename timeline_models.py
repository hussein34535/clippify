# timeline_models.py
# Pydantic models for the Clippify Pro NLE timeline state

from typing import List, Dict, Any, Optional
from pydantic import BaseModel, Field

class Vector2D(BaseModel):
    x: float = 0.0
    y: float = 0.0

class Keyframe(BaseModel):
    time: float
    property: str
    value: Any
    easing: str = "linear"  # "linear", "ease-in", "ease-out", "ease-in-out"

class TransformState(BaseModel):
    position: Vector2D = Field(default_factory=Vector2D)
    scale: Vector2D = Field(default_factory=lambda: Vector2D(x=100.0, y=100.0))
    rotation: float = 0.0
    keyframes: List[Keyframe] = Field(default_factory=list)

class ColorGradingState(BaseModel):
    brightness: float = 0.0  # -1.0 to 1.0 (offset)
    contrast: float = 1.0    # 0.0 to 5.0 (multiplier)
    saturation: float = 1.0  # 0.0 to 5.0 (multiplier)
    temperature: float = 6500.0  # kelvin (warmth)
    lut_path: str = ""

class FilterSpec(BaseModel):
    type: str  # "blur", "vignette", "mosaic", "chromakey", "noise"
    params: Dict[str, Any] = Field(default_factory=dict)

class AIFeatures(BaseModel):
    face_tracking: bool = False
    bg_removed: bool = False
    bg_remove_method: str = "none"  # "none", "chromakey", "sam", "rmbg"
    chromakey_color: str = "#00FF00"

class VideoClip(BaseModel):
    id: str
    source_path: str
    start_time_in_timeline: float
    end_time_in_timeline: float
    source_trim_start: float = 0.0
    source_trim_end: float
    source_duration: float = 0.0
    speed: float = 1.0
    volume: float = 1.0
    transform: TransformState = Field(default_factory=TransformState)
    color_grading: ColorGradingState = Field(default_factory=ColorGradingState)
    filters: List[FilterSpec] = Field(default_factory=list)
    ai_features: AIFeatures = Field(default_factory=AIFeatures)

class AudioClip(BaseModel):
    id: str
    source_path: str
    start_time_in_timeline: float
    end_time_in_timeline: float
    source_trim_start: float = 0.0
    source_trim_end: float
    source_duration: float = 0.0
    volume: float = 1.0
    fade_in: float = 0.0
    fade_out: float = 0.0
    effects: List[FilterSpec] = Field(default_factory=list)

class SubtitleClipStyle(BaseModel):
    font_name: str = "Impact"
    font_size: int = 48
    primary_color: str = "#FFFFFF"
    stroke_color: str = "#000000"
    stroke_width: int = 2
    animation: str = "pop_in"  # "none", "pop_in", "karaoke", "fade"
    alignment: str = "center_bottom"

class SubtitleClip(BaseModel):
    id: str
    text: str
    start_time: float
    end_time: float
    style: SubtitleClipStyle = Field(default_factory=SubtitleClipStyle)

class OverlayClip(BaseModel):
    id: str
    type: str = "broll"  # "broll", "image", "text_sticker", "effect_overlay"
    source_path: str
    start_time_in_timeline: float
    end_time_in_timeline: float
    source_trim_start: float = 0.0
    source_trim_end: float
    source_duration: float = 0.0
    transform: TransformState = Field(default_factory=TransformState)

class VideoTrack(BaseModel):
    id: str
    name: str = "Video Track"
    index: int = 0
    clips: List[VideoClip] = Field(default_factory=list)

class AudioTrack(BaseModel):
    id: str
    name: str = "Audio Track"
    index: int = 0
    clips: List[AudioClip] = Field(default_factory=list)

class SubtitleTrack(BaseModel):
    id: str
    clips: List[SubtitleClip] = Field(default_factory=list)

class OverlayTrack(BaseModel):
    id: str
    clips: List[OverlayClip] = Field(default_factory=list)

class Tracks(BaseModel):
    video: List[VideoTrack] = Field(default_factory=list)
    audio: List[AudioTrack] = Field(default_factory=list)
    subtitles: List[SubtitleTrack] = Field(default_factory=list)
    overlays: List[OverlayTrack] = Field(default_factory=list)

class TimelineSettings(BaseModel):
    width: int = 1080
    height: int = 1920
    fps: int = 30
    sample_rate: int = 44100
    aspect_ratio: str = "9:16"

class TimelineState(BaseModel):
    project_id: str
    project_name: str
    settings: TimelineSettings = Field(default_factory=TimelineSettings)
    tracks: Tracks = Field(default_factory=Tracks)
