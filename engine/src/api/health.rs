/// Health check endpoint — liveness probe for the Rust engine.
use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

pub fn router() -> Router {
    Router::new().route("/health", get(health_handler))
}

async fn health_handler() -> Json<Value> {
    Json(json!({
        "status": "ok",
        "engine": "rust",
        "version": env!("CARGO_PKG_VERSION"),
    }))
}
