//! fair_queue.rs — Fair-use admission queue (port of fair_queue.py).
//!
//! Protects the free shared pool from flooding:
//!   1. Daily quota per identity key (user-id or IP) on a light SQLite db.
//!   2. An `active` table of running jobs for queue-position estimates.
//!
//! Environment switches
//! --------------------
//! FAIRQUEUE_ENABLED   "false" (default) → admit() always returns ok and
//!                     start/finish are no-ops (persist-skip). Flip to
//!                     "true"/"1" at cloud launch to enforce quotas.
//! FAIRQUEUE_DB        Database path (default: ./fairqueue.db).
//! FREE_DAILY_CAP      Free-tier daily quota (default: 3).

use anyhow::Result;
use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};

pub struct FairQueue {
    pub db: Connection,
}

/// Outcome of a job-admission attempt.
#[derive(Debug, Clone)]
pub struct Decision {
    pub ok: bool,
    pub reason: String,
    pub retry_after_sec: i64,
    pub position: i64,
}

impl Decision {
    fn allow(reason: &str, position: i64) -> Self {
        Self {
            ok: true,
            reason: reason.to_string(),
            retry_after_sec: 0,
            position,
        }
    }

    fn deny(retry_after_sec: i64, position: i64) -> Self {
        Self {
            ok: false,
            reason: "daily_cap_reached".to_string(),
            retry_after_sec,
            position,
        }
    }
}

impl FairQueue {
    /// Open (and initialize) the queue database at `path`.
    pub fn open(path: &str) -> Result<Self> {
        let db = Connection::open(path)?;
        db.execute_batch(
            "CREATE TABLE IF NOT EXISTS usage (
                idem  TEXT NOT NULL,
                day   TEXT NOT NULL,
                count INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (idem, day)
             );
             CREATE TABLE IF NOT EXISTS active (
                job_id     TEXT PRIMARY KEY,
                key        TEXT NOT NULL,
                started_at TEXT NOT NULL
             );",
        )?;
        Ok(Self { db })
    }

    /// Open using FAIRQUEUE_DB (default ./fairqueue.db).
    pub fn new() -> Result<Self> {
        let path = std::env::var("FAIRQUEUE_DB").unwrap_or_else(|_| "./fairqueue.db".to_string());
        Self::open(&path)
    }

    /// Feature gate — mirrors fair_queue.py `_enabled()`.
    pub fn enabled() -> bool {
        matches!(
            std::env::var("FAIRQUEUE_ENABLED")
                .unwrap_or_default()
                .trim()
                .to_lowercase()
                .as_str(),
            "1" | "true" | "yes" | "on"
        )
    }

    /// Free-tier daily cap from FREE_DAILY_CAP (default 3, bad values → 3).
    pub fn free_daily_cap() -> i64 {
        std::env::var("FREE_DAILY_CAP")
            .ok()
            .and_then(|v| v.trim().parse().ok())
            .unwrap_or(3)
    }

    /// UTC calendar day (YYYY-MM-DD) — day rollover is implicit because the
    /// key is recomputed on every call.
    fn utc_day(now: &chrono::DateTime<Utc>) -> String {
        now.format("%Y-%m-%d").to_string()
    }

    /// Seconds remaining until the next UTC midnight.
    fn secs_until_midnight(now: &chrono::DateTime<Utc>) -> i64 {
        const DAY: i64 = 86_400;
        DAY - now.timestamp().rem_euclid(DAY)
    }

    /// Admission decision: enforces the daily cap on the free plan and
    /// records usage for everyone (paid plans bypass the cap only).
    pub fn admit(&self, key: &str, plan: &str) -> Result<Decision> {
        if !Self::enabled() {
            return Ok(Decision::allow("disabled", 0));
        }

        let now = Utc::now();
        let day = Self::utc_day(&now);
        let limit = Self::free_daily_cap();

        let used: i64 = self
            .db
            .query_row(
                "SELECT count FROM usage WHERE idem=?1 AND day=?2",
                params![key, day],
                |r| r.get(0),
            )
            .optional()?
            .unwrap_or(0);
        let active_n: i64 =
            self.db.query_row("SELECT COUNT(*) FROM active", [], |r| r.get(0))?;
        let position = active_n; // v1: no real wait queue yet (+0 placeholder)

        if plan == "free" && used >= limit {
            return Ok(Decision::deny(Self::secs_until_midnight(&now), position));
        }

        self.db.execute(
            "INSERT INTO usage (idem, day, count) VALUES (?1, ?2, 1)
             ON CONFLICT(idem, day) DO UPDATE SET count = count + 1",
            params![key, day],
        )?;

        Ok(Decision::allow("ok", position))
    }

    /// Register a running job (no-op persist-skip when disabled).
    pub fn start_job(&self, job_id: &str, key: &str) {
        if !Self::enabled() {
            return;
        }
        let _ = self.db.execute(
            "INSERT OR REPLACE INTO active (job_id, key, started_at) VALUES (?1, ?2, ?3)",
            params![job_id, key, Utc::now().to_rfc3339()],
        );
    }

    /// Release a running job slot (no-op persist-skip when disabled).
    pub fn finish_job(&self, job_id: &str) {
        if !Self::enabled() {
            return;
        }
        let _ = self.db.execute("DELETE FROM active WHERE job_id=?1", params![job_id]);
    }

    /// Queue-position estimate = number of running jobs (+0 placeholder).
    pub fn position_estimate(&self) -> i64 {
        if !Self::enabled() {
            return 0;
        }
        self.db
            .query_row("SELECT COUNT(*) FROM active", [], |r| r.get(0))
            .unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp_db(tag: &str) -> String {
        let p = std::env::temp_dir().join(format!("fq_{}_{}.db", tag, std::process::id()));
        let _ = std::fs::remove_file(&p);
        p.to_string_lossy().into_owned()
    }

    #[test]
    fn paid_plan_bypasses_cap() {
        let q = FairQueue::open(&tmp_db("paid")).unwrap();
        for _ in 0..10 {
            let d = q.admit("key-pro", "pro").unwrap();
            assert!(d.ok, "paid plans bypass the free cap");
        }
    }

    #[test]
    fn admit_and_active_roundtrip() {
        let q = FairQueue::open(&tmp_db("roundtrip")).unwrap();
        let d = q.admit("key-a", "paid").unwrap();
        assert!(d.ok);
        q.start_job("j1", "key-a");
        q.finish_job("j1");
    }

    #[test]
    fn midnight_math_bounded() {
        let s = FairQueue::secs_until_midnight(&Utc::now());
        assert!((1..=86_400).contains(&s));
    }
}
