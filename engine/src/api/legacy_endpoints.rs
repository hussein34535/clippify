//! api/legacy_endpoints.rs — endpoints the Flutter client (api_client.dart)
//! expects from the old Python backend, re-exposed by the Rust engine.
//!
//! Actively-used routes get real implementations on top of MediaEngine /
//! AutoEditState; the remaining legacy routes answer 501 with a graceful JSON
//! body so the client degrades cleanly instead of failing on connection
//! errors (Dio throws on any non-2xx status, hence explicit bodies).

use std::collections::HashSet;
use std::sync::{Mutex, OnceLock};

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::api::auto_edit::AutoEditState;
use crate::media::MediaEngine;

const CACHE_THUMBS_DIR: &str = "cache/thumbs";

/// Session ids marked cancelled by POST /auto-edit/cancel/:id.
/// The pipeline itself does not poll this yet; removal from the live session
/// map requires a `pub fn remove` on AutoEditState (see BLOCKERS).
static CANCELLED: OnceLock<Mutex<HashSet<String>>> = OnceLock::new();

fn cancelled_set() -> &'static Mutex<HashSet<String>> {
    CANCELLED.get_or_init(|| Mutex::new(HashSet::new()))
}

pub fn router(auto_edit_state: AutoEditState) -> Router {
    Router::new()
        // ── real implementations ──
        .route("/media-info", post(media_info))
        .route("/detect-silence", post(detect_silence))
        .route("/clear-cache", post(clear_cache))
        .route("/auto-edit/cancel/:session_id", post(cancel_auto_edit))
        // ── actionable stubs (permanent: standalone-mode features) ──
        .route("/transcribe", post(transcribe_stub))
        .route("/download-youtube", post(youtube_stub))
        // ── 501 legacy stubs ──
        .route("/copilot/chat", post(not_implemented))
        .route("/analyze-video", post(not_implemented))
        .route("/generate-plan", post(not_implemented))
        .route("/render-plan", post(not_implemented))
        .route("/ai/tools", get(not_implemented))
        .route("/ai/execute", post(not_implemented))
        .route("/project/save", post(not_implemented))
        .route("/project/load", get(not_implemented))
        .route("/project/recent", get(not_implemented))
        .route("/project/render/timeline", post(not_implemented))
        .route("/project/export/xml", post(not_implemented))
        .route("/analyze-beats", post(not_implemented))
        .route("/style/analyze-reference", post(not_implemented))
        .route("/style/imitate", post(not_implemented))
        .route("/broll/search", post(not_implemented))
        .route("/broll/download", post(not_implemented))
        .route("/audio/separate", post(not_implemented))
        .route("/audio/ducking", post(not_implemented))
        .route("/viral/recommendations", post(not_implemented))
        .route("/project/ai/autoframing", post(not_implemented))
        // NOTE: /brief/parse lives in features::router() (real handler);
        // registering it here too made axum panic on overlapping routes.
        .with_state(auto_edit_state)
}

// ── shared stub helpers ──────────────────────────────────────────────────────

async fn not_implemented() -> Response {
    (
        StatusCode::NOT_IMPLEMENTED,
        Json(json!({
            "status": "not_implemented",
            "detail": "This feature requires the full Python backend"
        })),
    )
        .into_response()
}

async fn transcribe_stub() -> Response {
    (
        StatusCode::NOT_IMPLEMENTED,
        Json(json!({"status": "unavailable", "reason": "use standalone mode"})),
    )
        .into_response()
}

async fn youtube_stub() -> Response {
    (
        StatusCode::NOT_IMPLEMENTED,
        Json(json!({
            "status": "unavailable",
            "reason": "use standalone YoutubeService"
        })),
    )
        .into_response()
}

// ── real handlers ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct MediaInfoRequest {
    path: String,
    #[serde(default)]
    #[allow(dead_code)]
    timestamp_sec: Option<f64>,
}

