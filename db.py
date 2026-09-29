"""
db.py — thin, swappable database helper for Clippify v2.

Mirrors api.py's raw sqlite3 usage (no SQLAlchemy) but routes everything
through one module so the backend can be swapped via DATABASE_URL:

    sqlite:///./data/clippify.db   -> ./data/clippify.db
    postgres://user:pw@host/db     -> psycopg2 (if installed), else
                                      NotImplementedError

api.py / auth / billing can adopt this later by importing:
    from db import init_db, execute, query
and replacing `sqlite3.connect(DB_PATH)` blocks with execute()/query() calls.

query() returns list[dict] (column-name keyed rows) so callers stay identical
across sqlite and postgres backends.
"""

from __future__ import annotations

import json
import os
import sqlite3
from datetime import datetime, timezone
from urllib.parse import urlparse

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_DEFAULT_URL = "sqlite:///./data/clippify.db"


def get_db_path() -> str:
    """Parse DATABASE_URL into something connectable.

    "sqlite:///./x.db"      -> "./x.db"
    "sqlite:///C:/x/y.db"   -> "C:/x/y.db"
    "postgres://..."        -> raises NotImplementedError unless psycopg2 is
                               installed (then returns the DSN unchanged).
    """
    url = os.environ.get("DATABASE_URL", _DEFAULT_URL).strip()
    if not url:
        return _default_sqlite_path()

    if url.startswith("sqlite:///"):
        path = url[len("sqlite:///"):]
        if not path:
            raise ValueError(f"Empty sqlite path in DATABASE_URL: {url!r}")
        # Windows absolute ("sqlite:///C:/..." -> "C:/...") already fine.
        return os.path.normpath(path)

    if url.startswith(("postgres://", "postgresql://")):
        try:
            import psycopg2  # noqa: F401
        except ImportError:
            raise NotImplementedError(
                "DATABASE_URL points to Postgres but psycopg2 is not installed.\n"
                "Either:\n"
                "  1. Run the postgres service from docker-compose.yml "
                "(docker compose up postgres) and keep DATABASE_URL as-is after "
                "`pip install psycopg2-binary`, or\n"
                "  2. Use a local file: export DATABASE_URL=sqlite:///./data/clippify.db"
            )
        return url

    # Bare filesystem path convenience.
    if not urlparse(url).scheme:
        return os.path.normpath(url)

    raise ValueError(f"Unsupported DATABASE_URL scheme: {url!r}")


def _default_sqlite_path() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "clippify.db")


# ---------------------------------------------------------------------------
# Connections (per-call, mirroring api.py's style; cheap for sqlite)
# ---------------------------------------------------------------------------

_PG_CONN = None  # cached postgres connection


def _connect():
    path_or_dsn = get_db_path()

    if path_or_dsn.startswith("postgres"):
        global _PG_CONN
        if _PG_CONN is None or _PG_CONN.closed:
            import psycopg2
            _PG_CONN = psycopg2.connect(path_or_dsn)
            _PG_CONN.autocommit = True
        return _PG_CONN

    d = os.path.dirname(path_or_dsn)
    if d:
        os.makedirs(d, exist_ok=True)
    conn = sqlite3.connect(path_or_dsn)
    conn.row_factory = sqlite3.Row
    return conn


def _is_pg() -> bool:
    return get_db_path().startswith("postgres")


def _translate(sql: str) -> str:
    """? -> %s paramstyle translation for postgres drivers."""
    if _is_pg():
        return sql.replace("?", "%s")
    return sql


def _rows(cursor) -> list:
    cols = [d[0] for d in cursor.description] if cursor.description else []
    return [dict(zip(cols, row)) for row in cursor.fetchall()]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _cursor(conn):
    """sqlite3.Connection.execute() exists; psycopg2 needs an explicit cursor."""
    if _is_pg():
        return conn.cursor()
    return conn


def _exec(conn, sql: str, params: tuple):
    """Execute returning a real cursor for both backends."""
    if _is_pg():
        cur = conn.cursor()
        cur.execute(_translate(sql), tuple(params))
        return cur
    return conn.execute(_translate(sql), tuple(params))


