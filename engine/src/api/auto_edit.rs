/// api/auto_edit.rs — POST /auto-edit pipeline orchestrator (Squad-R2).
///
/// probe duration → detect silences → transcribe (if whisper available) →
/// director → critic → render. Sessions live in an in-memory HashMap; progress
/// is exposed via GET /auto-edit/status/:id and a WebSocket at
/// /ws/progress/:id.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Path, State,
    },
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::critic;
use crate::director;
use crate::llm::LlmBridge;
use crate::media::MediaEngine;
use crate::render::RenderPipeline;
use crate::transcribe::Transcriber;
use crate::types::{ClipSpec, RenderRequest};

const APPROVAL_THRESHOLD: f64 = 0.6;
const WS_POLL_MS: u64 = 500;
const WS_MAX_LIFETIME_SECS: u64 = 1800;

// ── state ────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AutoEditState {
    sessions: Arc<Mutex<HashMap<String, SessionState>>>,
}

impl AutoEditState {
    pub fn new() -> Self {
        AutoEditState {
            sessions: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    fn insert(&self, session: SessionState) {
        if let Ok(mut map) = self.sessions.lock() {
            map.insert(session.session_id.clone(), session);
        }
    }

    pub fn get(&self, session_id: &str) -> Option<SessionState> {
        self.sessions
            .lock()
            .ok()
            .and_then(|map| map.get(session_id).cloned())
    }

    fn update(&self, session_id: &str, f: impl FnOnce(&mut SessionState)) {
        if let Ok(mut map) = self.sessions.lock() {
            if let Some(s) = map.get_mut(session_id) {
                f(s);
            }
        }
    }
}

impl Default for AutoEditState {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct ProgressEvent {
    pub ts: String,
    pub stage: String,
    pub progress: f32,
    pub message: String,
    /// Flutter-compatible fields
    #[serde(rename = "type")]
    pub event_type: String,
    #[serde(rename = "message_ar")]
    pub message_ar: String,
    #[serde(rename = "message_en")]
    pub message_en: String,
}

/// Map Rust pipeline stage names → Flutter-expected stage names
fn map_stage(rust_stage: &str) -> &str {
    match rust_stage {
        "probe" => "queued",
        "silences" => "transcribing",
        "transcribe" => "understanding",
        "direct" => "selecting",
        "critic" => "hooks",
        "render" => "rendering",
        "compile" => "compiling",
        "done" => "done",
        _ => rust_stage,
    }
}

#[derive(Serialize, Clone, Debug)]
pub struct SessionState {
    pub session_id: String,
    pub status: String,
    pub stage: String,
    pub progress: f32,
    pub created_at: String,
    pub events: Vec<ProgressEvent>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

// ── request payload ──────────────────────────────────────────────────────────

#[derive(Deserialize, Debug)]
pub struct AutoEditRequest {
    pub video_path: String,
    #[serde(default)]
    pub answers: Answers,
}

#[derive(Deserialize, Debug, Default)]
#[serde(default)]
pub struct Answers {
    pub content_type: Option<String>,
    pub platform: Option<String>,
    pub n_clips: Option<usize>,
    pub clip_duration_sec: Option<f64>,
    pub caption_theme: Option<String>,
    pub zoom_style: Option<String>,
    pub language: Option<String>,
}

pub fn router(state: AutoEditState) -> Router {
    Router::new()
        .route("/auto-edit", post(post_auto_edit))
        .route("/auto-edit/status/:session_id", get(get_status))
        .route("/ws/progress/:session_id", get(ws_progress))
        .with_state(state)
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn post_auto_edit(
    State(state): State<AutoEditState>,
    Json(req): Json<AutoEditRequest>,
) -> Response {
    if req.video_path.trim().is_empty()
        || !std::path::Path::new(&req.video_path).exists()
    {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": format!("video_path not found: {}", req.video_path)})),
        )
            .into_response();
    }

    let session_id = uuid::Uuid::new_v4().to_string();
    state.insert(SessionState {
        session_id: session_id.clone(),
        status: "queued".to_string(),
        stage: "queued".to_string(),
        progress: 0.0,
        created_at: chrono::Utc::now().to_rfc3339(),
        events: vec![],
        result: None,
        error: None,
    });

    tokio::spawn(run_pipeline(state.clone(), session_id.clone(), req));

    (
        StatusCode::ACCEPTED,
        Json(json!({"session_id": session_id})),
    )
        .into_response()
}

async fn get_status(
    State(state): State<AutoEditState>,
    Path(session_id): Path<String>,
) -> Response {
    match state.get(&session_id) {
        Some(session) => Json(session).into_response(),
        None => (
            StatusCode::NOT_FOUND,
            Json(json!({"error": "unknown session"})),
        )
            .into_response(),
    }
}

async fn ws_progress(
    upgrade: WebSocketUpgrade,
    Path(session_id): Path<String>,
    State(state): State<AutoEditState>,
) -> Response {
    upgrade.on_upgrade(move |socket| progress_socket(socket, session_id, state))
}

async fn progress_socket(mut socket: WebSocket, session_id: String, state: AutoEditState) {
    let mut sent = 0usize;
    let deadline =
        tokio::time::Instant::now() + std::time::Duration::from_secs(WS_MAX_LIFETIME_SECS);

    loop {
        if tokio::time::Instant::now() > deadline {
            let _ = socket
                .send(Message::Text(json!({"event": "timeout"}).to_string()))
                .await;
            return;
        }
        let Some(session) = state.get(&session_id) else {
            let _ = socket
                .send(Message::Text(json!({"error": "unknown session"}).to_string()))
                .await;
            return;
        };
        for ev in session.events.iter().skip(sent) {
            let Ok(text) = serde_json::to_string(ev) else { return };
            if socket.send(Message::Text(text)).await.is_err() {
                return;
            }
            sent += 1;
        }
        if session.status == "done" || session.status == "error" {
            if session.status == "done" {
                // Send done event with results in Flutter-expected format
                let _ = socket
                    .send(Message::Text(
                        json!({
                            "type": "done",
                            "result": session.result.clone().unwrap_or(json!({}))
                        })
                        .to_string(),
                    ))
                    .await;
            } else {
                // Send error event
                let _ = socket
                    .send(Message::Text(
                        json!({
                            "type": "error",
                            "message_ar": session.error.clone().unwrap_or_default(),
                            "message_en": session.error.clone().unwrap_or_default()
                        })
                        .to_string(),
                    ))
                    .await;
            }
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(WS_POLL_MS)).await;
    }
}

// ── pipeline ─────────────────────────────────────────────────────────────────

fn report(state: &AutoEditState, session_id: &str, stage: &str, progress: f32, message: &str) {
    let mapped = map_stage(stage);
    let ev = ProgressEvent {
        ts: chrono::Utc::now().to_rfc3339(),
        stage: mapped.to_string(),
        progress,
        message: message.to_string(),
        event_type: "progress".to_string(),
        message_ar: message.to_string(),
        message_en: message.to_string(),
    };
    state.update(session_id, |s| {
        s.status = "running".to_string();
        s.stage = mapped.to_string();
        s.progress = progress;
        s.events.push(ev);
    });
}

fn fail(state: &AutoEditState, session_id: &str, err: String) {
    state.update(session_id, |s| {
        s.status = "error".to_string();
        s.stage = "error".to_string();
        s.error = Some(err.clone());
        s.events.push(ProgressEvent {
            ts: chrono::Utc::now().to_rfc3339(),
            stage: "error".to_string(),
            progress: s.progress,
            message: err.clone(),
            event_type: "error".to_string(),
            message_ar: err.clone(),
            message_en: err,
        });
    });
}

fn speech_segments(silences: &[crate::types::Silence]) -> Vec<(f64, f64)> {
    let mut segs = Vec::new();
    let mut cursor = 0.0f64;
    for s in silences {
        if s.start > cursor + 0.15 {
            segs.push((cursor, s.start));
        }
        cursor = cursor.max(s.end);
    }
    segs.push((cursor, cursor + 1.0));
    segs
}

fn fallback_summary(speech: &[(f64, f64)]) -> String {
    speech
        .iter()
        .enumerate()
        .map(|(i, (s, e))| format!("[{:.1}s] (speech segment {}, {:.1}s)", s, i + 1, e - s))
        .collect::<Vec<_>>()
        .join("\n")
}

async fn run_pipeline(state: AutoEditState, session_id: String, req: AutoEditRequest) {
    let media = MediaEngine::new();
    let llm = LlmBridge::new();

    // 1) probe duration
    report(&state, &session_id, "probe", 5.0, "probing duration");
    let Ok(duration) = media.probe_duration(&req.video_path).await else {
        fail(&state, &session_id, "ffmpeg could not probe video duration".into());
        return;
    };

    // 2) detect silences → speech segments
    report(&state, &session_id, "silences", 20.0, "detecting silences");
    let silences = media
        .detect_silences(&req.video_path, -30.0, 0.5)
        .await
        .unwrap_or_default();
    let speech = speech_segments(&silences);

    // 3) transcribe (best-effort)
    report(&state, &session_id, "transcribe", 40.0, "building transcript");
    let transcriber = Transcriber::new();
    let summary = if transcriber.is_available() {
        match transcriber.transcribe(&req.video_path).await {
            Ok(segments) => segments
                .iter()
                .map(|s| format!("[{:.1}s] {}", s.start, s.text))
                .collect::<Vec<_>>()
                .join("\n"),
            Err(_) => fallback_summary(&speech),
        }
    } else {
        fallback_summary(&speech)
    };
    let summary: String = summary.chars().take(6000).collect();

    // 4) director
    report(&state, &session_id, "direct", 60.0, "directing clips");
    let n_clips = req.answers.n_clips.unwrap_or(5).clamp(1, 12);
    let profile = json!({
        "content_type": req.answers.content_type.clone().unwrap_or_else(|| "podcast".into()),
        "platform": req.answers.platform,
        "caption_theme": req.answers.caption_theme,
        "zoom_style": req.answers.zoom_style,
        "clip_duration_sec": req.answers.clip_duration_sec.unwrap_or(duration.min(90.0)),
    });
    let mut plan = match director::direct(&summary, &profile, &llm, n_clips).await {
        Ok(p) if !p.clips.is_empty() => p,
        _ => director::heuristic_direct(&summary, n_clips),
    };

    // 5) critic (+ heuristic retry below threshold)
    report(&state, &session_id, "critic", 75.0, "reviewing plan");
    let mut verdict = critic::review(&plan, &llm).await;
    let mut source = if plan.reasoning.starts_with("heuristic fallback") {
        "heuristic"
    } else {
        "llm"
    };
    if verdict.score < APPROVAL_THRESHOLD && !summary.trim().is_empty() {
        let alt = director::heuristic_direct(&summary, n_clips);
        if !alt.clips.is_empty() {
            let alt_verdict = critic::review(&alt, &llm).await;
            if alt_verdict.score > verdict.score {
                plan = alt;
                verdict = alt_verdict;
                source = "heuristic";
            }
        }
    }

    // 6) render
    report(&state, &session_id, "render", 85.0, "rendering clips");
    let output_dir = format!("output/{session_id}");
    let specs: Vec<ClipSpec> = plan
        .clips
        .iter()
        .enumerate()
        .map(|(i, c)| ClipSpec {
            index: i,
            start_sec: c.start_sec,
            end_sec: c.end_sec,
            hook: c.hook_text.clone(),
            caption_theme: c.caption_theme.clone(),
            zoom_style: c.zoom_style.clone(),
        })
        .collect();
    let render_req = RenderRequest {
        video_path: req.video_path.clone(),
        output_dir,
        clips: specs,
        width: 1080,
        height: 1920,
        fps: 30,
    };
    let pipeline = RenderPipeline::new();
    let rendered = pipeline.render(&render_req).await.unwrap_or_default();
    let compiled = if rendered.is_empty() {
        None
    } else {
        let path = format!("{}/compiled_final.mp4", render_req.output_dir);
        pipeline.compile(&rendered, &path).await.ok()
    };

    // 7) done
    report(&state, &session_id, "done", 100.0, "pipeline finished");
    let result = json!({
        "video_duration_sec": duration,
        "source": source,
        "reasoning": plan.reasoning,
        "clips": plan.clips,
        "critic": {
            "score": verdict.score,
            "feedback": verdict.feedback,
            "issues": verdict.issues,
        },
        "rendered": rendered,
        "compiled": compiled,
    });
    state.update(&session_id, |s| {
        s.status = "done".to_string();
        s.stage = "done".to_string();
        s.progress = 100.0;
        s.result = Some(result);
    });
}
