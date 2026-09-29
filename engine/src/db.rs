use std::{env, fs, path::Path, sync::{Arc, Mutex, OnceLock}};

use anyhow::{Context, Result};
use rusqlite::Connection;

pub type Db = Arc<Mutex<Connection>>;

const DB_ENV: &str = "CLIPPIFY_DB";
const DB_DEFAULT: &str = "./clippify.db";

pub fn db_path() -> String {
    env::var(DB_ENV).unwrap_or_else(|_| DB_DEFAULT.to_string())
}

pub fn init_db(path: &str) -> Result<Connection> {
    if let Some(parent) = Path::new(path).parent() {
        if !parent.as_os_str().is_empty() {
            let _ = fs::create_dir_all(parent);
        }
    }

    let conn = Connection::open(path).with_context(|| format!("open sqlite db at {path}"))?;

    conn.execute_batch(
        "PRAGMA journal_mode = WAL;

         CREATE TABLE IF NOT EXISTS users (
             id            TEXT PRIMARY KEY,
             email         TEXT UNIQUE NOT NULL,
             name          TEXT,
             password_hash TEXT,
             plan          TEXT DEFAULT 'free',
             credits_used  INTEGER DEFAULT 0,
             period_start  TEXT
         );

         CREATE TABLE IF NOT EXISTS sessions (
             session_id TEXT PRIMARY KEY,
             progress   REAL,
             status     TEXT,
             results    TEXT,
             errors     TEXT
         );",
    )
    .context("initialize clippify schema")?;

    Ok(conn)
}

static GLOBAL_DB: OnceLock<Db> = OnceLock::new();

pub fn global_db() -> &'static Db {
    GLOBAL_DB.get_or_init(|| {
        let path = db_path();
        match init_db(&path) {
            Ok(conn) => Arc::new(Mutex::new(conn)),
            Err(err) => {
                eprintln!("clippify: failed to init db at {path}: {err}; falling back to in-memory db");
                let conn =
                    Connection::open_in_memory().expect("failed to open in-memory sqlite db");
                Arc::new(Mutex::new(conn))
            }
        }
    })
}