def query(sql: str, params: tuple | list = ()) -> list:
    """Run a SELECT and return rows as list[dict]."""
    with closing_conn(_connect()) as conn:
        cur = _exec(conn, sql, params)
        return _rows(cur)


class closing_conn:
    """Context manager that closes plain connections but keeps cached pg conn."""

    def __init__(self, conn):
        self.conn = conn
        self._pg = _is_pg()

    def __enter__(self):
        return self.conn

    def __exit__(self, *exc):
        if not self._pg:
            self.conn.close()


def execute(sql: str, params: tuple | list = ()) -> int:
    """Run an INSERT/UPDATE/DELETE/DDL statement; commit; return rowcount."""
    with closing_conn(_connect()) as conn:
        cur = _exec(conn, sql, params)
        if not _is_pg():
            conn.commit()
        else:
            _PG_CONN.commit()
        return cur.rowcount


def executescript(script: str) -> None:
    """Multi-statement DDL helper (sqlite only semantics; pg splits on ';')."""
    if _is_pg():
        for stmt in [s.strip() for s in script.split(";") if s.strip()]:
            execute(stmt)
        return
    conn = _connect()
    try:
        conn.executescript(script)
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    """Ensure the data directory exists and schema is current."""
    path = get_db_path()
    if not path.startswith("postgres"):
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
    migrate()


def migrate() -> None:
    """
    v2 schema proof-of-layer. Intentionally does NOT touch api.py's legacy
    `sessions` table — this only adds sessions_v2 so auth/orchestrator code
    can adopt the layer incrementally:

        sessions_v2(session_id TEXT PRIMARY KEY, user_id TEXT, kind TEXT,
                    progress REAL, status TEXT, payload TEXT(json),
                    updated_at TEXT(iso-8601 UTC))
    """
    ddl = """
    CREATE TABLE IF NOT EXISTS sessions_v2 (
        session_id TEXT PRIMARY KEY,
        user_id    TEXT,
        kind       TEXT,
        progress   REAL DEFAULT 0,
        status     TEXT DEFAULT 'queued',
        payload    TEXT,
        updated_at TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_v2_user ON sessions_v2 (user_id);
    CREATE INDEX IF NOT EXISTS idx_sessions_v2_status ON sessions_v2 (status);
    """
    executescript(ddl)


# ---------------------------------------------------------------------------
# Convenience CRUD for sessions_v2 (what orchestrator/api will migrate to)
# ---------------------------------------------------------------------------

_UPSERT_SQLITE = """
INSERT INTO sessions_v2 (session_id, user_id, kind, progress, status, payload, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(session_id) DO UPDATE SET
    user_id=excluded.user_id, kind=excluded.kind, progress=excluded.progress,
    status=excluded.status, payload=excluded.payload, updated_at=excluded.updated_at
"""


def upsert_session(session_id: str, *, user_id: str | None = None, kind: str | None = None,
                   progress: float = 0.0, status: str = "queued",
                   payload: dict | list | None = None) -> None:
    now = datetime.now(timezone.utc).isoformat()
    blob = json.dumps(payload, ensure_ascii=False) if payload is not None else None
    if _is_pg():
        execute("""
            INSERT INTO sessions_v2 (session_id, user_id, kind, progress, status, payload, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (session_id) DO UPDATE SET
                user_id=EXCLUDED.user_id, kind=EXCLUDED.kind, progress=EXCLUDED.progress,
                status=EXCLUDED.status, payload=EXCLUDED.payload, updated_at=EXCLUDED.updated_at
        """, (session_id, user_id, kind, progress, status, blob, now))
    else:
        execute(_UPSERT_SQLITE, (session_id, user_id, kind, progress, status, blob, now))


def get_session_row(session_id: str) -> dict | None:
    rows = query("SELECT * FROM sessions_v2 WHERE session_id = ?", (session_id,))
    if rows and isinstance(rows[0].get("payload"), str):
        try:
            rows[0]["payload"] = json.loads(rows[0]["payload"])
        except (ValueError, TypeError):
            pass
    return rows[0] if rows else None


if __name__ == "__main__":
    init_db()
    print("db ready at:", get_db_path())
