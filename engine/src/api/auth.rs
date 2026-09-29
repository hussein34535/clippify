use std::sync::Mutex;

use axum::{
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use bcrypt::{hash, verify, DEFAULT_COST};
use chrono::{Duration, Utc};
use jsonwebtoken::{
    decode, encode, Algorithm, DecodingKey, EncodingKey, Header as JwtHeader, Validation,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::db;

const JWT_SECRET_ENV: &str = "JWT_SECRET";
const JWT_SECRET_DEFAULT: &str = "dev-secret";
const ACCESS_TOKEN_TTL_SECS: i64 = 30 * 60;
const REFRESH_TOKEN_TTL_SECS: i64 = 30 * 24 * 60 * 60;
const TOKEN_TYPE_BEARER: &str = "bearer";
const DUMMY_BCRYPT_HASH: &str = "$2a$12$R9h/cIPz0gi.URNNX3kh2OPST9/PgBkqquzi.Ss7KIUgO2t0jWMUW";

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    sub: String,
    #[serde(rename = "type")]
    token_type: String,
    iat: i64,
    exp: i64,
}

#[derive(Debug, Serialize)]
pub struct User {
    pub id: String,
    pub email: String,
    pub name: String,
    pub plan: String,
    pub credits_used: i64,
    pub credits_limit: i64,
}

struct StoredUser {
    id: String,
    email: String,
    name: String,
    password_hash: Option<String>,
    plan: String,
    credits_used: i64,
}

#[derive(Debug, Deserialize)]
struct RegisterIn {
    email: String,
    password: String,
    #[serde(default)]
    name: String,
}

#[derive(Debug, Deserialize)]
struct LoginIn {
    email: String,
    password: String,
}

#[derive(Debug, Deserialize)]
struct RefreshIn {
    refresh_token: String,
}

fn jwt_secret() -> String {
    std::env::var(JWT_SECRET_ENV).unwrap_or_else(|_| JWT_SECRET_DEFAULT.to_string())
}

fn encoding_key() -> EncodingKey {
    EncodingKey::from_secret(jwt_secret().as_bytes())
}

fn decoding_key() -> DecodingKey {
    DecodingKey::from_secret(jwt_secret().as_bytes())
}

fn plan_limit(plan: &str) -> i64 {
    match plan {
        "pro" => 30,
        "studio" => 300,
        _ => 3,
    }
}

fn user_out(user: &StoredUser) -> User {
    User {
        id: user.id.clone(),
        email: user.email.clone(),
        name: user.name.clone(),
        plan: user.plan.clone(),
        credits_used: user.credits_used,
        credits_limit: plan_limit(&user.plan),
    }
}

const USER_COLS: &str = "id, email, name, password_hash, plan, credits_used";

fn stored_user_from_row(row: &rusqlite::Row) -> rusqlite::Result<StoredUser> {
    Ok(StoredUser {
        id: row.get(0)?,
        email: row.get(1)?,
        name: row.get::<_, Option<String>>(2)?.unwrap_or_default(),
        password_hash: row.get(3)?,
        plan: row
            .get::<_, Option<String>>(4)?
            .unwrap_or_else(|| "free".into()),
        credits_used: row.get::<_, Option<i64>>(5)?.unwrap_or(0),
    })
}

fn find_user_by_id(conn: &Connection, id: &str) -> rusqlite::Result<Option<StoredUser>> {
    conn.query_row(
        &format!("SELECT {USER_COLS} FROM users WHERE id = ?1"),
        params![id],
        stored_user_from_row,
    )
    .optional()
}

fn find_user_by_email(conn: &Connection, email: &str) -> rusqlite::Result<Option<StoredUser>> {
    conn.query_row(
        &format!("SELECT {USER_COLS} FROM users WHERE email = ?1"),
        params![email],
        stored_user_from_row,
    )
    .optional()
}

fn create_token(user_id: &str, token_type: &str, ttl_secs: i64) -> Result<String, StatusCode> {
    let now = Utc::now();
    let claims = Claims {
        sub: user_id.to_string(),
        token_type: token_type.to_string(),
        iat: now.timestamp(),
        exp: (now + Duration::seconds(ttl_secs)).timestamp(),
    };
    encode(&JwtHeader::default(), &claims, &encoding_key())
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)
}

