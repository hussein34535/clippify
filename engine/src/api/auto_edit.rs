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
use crate::{short_ai_director, short_edit, short_render};
use crate::short_plan::{self, Treatment, ZoomPolicy};
use crate::short_creative::{self, Style};
use crate::transcribe::Transcriber;
use crate::types::{ClipSpec, RenderRequest};

const APPROVAL_THRESHOLD: f64 = 0.6;
const WS_POLL_MS: u64 = 500;
const WS_MAX_LIFETIME_SECS: u64 = 1800;

// ── state ────────────────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AutoEditState {
    sessions: Arc<Mutex<HashMap<String, SessionState>>>,
    local_short: bool,
    mobile_upload: bool,
    short_provider: Option<Arc<short_edit::ShortProvider>>,
    short_tasks: Arc<Mutex<HashMap<String, tokio::task::AbortHandle>>>,
}

impl AutoEditState {
    pub fn new() -> Self {
        AutoEditState {
            sessions: Arc::new(Mutex::new(HashMap::new())),
            local_short: false,
            mobile_upload: false,
            short_provider: None,
            short_tasks: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn local_short(short_provider: Option<short_edit::ShortProvider>, mobile_upload: bool) -> Self {
        Self {
            local_short: true,
            mobile_upload,
            short_provider: short_provider.map(Arc::new),
            ..Self::new()
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
    pub mode: Option<String>,
    pub content_type: Option<String>,
    pub platform: Option<String>,
    pub n_clips: Option<usize>,
    pub clip_duration_sec: Option<f64>,
    pub caption_theme: Option<String>,
    pub zoom_style: Option<String>,
    pub zoom_policy: Option<ZoomPolicy>,
    pub edit_brief: Option<String>,
    pub creative_style: Option<Style>,
    pub creative_title: Option<String>,
    pub creative_music: Option<bool>,
    pub creative_effects: Option<bool>,
    pub short_director: ShortDirector,
    pub language: Option<String>,
}

#[derive(Clone, Copy, Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ShortDirector {
    #[default]
    Hybrid,
    Ai,
    Local,
}

pub fn router(state: AutoEditState) -> Router {
    let mut routes = Router::new()
        .route("/auto-edit", post(post_auto_edit))
        .route("/auto-edit/status/:session_id", get(get_status))
        .route("/ws/progress/:session_id", get(ws_progress));
    if state.local_short {
        routes = routes.route("/auto-edit/cancel/:session_id", post(cancel_short));
    }
    routes.with_state(state)
}

// ── handlers ─────────────────────────────────────────────────────────────────

async fn post_auto_edit(
    State(state): State<AutoEditState>,
    Json(req): Json<AutoEditRequest>,
) -> Response {
    let short = req.answers.mode.as_deref() == Some("short_auto");
    if short != state.local_short {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "Short Auto requires a supported local engine"})),
        )
            .into_response();
    }
    let valid_input = if state.mobile_upload {
        super::files::is_uploaded_media(&req.video_path).await
    } else {
        !req.video_path.trim().is_empty() && std::path::Path::new(&req.video_path).is_file()
    };
    if !valid_input {
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"error": "Video file not found. Upload the video before starting."})),
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

    if short {
        let mut tasks = state.short_tasks.lock().expect("short tasks lock");
        if !tasks.is_empty() {
            if let Ok(mut sessions) = state.sessions.lock() {
                sessions.remove(&session_id);
            }
            return (
                StatusCode::CONFLICT,
                Json(json!({"error": "A Short Auto job is already running"})),
            )
                .into_response();
        }
        let task_state = state.clone();
        let id = session_id.clone();
        let upload = state.mobile_upload.then(|| req.video_path.clone());
        let handle = tokio::spawn(async move {
            run_short_pipeline(&task_state, &id, &req).await;
        });
        tasks.insert(session_id.clone(), handle.abort_handle());
        let cleanup_state = state.clone();
        let cleanup_id = session_id.clone();
        tokio::spawn(async move {
            let _ = handle.await;
            if let Some(path) = upload.filter(|_| {
                cleanup_state.get(&cleanup_id).is_some_and(|session| session.status == "done")
            }) {
                let _ = tokio::fs::remove_file(path).await;
            }
            if let Ok(mut tasks) = cleanup_state.short_tasks.lock() {
                tasks.remove(&cleanup_id);
            }
        });
    } else {
        tokio::spawn(run_pipeline(state.clone(), session_id.clone(), req));
    }

    (
        StatusCode::ACCEPTED,
        Json(json!({"session_id": session_id})),
    )
        .into_response()
}

