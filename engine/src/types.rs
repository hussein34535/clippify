use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Silence {
    pub start: f64,
    pub end: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct Thumb {
    pub index: usize,
    pub path: String,
    pub timestamp_sec: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TranscribedWord {
    pub text: String,
    pub start: f64,
    pub end: f64,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TranscribedSegment {
    pub text: String,
    pub start: f64,
    pub end: f64,
    pub words: Vec<TranscribedWord>,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct ClipSpec {
    pub index: usize,
    pub start_sec: f64,
    pub end_sec: f64,
    pub hook: String,
    pub caption_theme: String,
    pub zoom_style: String,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct RenderRequest {
    pub video_path: String,
    pub output_dir: String,
    pub clips: Vec<ClipSpec>,
    pub width: u32,
    pub height: u32,
    pub fps: u32,
}

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct LlmResponse {
    pub text: String,
    pub provider: String,
    pub latency_ms: u128,
}
