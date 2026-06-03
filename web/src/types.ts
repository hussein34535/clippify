// types.ts
// TypeScript types for the ClipAI Pro NLE timeline state

export interface Vector2D {
  x: number;
  y: number;
}

export interface Keyframe {
  time: number;
  property: string;
  value: any;
  easing: 'linear' | 'ease-in' | 'ease-out' | 'ease-in-out';
}

export interface TransformState {
  position: Vector2D;
  scale: Vector2D;
  rotation: number;
  keyframes: Keyframe[];
}

export interface ColorGradingState {
  brightness: number;
  contrast: number;
  saturation: number;
  temperature: number;
  lut_path: string;
  lift?: { r: number; g: number; b: number };
  gamma?: { r: number; g: number; b: number };
  gain?: { r: number; g: number; b: number };
}

export interface FilterSpec {
  type: 'blur' | 'vignette' | 'mosaic' | 'chromakey' | 'noise';
  params: Record<string, any>;
}

export interface AIFeatures {
  face_tracking: boolean;
  bg_removed: boolean;
  bg_remove_method: 'none' | 'chromakey' | 'sam' | 'rmbg';
  chromakey_color: string;
  vocal_isolation?: boolean;
  auto_ducking?: boolean;
  ducking_level?: number;
}

export interface VideoClip {
  id: string;
  source_path: string;
  start_time_in_timeline: number;
  end_time_in_timeline: number;
  source_trim_start: number;
  source_trim_end: number;
  speed: number;
  volume: number;
  transform: TransformState;
  color_grading: ColorGradingState;
  filters: FilterSpec[];
  ai_features: AIFeatures;
}

export interface AudioClip {
  id: string;
  source_path: string;
  start_time_in_timeline: number;
  end_time_in_timeline: number;
  source_trim_start: number;
  source_trim_end: number;
  volume: number;
  fade_in: number;
  fade_out: number;
  effects: FilterSpec[];
}

export interface SubtitleClipStyle {
  font_name: string;
  font_size: number;
  primary_color: string;
  stroke_color: string;
  stroke_width: number;
  animation: 'none' | 'pop_in' | 'karaoke' | 'fade';
  alignment: 'center_bottom' | 'center_top' | 'center_middle';
}

export interface SubtitleClip {
  id: string;
  text: string;
  start_time: number;
  end_time: number;
  style: SubtitleClipStyle;
}

export interface OverlayClip {
  id: string;
  type: 'broll' | 'image' | 'text_sticker' | 'effect_overlay';
  source_path: string;
  start_time_in_timeline: number;
  end_time_in_timeline: number;
  source_trim_start: number;
  source_trim_end: number;
  transform: TransformState;
}

export interface VideoTrack {
  id: string;
  name: string;
  index: number;
  clips: VideoClip[];
}

export interface AudioTrack {
  id: string;
  name: string;
  index: number;
  clips: AudioClip[];
}

export interface SubtitleTrack {
  id: string;
  clips: SubtitleClip[];
}

export interface OverlayTrack {
  id: string;
  clips: OverlayClip[];
}

export interface Tracks {
  video: VideoTrack[];
  audio: AudioTrack[];
  subtitles: SubtitleTrack[];
  overlays: OverlayTrack[];
}

export interface TimelineSettings {
  width: number;
  height: number;
  fps: number;
  sample_rate: number;
  aspect_ratio: '9:16' | '16:9' | '1:1';
}

// App-level types
export interface Word {
  text: string;
  start: number;
  end: number;
}

export interface Clip {
  index: number;
  start_sec: number;
  end_sec: number;
  hook: string;
  reason: string;
  caption_theme: string;
  zoom_style: string;
  color_grade: string;
  emphasis_words: string[];
  sfx_queries: string[];
  planned_brolls: any[];
  hook_options: string[];
  slow_motion_start: number;
  slow_motion_end: number;
  slow_motion_speed: number;
}

export interface AppSettings {
  n_clips: number;
  duration: number;
  subtitle_style: string;
  font_name: string;
  export_quality: string;
  sfx_mode: string;
  translate_to_arabic: boolean;
  auto_broll: boolean;
  gemma_multimodal: boolean;
  pexels_api_key: string;
  pixabay_api_key: string;
  output_dir: string;
  export_mode: string;
  framing_strategy?: string;
  whisper_model: string;
}

export interface TimelineState {
  project_id: string;
  project_name: string;
  settings: TimelineSettings;
  tracks: Tracks;
}

export interface ViralRecommendation {
  time_sec: number;
  type: 'zoom' | 'sfx' | 'broll' | 'text_highlight' | 'speed_up' | string;
  description: string;
  reason: string;
}
