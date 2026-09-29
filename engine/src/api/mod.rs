pub mod auth;
pub mod auto_edit;
pub mod features;
pub mod health;
pub mod legacy_endpoints;
pub mod media_endpoints;
pub mod providers;
pub mod settings;
pub mod system;

pub fn api_router() -> axum::Router {
    let auto_edit_state = auto_edit::AutoEditState::new();
    axum::Router::new()
        .nest("/auth", auth::router())
        .merge(media_endpoints::router())
        .merge(auto_edit::router(auto_edit_state.clone()))
        .merge(legacy_endpoints::router(auto_edit_state))
        .merge(features::router())
        .merge(system::router())
        .merge(health::router())
        .merge(providers::router())
        .merge(settings::router())
}
