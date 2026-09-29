"""Fair-use admission queue for the free shared pool.

يحمي المجموعة المشتركة المجانية من الإغراق عند آلاف المستخدمين عبر:
  1. حصة يومية لكل مفتاح هوية (user-id أو IP) على قاعدة SQLite خفيفة.
  2. سجل ``active`` للوظائف الجارية لتقدير موقع الطابور (position estimate).

Environment switches
--------------------
FAIRQUEUE_ENABLED   "false" (default) → admit() يعيد ok دائماً و start/finish
                    no-op (persist-skip). اقلبها إلى "true"/"1" عند إطلاق
                    السحابة (W5 cloud flip) ليبدأ فرض الحصص فعلياً.
FAIRQUEUE_DB        مسار قاعدة البيانات (default: ./fairqueue.db).
FREE_DAILY_CAP      الحصة اليومية للمجاني (default: 3).

المفاتيح تُشتق عبر identity_key(): user id إن توفر، وإلا IP العميل،
وإلا 'anon'. الخطط المدفوعة (plan != 'free') تتجاوز الحصة لكن يُسجل
استخدامها في جدول usage على أي حال.
"""

import os
import sqlite3
import threading
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

DEFAULT_DB = "./fairqueue.db"

_lock = threading.Lock()
_conn: sqlite3.Connection = None
_active_path: str = None


@dataclass
class Decision:
    """نتيجة محاولة دخول وظيفة جديدة إلى المجموعة."""

    ok: bool
    reason: str = ""
    retry_after_sec: int = 0
    position: int = 0


def _enabled() -> bool:
    return os.environ.get("FAIRQUEUE_ENABLED", "false").strip().lower() in (
        "1", "true", "yes", "on",
    )


def _free_daily_cap() -> int:
    try:
        return int(os.environ.get("FREE_DAILY_CAP", "3"))
    except (TypeError, ValueError):
        return 3


def _utcnow() -> datetime:
    """Clock seam — الاختبارات تستبدلها لمحاكاة منتصف الليل."""
    return datetime.now(timezone.utc)


def _today(now: datetime = None) -> str:
    now = now or _utcnow()
    return now.date().isoformat()


def _seconds_until_midnight(now: datetime = None) -> int:
    now = now or _utcnow()
    tomorrow = (now + timedelta(days=1)).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    return max(0, int((tomorrow - now).total_seconds()))


def identity_key(user=None, request=None) -> str:
    """مفتاح الهوية: user id → client host/ip → 'anon'.

    يستخدم getattr آمناً لأن request.client في Starlette يعرّض
    ``host`` (وليس ``ip``)، وبعض الـ test doubles لا تعرّفه أصلاً.
    """
    if isinstance(user, dict):
        uid = user.get("id")
        if uid:
            return str(uid)
    client = getattr(request, "client", None)
    if client is not None:
        host = getattr(client, "host", None) or getattr(client, "ip", None)
        if host:
            return str(host)
    return "anon"


def _get_conn() -> sqlite3.Connection:
    """اتصال مفرد يعاد فتحه تلقائياً إذا تغيّر FAIRQUEUE_DB (لعزل الاختبارات)."""
    global _conn, _active_path
    path = os.environ.get("FAIRQUEUE_DB", DEFAULT_DB)
    with _lock:
        if _conn is not None and _active_path == path:
            return _conn
        if _conn is not None:
            try:
                _conn.close()
            except Exception:
                pass
        conn = sqlite3.connect(path, check_same_thread=False)
        conn.execute(
            "CREATE TABLE IF NOT EXISTS usage ("
            " idem TEXT NOT NULL,"
            " day TEXT NOT NULL,"
            " count INTEGER NOT NULL DEFAULT 0,"
            " PRIMARY KEY (idem, day)"
            ")"
        )
        conn.execute(
            "CREATE TABLE IF NOT EXISTS active ("
            " job_id TEXT PRIMARY KEY,"
            " key TEXT NOT NULL,"
            " started_at TEXT NOT NULL"
            ")"
        )
        conn.commit()
        _conn = conn
        _active_path = path
        return conn


def close() -> None:
    """أغلق الاتصال المخزَّن (تستخدمه الاختبارات لعزل tmp dbs)."""
    global _conn, _active_path
    with _lock:
        if _conn is not None:
            try:
                _conn.close()
            except Exception:
                pass
        _conn = None
        _active_path = None


def admit(key, plan: str = "free", *, cap: int = None) -> Decision:
    """قرار دخول: يفرض الحصة اليومية على المجاني ويسجل الاستخدام دائماً."""
    if not _enabled():
        return Decision(ok=True, reason="disabled")

    now = _utcnow()
    day = _today(now)
    limit = _free_daily_cap() if cap is None else cap

    conn = _get_conn()
    with _lock:
        row = conn.execute(
            "SELECT count FROM usage WHERE idem=? AND day=?", (key, day)
        ).fetchone()
        used = row[0] if row else 0
        active_n = conn.execute("SELECT COUNT(*) FROM active").fetchone()[0]
        position = active_n + _QUEUED_PLACEHOLDER

        if plan == "free" and used >= limit:
            return Decision(
                ok=False,
                reason="daily_cap_reached",
                retry_after_sec=_seconds_until_midnight(now),
                position=position,
            )

        if row:
            conn.execute(
                "UPDATE usage SET count=count+1 WHERE idem=? AND day=?", (key, day)
            )
        else:
            conn.execute(
                "INSERT INTO usage (idem, day, count) VALUES (?, ?, 1)", (key, day)
            )
        conn.commit()

    return Decision(ok=True, reason="ok", position=position)


_QUEUED_PLACEHOLDER = 0  # v1: لا طابور انتظار فعلي بعد


def start_job(job_id, key) -> None:
    """سجّل وظيفة جارية (no-op persist-skip عندما FAIRQUEUE_ENABLED=false)."""
    if not _enabled():
        return
    conn = _get_conn()
    with _lock:
        conn.execute(
            "INSERT OR REPLACE INTO active (job_id, key, started_at) VALUES (?, ?, ?)",
            (str(job_id), str(key), _utcnow().isoformat()),
        )
        conn.commit()


def finish_job(job_id) -> None:
    """أفرغ خانة الوظيفة الجارية."""
    if not _enabled():
        return
    conn = _get_conn()
    with _lock:
        conn.execute("DELETE FROM active WHERE job_id=?", (str(job_id),))
        conn.commit()


def position_estimate() -> int:
    """تقدير موقعك في الطابور = عدد الوظائف الجارية + queued_placeholder(0)."""
    if not _enabled():
        return 0
    return _get_conn().execute("SELECT COUNT(*) FROM active").fetchone()[0] + _QUEUED_PLACEHOLDER