async fn cancel_short(
    State(state): State<AutoEditState>,
    Path(session_id): Path<String>,
) -> Response {
    let task = state.short_tasks.lock().ok().and_then(|tasks| tasks.get(&session_id).cloned());
    if let Some(task) = task {
        state.update(&session_id, |session| {
            if session.status == "queued" || session.status == "running" {
                session.status = "error".into();
                session.stage = "error".into();
                session.error = Some("تم إلغاء المونتاج.".into());
                task.abort();
            }
        });
    } else if state.get(&session_id).is_none() {
        return (StatusCode::NOT_FOUND, Json(json!({"error": "unknown session"}))).into_response();
    }
    Json(json!({"status": "ok"})).into_response()
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
        if s.status == "error" {
            return;
        }
        s.status = "running".to_string();
        s.stage = mapped.to_string();
        s.progress = progress;
        s.events.push(ev);
    });
}

fn fail(state: &AutoEditState, session_id: &str, err: String) {
    state.update(session_id, |s| {
        if s.status == "error" {
            return;
        }
        s.status = "error".to_string();
        s.stage = "error".to_string();
        s.error = Some(err);
    });
}

fn finish(state: &AutoEditState, session_id: &str, result: Value) {
    state.update(session_id, |session| {
        if session.status == "error" {
            return;
        }
        session.result = Some(result);
        session.status = "done".into();
        session.stage = "done".into();
        session.progress = 100.0;
    });
}

