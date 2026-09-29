//! Settings API — file-based persistence backed by `settings.json`.
use std::{
    env,
    fs,
    path::PathBuf,
    sync::Mutex,
};

use axum::{extract::State, routing::get, Json, Router};
use serde_json::{json, Value};

const SETTINGS_ENV: &str = "CLIPPIFY_SETTINGS";
const SETTINGS_FILE: &str = "settings.json";

struct SettingsState {
    path: PathBuf,
    lock: Mutex<()>,
}

fn default_settings() -> Value {
    json!({
        "theme": "system",
        "language": "en",
        "auto_save": true,
        "default_export": {
            "resolution": "1080x1920",
            "fps": 30,
            "format": "mp4"
        },
        "llm": {
            "provider": "gemini",
            "temperature": 0.5,
            "json_mode": true
        },
        "transcription": {
            "engine": "whisper.cpp",
            "model": "base"
        },
        "render": {
            "burn_captions": true,
            "caption_theme": "bold-yellow"
        }
    })
}

fn settings_path() -> PathBuf {
    let raw = env::var(SETTINGS_ENV).unwrap_or_else(|_| SETTINGS_FILE.to_string());
    PathBuf::from(raw)
}

fn load_settings(path: &PathBuf) -> Value {
    match fs::read_to_string(path) {
        Ok(raw) => match serde_json::from_str::<Value>(&raw) {
            Ok(v) if v.is_object() => v,
            _ => default_settings(),
        },
        Err(_) => default_settings(),
    }
}

fn save_settings(path: &PathBuf, value: &Value) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
    }
    let pretty = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    fs::write(path, pretty).map_err(|e| e.to_string())
}

async fn get_settings(State(state): State<std::sync::Arc<SettingsState>>) -> Json<Value> {
    let _guard = state.lock.lock().expect("settings lock poisoned");
    Json(load_settings(&state.path))
}

async fn post_settings(
    State(state): State<std::sync::Arc<SettingsState>>,
    Json(body): Json<Value>,
) -> Json<Value> {
    let _guard = state.lock.lock().expect("settings lock poisoned");
    if !body.is_object() {
        return Json(json!({"status": "error", "error": "settings payload must be a JSON object"}));
    }
    match save_settings(&state.path, &body) {
        Ok(()) => Json(json!({
            "status": "ok",
            "path": state.path.display().to_string(),
            "settings": body
        })),
        Err(err) => Json(json!({"status": "error", "error": err})),
    }
}

pub fn router() -> Router {
    let state = std::sync::Arc::new(SettingsState {
        path: settings_path(),
        lock: Mutex::new(()),
    });
    Router::new()
        .route("/settings", get(get_settings).post(post_settings))
        .with_state(state)
}
