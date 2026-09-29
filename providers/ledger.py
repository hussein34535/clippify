"""
Usage ledger — same SQLite db as providers.store (providers.db).

Table:
    daily(provider TEXT, day TEXT, used INT, PRIMARY KEY(provider, day))
    cooldown(provider TEXT PK, until TEXT)

Daily reset is implicit: rows are keyed by UTC date string "YYYY-MM-DD",
so a new UTC day simply starts counting from zero. Cooldowns expire by
comparing the stored ISO timestamp against now.
"""

import json
import os
from datetime import datetime, timezone

from providers import store

# Default free-tier daily caps (override via JSON env PROVIDER_CAPS).
DEFAULT_CAPS = {"gemini_free": 1500, "groq_free": 200, "ollama": 10**9}

# Provider id → default cap key.
_CAP_KEY = {"gemini": "gemini_free", "groq": "groq_free", "ollama": "ollama"}

_SCHEMA = """
CREATE TABLE IF NOT EXISTS daily (
    provider TEXT NOT NULL,
    day      TEXT NOT NULL,
    used     INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (provider, day)
);
CREATE TABLE IF NOT EXISTS cooldown (
    provider TEXT PRIMARY KEY,
    until    TEXT NOT NULL
);
"""


def _connect():
    conn = store._connect()
    conn.executescript(_SCHEMA)
    return conn


def _today() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def caps() -> dict:
    """Effective caps: defaults merged with PROVIDER_CAPS JSON env overrides."""
    caps = dict(DEFAULT_CAPS)
    raw = os.getenv("PROVIDER_CAPS", "").strip()
    if raw:
        try:
            caps.update(json.loads(raw))
        except ValueError:
            pass  # Malformed JSON → keep defaults.
    return caps


def cap_for(provider: str) -> int:
    """Daily cap for provider ('gemini'→gemini_free alias); unknown providers are generous."""
    effective = caps()
    return int(effective.get(provider, effective.get(_CAP_KEY.get(provider, ""), 10**9)))


def add_used(provider: str, amount: int = 1) -> None:
    """Count successful calls for today (UTC)."""
    with _connect() as conn:
        conn.execute(
            "INSERT INTO daily(provider, day, used) VALUES(?,?,?) "
            "ON CONFLICT(provider, day) DO UPDATE SET used = used + excluded.used",
            (provider, _today(), amount),
        )


def used_today(provider: str) -> int:
    with _connect() as conn:
        row = conn.execute(
            "SELECT used FROM daily WHERE provider=? AND day=?", (provider, _today())
        ).fetchone()
    return int(row[0]) if row else 0


def available(provider: str) -> int:
    """cap - used_today (never negative)."""
    return max(0, cap_for(provider) - used_today(provider))


def set_cooldown(provider: str, until_iso: str) -> None:
    """Block provider until the ISO timestamp (typically next UTC midnight)."""
    with _connect() as conn:
        conn.execute(
            "INSERT INTO cooldown(provider, until) VALUES(?,?) "
            "ON CONFLICT(provider) DO UPDATE SET until=excluded.until",
            (provider, until_iso),
        )


def cooldown_until(provider: str):
    """ISO cooldown end or None when not cooling / already expired."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT until FROM cooldown WHERE provider=?", (provider,)
        ).fetchone()
    if not row:
        return None
    try:
        end = datetime.fromisoformat(row[0])
        if end.tzinfo is None:
            end = end.replace(tzinfo=timezone.utc)
    except ValueError:
        return None
    if datetime.now(timezone.utc) >= end:
        return None
    return row[0]


def clear_cooldown(provider: str) -> None:
    with _connect() as conn:
        conn.execute("DELETE FROM cooldown WHERE provider=?", (provider,))
