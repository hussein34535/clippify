"""
Auth service — user storage (SQLite, stdlib sqlite3 like api.py sessions) + JWT helpers.

DB path: env CLIPPIFY_USERS_DB (tests point this at a tmp dir), default ./users.db.
Tokens: python-jose HS256. Access 30min / Refresh 30d.
Hashing: passlib[bcrypt].
"""

import os
import sqlite3
import time
import uuid
from datetime import datetime, timedelta, timezone

from jose import ExpiredSignatureError, JWTError, jwt
from passlib.context import CryptContext

# ── Config ────────────────────────────────────────────────────────────────────
JWT_SECRET = os.getenv("JWT_SECRET", "dev-secret-change-me")
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = 30
REFRESH_TOKEN_DAYS = 30

USERS_DB_ENV = "CLIPPIFY_USERS_DB"
USERS_DB_DEFAULT = "./users.db"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class AuthError(Exception):
    """Invalid or expired token."""


class DuplicateEmailError(Exception):
    pass


# ── Time helpers ──────────────────────────────────────────────────────────────
def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().isoformat()


def parse_iso(value) -> datetime:
    if isinstance(value, datetime):
        dt = value
    else:
        dt = datetime.fromisoformat(str(value))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


# ── DB ────────────────────────────────────────────────────────────────────────
def _db_path() -> str:
    return os.getenv(USERS_DB_ENV, USERS_DB_DEFAULT)


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(_db_path())
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id            TEXT PRIMARY KEY,
            email         TEXT UNIQUE NOT NULL,
            name          TEXT,
            password_hash TEXT,
            plan          TEXT DEFAULT 'free',
            credits_used  INTEGER DEFAULT 0,
            period_start  TEXT
        )
    """)
    conn.commit()
    return conn


def _row_to_user(row) -> dict:
    return {
        "id": row["id"],
        "email": row["email"],
        "name": row["name"] or "",
        "plan": row["plan"] or "free",
        "credits_used": int(row["credits_used"] or 0),
        "period_start": row["period_start"],
    }


# ── Password hashing ──────────────────────────────────────────────────────────
def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return pwd_context.verify(plain, hashed)
    except Exception:
        return False


# ── User CRUD ─────────────────────────────────────────────────────────────────
def create_user(email: str, password: str, name: str = "") -> dict:
    conn = get_conn()
    try:
        existing = conn.execute(
            "SELECT id FROM users WHERE email = ?", (email.strip().lower(),)
        ).fetchone()
        if existing:
            raise DuplicateEmailError(email)
        user_id = str(uuid.uuid4())
        conn.execute(
            """
            INSERT INTO users (id, email, name, password_hash, plan, credits_used, period_start)
            VALUES (?, ?, ?, ?, 'free', 0, ?)
            """,
            (user_id, email.strip().lower(), name, hash_password(password), utc_now_iso()),
        )
        conn.commit()
        return get_user_by_id(user_id)
    finally:
        conn.close()


def get_user_by_email(email: str):
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT * FROM users WHERE email = ?", (email.strip().lower(),)
        ).fetchone()
        return _row_to_user(row) if row else None
    finally:
        conn.close()


def get_user_by_id(user_id: str):
    if not user_id:
        return None
    conn = get_conn()
    try:
        row = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        return _row_to_user(row) if row else None
    finally:
        conn.close()


def authenticate(email: str, password: str):
    user = get_user_by_email(email)
    if not user:
        # burn comparable time so missing-user doesn't leak via timing
        hash_password(password)
        return None
    conn = get_conn()
    try:
        row = conn.execute(
            "SELECT password_hash FROM users WHERE id = ?", (user["id"],)
        ).fetchone()
    finally:
        conn.close()
    if not row or not verify_password(password, row["password_hash"] or ""):
        return None
    return user


def update_usage(user_id: str, credits_used: int = None, period_start: str = None):
    conn = get_conn()
    try:
        if credits_used is not None and period_start is not None:
            conn.execute(
                "UPDATE users SET credits_used = ?, period_start = ? WHERE id = ?",
                (int(credits_used), period_start, user_id),
            )
        elif credits_used is not None:
            conn.execute(
                "UPDATE users SET credits_used = ? WHERE id = ?",
                (int(credits_used), user_id),
            )
        elif period_start is not None:
            conn.execute(
                "UPDATE users SET period_start = ? WHERE id = ?",
                (period_start, user_id),
            )
        conn.commit()
    finally:
        conn.close()


def set_plan(user_id: str, plan: str, reset_period: bool = True) -> dict:
    conn = get_conn()
    try:
        if reset_period:
            conn.execute(
                "UPDATE users SET plan = ?, credits_used = 0, period_start = ? WHERE id = ?",
                (plan, utc_now_iso(), user_id),
            )
        else:
            conn.execute("UPDATE users SET plan = ? WHERE id = ?", (plan, user_id))
        conn.commit()
    finally:
        conn.close()
    return get_user_by_id(user_id)


# ── JWT ───────────────────────────────────────────────────────────────────────
def _create_token(user_id: str, token_type: str, expires_delta: timedelta) -> str:
    now = int(time.time())
    payload = {
        "sub": user_id,
        "type": token_type,
        "iat": now,
        "exp": now + int(expires_delta.total_seconds()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def create_access_token(user_id: str) -> str:
    return _create_token(user_id, "access", timedelta(minutes=ACCESS_TOKEN_MINUTES))


def create_refresh_token(user_id: str) -> str:
    return _create_token(user_id, "refresh", timedelta(days=REFRESH_TOKEN_DAYS))


def decode_token(token: str, expected_type: str = "access") -> dict:
    """Decode + validate a JWT; raises AuthError on anything suspicious."""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except ExpiredSignatureError:
        raise AuthError("token_expired")
    except JWTError:
        raise AuthError("invalid_token")
    if payload.get("type") != expected_type:
        raise AuthError("invalid_token_type")
    if not payload.get("sub"):
        raise AuthError("missing_subject")
    return payload
