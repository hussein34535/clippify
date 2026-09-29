//! api/features.rs — Feature endpoints exposing the engine's standalone
//! modules (scenario, narrative, palette, motion, style_dna, trend,
//! sound_forge, brief_parser, hook_ab, attention_score, captions_v3,
//! audio_craft, magic_preview, fair_queue).
//!
//! Convention: every handler accepts JSON, calls one module function and
//! returns its result as JSON; failures come back as 500 + error message.
use std::sync::Arc;

use anyhow::{bail, Context, Result};
use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::{
    attention_score, audio_craft, brief_parser, captions_v3, fair_queue, hook_ab,
    llm::LlmBridge, media::MediaEngine, motion, narrative, palette, scenario, sound_forge,
    style_dna, trend,
};

#[derive(Clone)]
struct FeaturesState {
    llm: Arc<LlmBridge>,
}

pub fn router() -> Router {
    let state = FeaturesState {
        llm: Arc::new(LlmBridge::new()),
    };
    Router::new()
        .route("/scenarios", get(list_scenarios))
        .route("/scenario/:type", get(get_scenario))
        .route("/narrative", post(narrative_parse))
        .route("/palette", post(palette_from_video))
        .route("/motion-recipes", get(motion_recipes))
        .route("/motion-filter", post(motion_filter))
        .route("/style-dna/extract", post(style_dna_extract))
        .route("/trends/:niche", get(trends_niche))
        .route("/sound-forge", post(sound_forge_generate))
        .route("/brief/parse", post(brief_parse))
        .route("/hooks/variants", post(hook_variants))
        .route("/attention", post(attention_predict))
        .route("/captions/presets", get(caption_presets))
        .route("/captions/generate", post(captions_generate))
        .route("/audio-chain", post(audio_chain))
        .route("/preview-args", post(preview_args_route))
        .route("/fair-queue/admit", post(fair_queue_admit))
        .with_state(state)
}

// ── helpers ──────────────────────────────────────────────────────────────────

fn err_500(msg: impl std::fmt::Display) -> Response {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(json!({"status": "error", "error": msg.to_string()})),
    )
        .into_response()
}

type HandlerResult = Result<Json<Value>, Response>;

/// Parse a JSON `[[start_sec, end_sec, text], ...]` array into word triples.
fn parse_words(v: &Value) -> Result<Vec<(f64, f64, String)>> {
    let arr = v
        .as_array()
        .context("words must be an array of [start_sec, end_sec, text] triples")?;
    let mut out = Vec::with_capacity(arr.len());
    for w in arr {
        let triple = w.as_array().context("each word must be [start, end, text]")?;
        if triple.len() != 3 {
            bail!("each word must have exactly 3 elements [start, end, text]");
        }
        let start = triple[0].as_f64().context("word start must be a number")?;
        let end = triple[1].as_f64().context("word end must be a number")?;
        let text = triple[2]
            .as_str()
            .context("word text must be a string")?
            .to_string();
        out.push((start, end, text));
    }
    Ok(out)
}

// ── scenario ─────────────────────────────────────────────────────────────────

async fn list_scenarios() -> Json<Value> {
    Json(json!({"status": "ok", "scenarios": scenario::list_profiles()}))
}

async fn get_scenario(Path(content_type): Path<String>) -> Json<Value> {
    let profile = scenario::get_profile(&content_type);
    Json(json!({"status": "ok", "type": content_type, "profile": profile}))
}

// ── narrative ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct NarrativeBody {
    transcript: String,
}

async fn narrative_parse(
    State(st): State<FeaturesState>,
    Json(body): Json<NarrativeBody>,
) -> HandlerResult {
    let result = narrative::parse_narrative(&body.transcript, &st.llm)
        .await
        .map_err(|e| err_500(e))?;
    Ok(Json(json!({"status": "ok", "narrative": result})))
}

// ── palette ──────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PaletteBody {
    video_path: String,
    mood: String,
    #[serde(default = "default_palette_frames")]
    n_frames: usize,
}

fn default_palette_frames() -> usize {
    24
}

