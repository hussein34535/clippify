"""
BYOK key store — SQLite providers.db (env CLIPPIFY_PROVIDERS_DB, default ./providers.db).

Table:
    byok(provider TEXT PK, key_enc BLOB, added_at TEXT)

Keys are encrypted with Fernet (cryptography pkg) derived from APP_SECRET:
sha256(secret) → base64 urlsafe. If `cryptography` is not installed we fall back
to base64-encoded plaintext so local dev never breaks — documented and only for dev;
install `cryptography` in production.
"""

import base64
import hashlib
import os
import sqlite3
from datetime import datetime, timezone

_SCHEMA = """
CREATE TABLE IF NOT EXISTS byok (
    provider TEXT PRIMARY KEY,
    key_enc  BLOB NOT NULL,
    added_at TEXT NOT NULL
);
"""

_DEFAULT_SECRET = "clippify-dev-secret"


def db_path() -> str:
    return os.getenv("CLIPPIFY_PROVIDERS_DB", "./providers.db")


def _connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db_path())
    conn.execute(_SCHEMA)
    return conn


def _fernet():
    """Fernet instance or None when cryptography is missing (dev plaintext fallback)."""
    try:
        from cryptography.fernet import Fernet
    except ImportError:
        return None
    secret = os.getenv("APP_SECRET", _DEFAULT_SECRET)
    key = base64.urlsafe_b64encode(hashlib.sha256(secret.encode()).digest())
    return Fernet(key)


def set_key(provider: str, api_key: str) -> None:
    """Store (or overwrite) a user's own API key for provider."""
    if not provider or not api_key:
        raise ValueError("provider and api_key must be non-empty")
    f = _fernet()
    if f is not None:
        blob = f.encrypt(api_key.encode())
    else:
        # Dev fallback: base64 plaintext (no cryptography installed).
        blob = base64.b64encode(api_key.encode())
    now = datetime.now(timezone.utc).isoformat()
    with _connect() as conn:
        conn.execute(
            "INSERT INTO byok(provider, key_enc, added_at) VALUES(?,?,?) "
            "ON CONFLICT(provider) DO UPDATE SET key_enc=excluded.key_enc, added_at=excluded.added_at",
            (provider, sqlite3.Binary(blob), now),
        )


def get_key(provider: str):
    """Decrypted API key string or None."""
    with _connect() as conn:
        row = conn.execute(
            "SELECT key_enc FROM byok WHERE provider=?", (provider,)
        ).fetchone()
    if not row:
        return None
    blob = bytes(row[0])
    f = _fernet()
    if f is not None:
        try:
            return f.decrypt(blob).decode()
        except Exception:
            pass  # Written in dev-plaintext mode before cryptography was installed.
    try:
        return base64.b64decode(blob).decode()
    except Exception:
        return None


def delete_key(provider: str) -> bool:
    """Remove the stored key; True when a row was deleted."""
    with _connect() as conn:
        cur = conn.execute("DELETE FROM byok WHERE provider=?", (provider,))
    return cur.rowcount > 0


def list() -> list:
    """Providers that have a stored BYOK key."""
    with _connect() as conn:
        rows = conn.execute("SELECT provider FROM byok ORDER BY added_at").fetchall()
    return [r[0] for r in rows]