async fn run_short_pipeline(state: &AutoEditState, session_id: &str, req: &AutoEditRequest) {
    let media = MediaEngine::new();
    let ai_only = req.answers.short_director == ShortDirector::Ai;
    if ai_only {
        match state.short_provider.as_deref() {
            Some(provider) if provider.vision() => {}
            Some(_) => {
                fail(
                    state,
                    session_id,
                    short_ai_director::DirectorError::Vision.message().into(),
                );
                return;
            }
            None => {
                fail(state, session_id, "المخرج الذكي محتاج مزوّد بيدعم الصور. فعّل المزوّد من إعدادات الذكاء الاصطناعي أو اختار المونتاج المحلي.".into());
                return;
            }
        }
    }
    report(state, session_id, "probe", 5.0, "بنفحص الفيديو");
    let duration = match media.probe_duration(&req.video_path).await {
        Ok(value) if value.is_finite() && value > 0.0 && value <= 900.0 => value,
        _ => {
            fail(state, session_id, "اختار فيديو صالح مدته 15 دقيقة أو أقل.".into());
            return;
        }
    };

    report(state, session_id, "transcribe", 20.0, "بنحلل الكلام والصوت");
    let transcriber = Transcriber::new();
    let (transcript, silences) = tokio::join!(
        transcriber.transcribe_short(&media, &req.video_path),
        async {
            if ai_only { Ok(Vec::new()) } else {
                media.detect_silences(&req.video_path, -35.0, 0.6).await
            }
        },
    );
    let transcript_available = transcript.as_ref().is_ok_and(|segments| !segments.is_empty());
    let transcript = transcript.unwrap_or_default();
    let silences = silences.unwrap_or_default();
    let target = req.answers.clip_duration_sec.filter(|value| value.is_finite()).unwrap_or(45.0);
    let brief: String = req.answers.edit_brief.as_deref().unwrap_or("").chars().take(500).collect();
    let zoom_policy = req.answers.zoom_policy.unwrap_or_default();
    let platform = req.answers.platform.as_deref().unwrap_or("tiktok");
    if ai_only {
        let provider = state.short_provider.as_deref().unwrap();
        report(state, session_id, "direct", 58.0, "المخرج الذكي بيفهم المشهد وبيحدد الهدف وخطة المونتاج");
        let plan = short_ai_director::direct(provider, &media, short_ai_director::Input {
            video: &req.video_path, transcript: &transcript, duration, target, platform, brief: &brief, zoom_policy,
        }).await;
        let plan = match plan {
            Ok(plan) => plan,
            Err(problem) => {
                eprintln!("[short-director] {problem:?}");
                fail(state, session_id, problem.message().into());
                return;
            }
        };
        let description = json!({
            "understanding": plan.understanding,
            "purpose": plan.purpose,
            "strategy": plan.strategy,
            "evidence_frames": plan.evidence_frames
        });
        let mut treatment = plan.treatment;
        let effects = req.answers.creative_effects != Some(false)
            && (treatment.sound != short_plan::Accent::Off || !plan.design.sound_cues.is_empty());
        if !effects {
            treatment.sound = short_plan::Accent::Off;
        }
        let hook = plan.title.clone();
        let design = short_creative::Options {
            style: plan.style,
            title: plan.title,
            music: plan.music && req.answers.creative_music != Some(false),
            effects,
            brief,
            focus_source_sec: None,
            directed: Some(plan.design),
        };
        render_short_result(state, session_id, req, &media, &transcript, ShortRenderPlan {
            ranges: plan.ranges, treatment, design, hook, source: provider.name(),
            provider_status: "applied", description: Some(description),
        }).await;
        return;
    }

    let options = short_edit::candidates(&transcript, &silences, duration, target);
    report(state, session_id, "direct", 62.0, "بنختار المقطع ونجهّز الألوان والمؤثرات");
    let creative_style = req.answers.creative_style.unwrap_or_default();
    let provider = state.short_provider.as_deref().filter(|_| req.answers.short_director != ShortDirector::Local);
    let direction = match provider {
        Some(provider) => short_edit::direct_with_provider(
            provider, &options, &brief, platform, zoom_policy, creative_style,
            &media, &req.video_path,
        ).await,
        None => None,
    };
    let chosen = &options[direction.as_ref().map_or(0, |plan| plan.candidate_id)];
    let used_provider = direction.is_some();
    let provider_name = provider.map(|provider| provider.name());
    let focus_source_sec = direction.as_ref().and_then(|plan| plan.focus_sec);
    let style = creative_style.resolve(
        direction.as_ref().and_then(|plan| plan.creative_style),
        req.answers.content_type.as_deref().unwrap_or("auto"),
        transcript_available,
        &brief,
    );
    let provider_status = if used_provider {
        "applied"
    } else if provider.is_some() {
        "local_fallback"
    } else {
        "disabled"
    };
    let mut treatment = direction.map_or_else(
        || Treatment::local(&brief, zoom_policy),
        |plan| plan.treatment.respect(&brief, zoom_policy),
    );
    if req.answers.creative_effects == Some(false) {
        treatment.sound = short_plan::Accent::Off;
    }
    let mut start = chosen.start;
    if start < 4.0 && chosen.end - start >= 5.0 && treatment.trim_pauses {
        let visually_ready = short_edit::usable_opening(&media, &req.video_path).await;
        let first_speech = transcript.iter().find(|segment| segment.end > start)
            .map_or(chosen.end, |segment| segment.start - 0.18);
        // Missing pictures can be cut only up to the first usable dialogue.
        if visually_ready <= first_speech && visually_ready <= chosen.end - 3.0 {
            start = start.max(visually_ready);
        }
    }
    let ranges = short_plan::keep_ranges(start, chosen.end, &silences, &transcript, &treatment, &brief);
    let design = short_creative::Options {
        style,
        title: req.answers.creative_title.as_deref().unwrap_or("").chars().take(35).collect(),
        music: req.answers.creative_music.unwrap_or(style != Style::Clean),
        effects: req.answers.creative_effects.unwrap_or(style != Style::Clean),
        brief,
        focus_source_sec,
        directed: None,
    };
    render_short_result(state, session_id, req, &media, &transcript, ShortRenderPlan {
        ranges, treatment, design, hook: chosen.opening.clone(),
        source: if used_provider { provider_name.unwrap_or("ai_provider") } else if transcript_available { "local_transcript" } else { "local_audio" },
        provider_status, description: None,
    }).await;
}

