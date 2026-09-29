/// Providers API — LLM cascade status + in-memory API key vault.
use axum::{
    extract::{Path, State},
    routing::{delete, get, post},
    Json, Router,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

pub struct ProviderState {
    pub bridge: tokio::sync::Mutex<crate::llm::LlmBridge>,
    pub keys: Mutex<HashMap<String, String>>,
}

type SharedState = Arc<ProviderState>;

pub fn router() -> Router {
    let state: SharedState = Arc::new(ProviderState {
        bridge: tokio::sync::Mutex::new(crate::llm::LlmBridge::new()),
        keys: Mutex::new(HashMap::new()),
    });
    Router::new()
        .route("/status", get(status))
        .route("/key", post(set_key))
        .route("/key/:provider", delete(delete_key))
        .with_state(state)
}

async fn status(State(state): State<SharedState>) -> Json<Value> {
    let bridge = state.bridge.lock().await;
    let providers = bridge.status().await;
    Json(json!({"status": "ok", "providers": providers}))
}

#[derive(Deserialize)]
pub struct KeyRequest {
    pub provider: String,
    pub key: String,
}

async fn set_key(State(state): State<SharedState>, Json(req): Json<KeyRequest>) -> Json<Value> {
    let provider = req.provider.trim().to_lowercase();
    if provider.is_empty() || req.key.trim().is_empty() {
        return Json(json!({"status": "error", "error": "provider and key are required"}));
    }
    match provider.as_str() {
        "gemini" => state.bridge.lock().await.gemini_key = req.key.clone(),
        "groq" => state.bridge.lock().await.groq_key = req.key.clone(),
        _ => {}
    }
    state
        .keys
        .lock()
        .expect("keys lock poisoned")
        .insert(provider.clone(), req.key);
    Json(json!({"status": "ok", "provider": provider}))
}

async fn delete_key(
    State(state): State<SharedState>,
    Path(provider): Path<String>,
) -> Json<Value> {
    let provider = provider.trim().to_lowercase();
    let removed = state
        .keys
        .lock()
        .expect("keys lock poisoned")
        .remove(&provider)
        .is_some();
    Json(json!({"status": "ok", "provider": provider, "removed": removed}))
}