async fn media_info(Json(req): Json<MediaInfoRequest>) -> Response {
    if req.path.trim().is_empty() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"status": "error", "error": "path is required"})),
        )
            .into_response();
    }
    if !std::path::Path::new(&req.path).exists() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "status": "error",
                "error": format!("file not found: {}", req.path)
            })),
        )
            .into_response();
    }

    let engine = MediaEngine::new();
    match engine.probe_duration(&req.path).await {
        Ok(duration) => (
            StatusCode::OK,
            Json(json!({"status": "ok", "duration": duration})),
        )
            .into_response(),
        Err(err) => (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "status": "error",
                "error": format!("ffmpeg probe failed: {err}")
            })),
        )
            .into_response(),
    }
}

#[derive(Deserialize)]
struct DetectSilenceRequest {
    video_path: String,
    #[serde(default = "default_min_silence_ms")]
    min_silence_duration_ms: u64,
    /// 0..1 amplitude threshold → silencedetect noise floor in dB.
    #[serde(default = "default_threshold")]
    threshold: f64,
}

fn default_min_silence_ms() -> u64 {
    500
}

fn default_threshold() -> f64 {
    0.5
}

async fn detect_silence(Json(req): Json<DetectSilenceRequest>) -> Response {
    if req.video_path.trim().is_empty() || !std::path::Path::new(&req.video_path).exists() {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "status": "error",
                "error": format!("video_path not found: {}", req.video_path)
            })),
        )
            .into_response();
    }

    let noise_db = (-60.0 * req.threshold.clamp(0.05, 1.0)).clamp(-70.0, -5.0);
    let min_dur = req.min_silence_duration_ms as f64 / 1000.0;

    let engine = MediaEngine::new();
    match engine.detect_silences(&req.video_path, noise_db, min_dur).await {
        Ok(silences) => (
            StatusCode::OK,
            Json(json!({
                "status": "ok",
                "silences": silences,
                "speech": speech_segments(&silences),
            })),
        )
            .into_response(),
        Err(err) => (
            StatusCode::UNPROCESSABLE_ENTITY,
            Json(json!({
                "status": "error",
                "error": format!("silencedetect failed: {err}")
            })),
        )
            .into_response(),
    }
}

/// Speech segments = gaps between silences (mirrors main.rs / auto_edit.rs).
fn speech_segments(silences: &[crate::types::Silence]) -> Vec<Value> {
    let mut segs = Vec::new();
    let mut cursor = 0.0f64;
    for s in silences {
        if s.start > cursor + 0.15 {
            segs.push(json!({"start": cursor, "end": s.start}));
        }
        cursor = cursor.max(s.end);
    }
    if cursor > 0.0 {
        segs.push(json!({"start": cursor, "end": cursor + 1.0}));
    }
    segs
}

async fn clear_cache() -> Response {
    let dir = std::path::Path::new(CACHE_THUMBS_DIR);
    let mut removed = 0usize;
    let mut errors: Vec<String> = Vec::new();

    match std::fs::read_dir(dir) {
        Ok(entries) => {
            for entry in entries.flatten() {
                let path = entry.path();
                let result = if path.is_dir() {
                    std::fs::remove_dir_all(&path)
                } else {
                    std::fs::remove_file(&path)
                };
                match result {
                    Ok(()) => removed += 1,
                    Err(err) => errors.push(format!(
                        "{}: {err}",
                        entry.file_name().to_string_lossy()
                    )),
                }
            }
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => errors.push(format!("{CACHE_THUMBS_DIR}: {err}")),
    }

    if errors.is_empty() {
        (
            StatusCode::OK,
            Json(json!({"status": "ok", "removed": removed})),
        )
            .into_response()
    } else {
        (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(json!({"status": "error", "removed": removed, "errors": errors})),
        )
            .into_response()
    }
}

async fn cancel_auto_edit(
    State(state): State<AutoEditState>,
    Path(session_id): Path<String>,
) -> Response {
    if let Ok(mut set) = cancelled_set().lock() {
        set.insert(session_id.clone());
    }
    let known = state.get(&session_id).is_some();
    (
        StatusCode::OK,
        Json(json!({
            "status": "ok",
            "session_id": session_id,
            "known": known,
        })),
    )
        .into_response()
}