async fn palette_from_video(Json(body): Json<PaletteBody>) -> HandlerResult {
    let ffmpeg = MediaEngine::new().ffmpeg_path;
    let dominant = palette::try_extract_dominant_colors(&ffmpeg, &body.video_path, body.n_frames)
        .map_err(|e| err_500(e))?;
    let result = palette::generate_palette(&dominant, &body.mood);
    let dominant_json: Vec<Value> = dominant
        .iter()
        .map(|(color, pct)| json!({"color": color, "pct": pct}))
        .collect();
    Ok(Json(json!({
        "status": "ok",
        "mood": body.mood,
        "dominant": dominant_json,
        "palette": result,
    })))
}

// ── motion ───────────────────────────────────────────────────────────────────

async fn motion_recipes() -> Json<Value> {
    Json(json!({"status": "ok", "recipes": motion::get_recipes()}))
}

#[derive(Deserialize)]
struct MotionFilterBody {
    name: String,
    duration_sec: f64,
    #[serde(default)]
    params: Value,
}

async fn motion_filter(Json(body): Json<MotionFilterBody>) -> HandlerResult {
    let filter = motion::try_build_filter(&body.name, body.duration_sec, &body.params)
        .map_err(|e| err_500(e))?;
    Ok(Json(json!({
        "status": "ok",
        "name": body.name,
        "duration_sec": body.duration_sec,
        "filter": filter,
    })))
}

// ── style_dna ────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct StyleDnaBody {
    transcript: String,
    #[serde(default)]
    clip_metadata: Value,
}

async fn style_dna_extract(
    State(st): State<FeaturesState>,
    Json(body): Json<StyleDnaBody>,
) -> HandlerResult {
    let dna = style_dna::extract(&body.transcript, &body.clip_metadata, &st.llm)
        .await
        .map_err(|e| err_500(e))?;
    Ok(Json(json!({
        "status": "ok",
        "dna": dna,
        "prompt_fragment": style_dna::to_prompt(&dna),
    })))
}

// ── trend ────────────────────────────────────────────────────────────────────

async fn trends_niche(Path(niche): Path<String>) -> HandlerResult {
    let trends = trend::aggregate(&niche).await;
    Ok(Json(json!({
        "status": "ok",
        "niche": niche,
        "count": trends.len(),
        "trends": trends,
        "hashtags": trend::get_hashtags(&niche),
        "sounds": trend::get_sounds(&niche),
    })))
}

// ── sound_forge ──────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct SoundForgeBody {
    sound_type: String,
    #[serde(default)]
    duration_sec: f64,
    #[serde(default)]
    seed: Option<u64>,
    #[serde(default)]
    out_path: Option<String>,
}

async fn sound_forge_generate(Json(body): Json<SoundForgeBody>) -> HandlerResult {
    let mut forge = match body.seed {
        Some(seed) => sound_forge::SoundForge::with_seed(sound_forge::SAMPLE_RATE, seed),
        None => sound_forge::SoundForge::default(),
    };
    let samples = forge.generate(&body.sound_type, body.duration_sec);
    if samples.is_empty() {
        return Err(err_500(format!(
            "unknown sound_type {:?} or non-positive duration",
            body.sound_type
        )));
    }
    let duration = samples.len() as f64 / sound_forge::SAMPLE_RATE as f64;

    let mut wav_path = Value::Null;
    if let Some(path) = body.out_path.as_deref().filter(|p| !p.trim().is_empty()) {
        sound_forge::SoundForge::save_wav(path, &samples).map_err(|e| err_500(e))?;
        wav_path = json!(path);
    }

    Ok(Json(json!({
        "status": "ok",
        "sound_type": body.sound_type,
        "sample_rate": sound_forge::SAMPLE_RATE,
        "samples_count": samples.len(),
        "duration_sec": (duration * 1000.0).round() / 1000.0,
        "wav_path": wav_path,
        "samples": samples,
    })))
}

// ── brief_parser ─────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct BriefBody {
    brief_text: String,
}

async fn brief_parse(
    State(st): State<FeaturesState>,
    Json(body): Json<BriefBody>,
) -> HandlerResult {
    let settings = brief_parser::parse_brief(&body.brief_text, &st.llm)
        .await
        .map_err(|e| err_500(e))?;
    Ok(Json(json!({"status": "ok", "settings": settings})))
}

// ── hook_ab ──────────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct HookVariantsBody {
    transcript_segment: String,
    #[serde(default = "default_hook_count")]
    count: usize,
}

fn default_hook_count() -> usize {
    4
}