fn decode_access_token(token: &str) -> Result<String, StatusCode> {
    let validation = Validation::new(Algorithm::HS256);
    let data = decode::<Claims>(token, &decoding_key(), &validation)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;
    if data.claims.token_type != "access" || data.claims.sub.is_empty() {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(data.claims.sub)
}

fn decode_refresh_token(token: &str) -> Result<String, StatusCode> {
    let validation = Validation::new(Algorithm::HS256);
    let data = decode::<Claims>(token, &decoding_key(), &validation)
        .map_err(|_| StatusCode::UNAUTHORIZED)?;
    if data.claims.token_type != "refresh" || data.claims.sub.is_empty() {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(data.claims.sub)
}

fn issue_tokens(user_id: &str) -> Result<(String, String), StatusCode> {
    let access = create_token(user_id, "access", ACCESS_TOKEN_TTL_SECS)?;
    let refresh = create_token(user_id, "refresh", REFRESH_TOKEN_TTL_SECS)?;
    Ok((access, refresh))
}

pub fn router() -> Router {
    Router::new()
        .route("/register", post(register))
        .route("/login", post(login))
        .route("/refresh", post(refresh))
        .route("/me", get(me))
        .route("/logout", post(logout))
}

pub async fn require_user(headers: HeaderMap) -> Result<User, StatusCode> {
    let auth_header = headers
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let token = auth_header
        .strip_prefix("Bearer ")
        .or_else(|| auth_header.strip_prefix("bearer "))
        .map(str::trim)
        .filter(|token| !token.is_empty())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let user_id = decode_access_token(token)?;

    let conn_guard = db::global_db()
        .lock()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    find_user_by_id(&conn_guard, &user_id)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .map(|stored| user_out(&stored))
        .ok_or(StatusCode::UNAUTHORIZED)
}

fn auth_response(user: StoredUser) -> Result<Json<Value>, StatusCode> {
    let (access_token, refresh_token) = issue_tokens(&user.id)?;
    Ok(Json(json!({
        "user": user_out(&user),
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": TOKEN_TYPE_BEARER,
    })))
}

async fn register(Json(payload): Json<RegisterIn>) -> Result<Json<Value>, StatusCode> {
    let email = payload.email.trim().to_lowercase();
    if email.len() < 3 || email.len() > 255 || payload.password.len() < 6 || payload.name.len() > 120
    {
        return Err(StatusCode::UNPROCESSABLE_ENTITY);
    }

    let password = payload.password;
    let pw_hash = tokio::task::spawn_blocking(move || hash(&password, DEFAULT_COST))
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let user_id = Uuid::new_v4().to_string();
    let period_start = Utc::now().to_rfc3339();

    let conn_guard = db::global_db()
        .lock()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    if find_user_by_email(&conn_guard, &email)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .is_some()
    {
        return Err(StatusCode::CONFLICT);
    }

    conn_guard
        .execute(
            "INSERT INTO users (id, email, name, password_hash, plan, credits_used, period_start)
             VALUES (?1, ?2, ?3, ?4, 'free', 0, ?5)",
            params![user_id, email, payload.name, pw_hash, period_start],
        )
        .map_err(|err| {
            if err.to_string().contains("UNIQUE") {
                StatusCode::CONFLICT
            } else {
                StatusCode::INTERNAL_SERVER_ERROR
            }
        })?;

    let stored = find_user_by_id(&conn_guard, &user_id)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

    auth_response(stored)
}

async fn login(Json(payload): Json<LoginIn>) -> Result<Json<Value>, StatusCode> {
    let email = payload.email.trim().to_lowercase();
    let password = payload.password;

    let stored = {
        let conn_guard = db::global_db()
            .lock()
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        find_user_by_email(&conn_guard, &email)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
    };

    let Some(stored) = stored else {
        let _ = tokio::task::spawn_blocking(move || verify(&password, DUMMY_BCRYPT_HASH)).await;
        return Err(StatusCode::UNAUTHORIZED);
    };

    let stored_hash = stored.password_hash.clone().unwrap_or_default();
    let valid = tokio::task::spawn_blocking(move || verify(&password, &stored_hash))
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .unwrap_or(false);

    if !valid {
        return Err(StatusCode::UNAUTHORIZED);
    }

    auth_response(stored)
}

async fn refresh(Json(payload): Json<RefreshIn>) -> Result<Json<Value>, StatusCode> {
    let user_id = decode_refresh_token(payload.refresh_token.trim())?;

    let conn_guard = db::global_db()
        .lock()
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let stored = find_user_by_id(&conn_guard, &user_id)
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?
        .ok_or(StatusCode::UNAUTHORIZED)?;

    let (access_token, refresh_token) = issue_tokens(&stored.id)?;
    Ok(Json(json!({
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": TOKEN_TYPE_BEARER,
    })))
}

async fn me(headers: HeaderMap) -> Result<Json<Value>, StatusCode> {
    let user = require_user(headers).await?;
    Ok(Json(json!({ "user": user })))
}

async fn logout(headers: HeaderMap) -> Result<Json<Value>, StatusCode> {
    require_user(headers).await?;
    Ok(Json(json!({ "ok": true })))
}