struct ShortRenderPlan {
    ranges: Vec<(f64, f64)>,
    treatment: Treatment,
    design: short_creative::Options,
    hook: String,
    source: &'static str,
    provider_status: &'static str,
    description: Option<Value>,
}

async fn render_short_result(
    state: &AutoEditState,
    session_id: &str,
    req: &AutoEditRequest,
    media: &MediaEngine,
    transcript: &[crate::types::TranscribedSegment],
    plan: ShortRenderPlan,
) {
    let ShortRenderPlan { ranges, treatment, design, hook, source, provider_status, description } = plan;
    let start = ranges[0].0;
    let end = ranges.last().unwrap().1;
    let has_visual_focus = design.focus_source_sec.is_some() || design.directed.as_ref().is_some_and(|design| !design.focus_source_secs.is_empty());
    let render_request = RenderRequest {
        video_path: req.video_path.clone(),
        output_dir: format!("output/{session_id}"),
        clips: vec![ClipSpec {
            index: 0,
            start_sec: start,
            end_sec: end,
            hook: hook.clone(),
            caption_theme: req.answers.caption_theme.clone().unwrap_or_default(),
            zoom_style: String::new(),
        }],
        width: 1080,
        height: 1920,
        fps: 30,
    };
    report(state, session_id, "render", 78.0, "بنجهز النسخة العمودية");
    match short_render::render_short(media, &render_request, transcript, &treatment, &ranges, &design).await {
        Ok(rendered) => finish(state, session_id, json!({
            "source": source,
            "provider_status": provider_status,
            "transcript_available": !transcript.is_empty(),
            "edit_plan": treatment,
            "source_ranges": ranges,
            "creative": {
                "style": rendered.creative.style,
                "title": rendered.creative.title,
                "accent_times": rendered.creative.beats,
                "original_music": rendered.creative.music,
                "designed_effects": rendered.creative.effects,
                "slow_motion": rendered.creative.slow_motion,
                "visual_provider_focus": has_visual_focus
            },
            "cuts": ranges.len().saturating_sub(1),
            "clips": [{
                "index": 0, "file_url": rendered.path, "duration_sec": rendered.duration_sec,
                "hook_text": hook,
                "has_captions": rendered.has_captions,
                "start_sec": start, "end_sec": end,
                "director": description
            }]
        })),
        Err(err) => {
            eprintln!("[short-render] {err:#}");
            fail(state, session_id, "تعذّر تصدير الفيديو. تأكد من صيغة الملف ومساحة التخزين.".into());
        }
    }
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
    let rendered = match pipeline.render(&render_req).await {
        Ok(paths) if !paths.is_empty() && paths.len() == render_req.clips.len()
            && paths.iter().all(|path| std::fs::metadata(path).is_ok_and(|entry| entry.is_file() && entry.len() > 0)) => paths,
        _ => {
            fail(&state, &session_id, "Could not render the requested clips".into());
            return;
        }
    };
    let compiled = if rendered.len() == 1 {
        rendered.first().cloned()
    } else {
        let path = format!("{}/compiled_final.mp4", render_req.output_dir);
        pipeline.compile(&rendered, &path).await.ok()
    };

    let clips = plan.clips.iter().zip(&rendered).map(|(clip, path)| {
        let mut result = json!(clip);
        result["file_url"] = json!(path);
        result
    }).collect::<Vec<_>>();
    let result = json!({
        "video_duration_sec": duration,
        "source": source,
        "reasoning": plan.reasoning,
        "clips": clips,
        "critic": {
            "score": verdict.score,
            "feedback": verdict.feedback,
            "issues": verdict.issues,
        },
        "rendered": rendered,
        "compiled": compiled,
    });
    finish(&state, &session_id, result);
}