async fn hook_variants(
    State(st): State<FeaturesState>,
    Json(body): Json<HookVariantsBody>,
) -> HandlerResult {
    let variants = hook_ab::generate_variants(&body.transcript_segment, body.count, &st.llm)
        .await
        .map_err(|e| err_500(e))?;
    Ok(Json(json!({"status": "ok", "variants": variants})))
}

// ── attention_score ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct AttentionBody {
    words: Value,
    #[serde(default)]
    video_duration: f64,
}

async fn attention_predict(Json(body): Json<AttentionBody>) -> HandlerResult {
    let words = parse_words(&body.words).map_err(|e| err_500(e))?;
    let duration = if body.video_duration > 0.0 {
        body.video_duration
    } else {
        words.iter().map(|w| w.1).fold(0.0f64, f64::max)
    };
    let curve = attention_score::predict_attention(&words, duration);
    let overall = attention_score::overall_score(&curve);
    let recs = attention_score::recommendations(&curve);
    Ok(Json(json!({
        "status": "ok",
        "video_duration": duration,
        "curve": curve,
        "overall_score": overall,
        "recommendations": recs,
    })))
}

// ── captions_v3 ──────────────────────────────────────────────────────────────

async fn caption_presets() -> Json<Value> {
    Json(json!({"status": "ok", "presets": captions_v3::get_presets()}))
}

#[derive(Deserialize)]
struct CaptionsGenerateBody {
    words: Value,
    #[serde(default = "default_caption_preset")]
    preset: String,
    #[serde(default = "default_video_width")]
    video_width: u32,
    #[serde(default = "default_video_height")]
    video_height: u32,
}

fn default_caption_preset() -> String {
    "clean_white".to_string()
}
fn default_video_width() -> u32 {
    1080
}
fn default_video_height() -> u32 {
    1920
}

async fn captions_generate(Json(body): Json<CaptionsGenerateBody>) -> HandlerResult {
    let words = parse_words(&body.words).map_err(|e| err_500(e))?;
    let preset = captions_v3::preset_by_name(&body.preset);
    let ass = captions_v3::generate_ass_subtitles(
        &words,
        &preset,
        body.video_width,
        body.video_height,
    );
    Ok(Json(json!({
        "status": "ok",
        "preset": preset.name,
        "events": ass.matches("Dialogue:").count(),
        "ass": ass,
    })))
}

// ── audio_craft ──────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct AudioChainBody {
    platform: String,
    #[serde(default)]
    options: Option<audio_craft::AudioOptions>,
}

async fn audio_chain(Json(body): Json<AudioChainBody>) -> HandlerResult {
    let options = body.options.unwrap_or_default();
    let chain = audio_craft::build_audio_filter_chain(&body.platform, options);
    Ok(Json(json!({
        "status": "ok",
        "platform": body.platform,
        "target_lufs": audio_craft::platform_target_lufs(&body.platform),
        "filter_chain": chain,
        "loudness_normalize_args": audio_craft::loudness_normalize_args(&body.platform),
    })))
}

// ── magic_preview ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct PreviewArgsBody {
    video_path: String,
    start_sec: f64,
    end_sec: f64,
    out_path: String,
}

async fn preview_args_route(Json(body): Json<PreviewArgsBody>) -> HandlerResult {
    let ffmpeg = MediaEngine::new().ffmpeg_path;
    let args = crate::magic_preview::preview_args(
        &ffmpeg,
        &body.video_path,
        body.start_sec,
        body.end_sec,
        &body.out_path,
    );
    Ok(Json(json!({"status": "ok", "args": args})))
}

// ── fair_queue ───────────────────────────────────────────────────────────────

#[derive(Deserialize)]
struct FairQueueAdmitBody {
    key: String,
    plan: String,
}

async fn fair_queue_admit(Json(body): Json<FairQueueAdmitBody>) -> HandlerResult {
    // rusqlite is sync: open + admit inside one blocking section with no
    // awaits in between so the !Send connection never crosses an await.
    let outcome = {
        let queue =
            fair_queue::FairQueue::new().map_err(|e| err_500(format!("fairqueue db: {e}")))?;
        queue
            .admit(&body.key, &body.plan)
            .map(|d| (d.ok, d.reason, d.retry_after_sec, d.position))
            .map_err(|e| err_500(e))?
    };
    let (ok, reason, retry_after_sec, position) = outcome;
    Ok(Json(json!({
        "status": "ok",
        "admitted": ok,
        "reason": reason,
        "retry_after_sec": retry_after_sec,
        "position": position,
    })))
}
