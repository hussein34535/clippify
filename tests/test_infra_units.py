"""
Unit tests for the AGENT-4 infra layer: db.py, storage.py, jobs.queue.

Env is set via monkeypatch BEFORE importing/reloading modules
(importlib.reload pattern), so no real S3/Redis/postgres is needed.
"""

import importlib
import os
import time

import pytest


# ---------------------------------------------------------------------------
# Helpers / fixtures
# ---------------------------------------------------------------------------


def _reload(name):
    return importlib.reload(importlib.import_module(name))


@pytest.fixture
def infra(tmp_path, monkeypatch):
    """Fresh db/storage/jobs modules pointed at tmp dirs, fallback mode."""
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{(tmp_path / 'test.db').as_posix()}")
    monkeypatch.setenv("STORAGE_DIR", str(tmp_path / "storage"))
    monkeypatch.delenv("S3_BUCKET", raising=False)
    monkeypatch.delenv("REDIS_URL", raising=False)
    monkeypatch.setenv("MAX_WORKERS", "1")
    monkeypatch.delenv("PUBLIC_BASE_URL", raising=False)

    db_mod = _reload("db")
    st_mod = _reload("storage")
    q_mod = _reload("jobs.queue")
    q_mod.reset_for_tests()
    yield {"db": db_mod, "storage": st_mod, "queue": q_mod, "tmp": tmp_path}
    q_mod.reset_for_tests()


def _wait_for(q_mod, job_id, statuses, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        snap = q_mod.status(job_id) or {}
        if snap.get("status") in statuses:
            return snap
        time.sleep(0.02)
    raise AssertionError(f"job {job_id} did not reach {statuses}: {q_mod.status(job_id)}")


# ---------------------------------------------------------------------------
# db.py
# ---------------------------------------------------------------------------


def test_sqlite_url_parsing(tmp_path, monkeypatch):
    monkeypatch.setenv("DATABASE_URL", "sqlite:///./x.db")
    db = _reload("db")
    assert db.get_db_path() == os.path.normpath("./x.db")

    win_abs = f"sqlite:///{(tmp_path / 'w.db').as_posix()}"
    monkeypatch.setenv("DATABASE_URL", win_abs)
    assert db.get_db_path() == str((tmp_path / "w.db"))


def test_postgres_url_without_driver_raises(monkeypatch):
    try:
        import psycopg2  # noqa: F401
        pytest.skip("psycopg2 installed — NotImplementedError path not applicable")
    except ImportError:
        pass
    monkeypatch.setenv("DATABASE_URL", "postgres://user:pw@localhost:5432/clippify")
    db = _reload("db")
    with pytest.raises(NotImplementedError, match="psycopg2|Docker|docker"):
        db.init_db()


def test_db_init_migrate_and_roundtrip(infra):
    db = infra["db"]
    db.init_db()  # creates dir + sessions_v2 schema

    db.execute(
        "INSERT INTO sessions_v2 (session_id, user_id, kind, progress, status, payload)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        ("s1", "u9", "auto-edit", 42.0, "running", '{"n":5}'),
    )
    rows = db.query("SELECT * FROM sessions_v2 WHERE session_id = ?", ("s1",))
    assert len(rows) == 1
    row = rows[0]
    assert row["session_id"] == "s1"
    assert row["user_id"] == "u9"
    assert row["progress"] == pytest.approx(42.0)

    # convenience upsert helper (ON CONFLICT path)
    db.upsert_session("s1", user_id="u9", kind="auto-edit", progress=90.0,
                      status="done", payload={"clips": 5})
    got = db.get_session_row("s1")
    assert got["status"] == "done"
    assert got["payload"] == {"clips": 5}
    assert got["updated_at"]  # iso timestamp written


# ---------------------------------------------------------------------------
# storage.py
# ---------------------------------------------------------------------------


def test_storage_local_roundtrip(infra, tmp_path):
    st = infra["storage"]
    src = tmp_path / "source.mp4"
    src.write_bytes(b"\x00\x01CLIPPIFY-TEST")

    url = st.put_file(str(src), "videos/a/b.mp4")
    assert url.endswith("/files/videos/a/b.mp4")  # local mode relative url
    assert not url.startswith(("http://", "https://"))

    # public_url accepts keys or stored paths too
    assert st.public_url("videos/a/b.mp4") == url

    # open_url round-trips through the local backend
    local = st.open_url(url)
    assert os.path.exists(local)
    with open(local, "rb") as fh:
        assert fh.read() == b"\x00\x01CLIPPIFY-TEST"

    # delete removes only the stored copy
    st.delete("videos/a/b.mp4")
    assert not os.path.exists(local)
    with pytest.raises(FileNotFoundError):
        st.open_url(url)


def test_presign_put_local_mode(infra):
    st = infra["storage"]
    out = st.presign_put("uploads/x.mp4")
    assert out.startswith("/api/upload/local/uploads/x.mp4")


# ---------------------------------------------------------------------------
# jobs.queue (fallback mode)
# ---------------------------------------------------------------------------


def test_queue_fallback_sync_fn_status(infra):
    q = infra["queue"]
    jid = q.enqueue(lambda a, b: a + b, 2, 3)
    assert isinstance(jid, str) and jid

    snap = _wait_for(q, jid, {"done"})
    assert snap["result"] == 5
    assert snap["error"] is None


def test_queue_named_function_via_registry(infra):
    q = infra["queue"]

    @q.register("echo_job")
    def echo(x):  # pragma: no cover - runs in worker thread
        return f"echo-{x}"

    jid = q.enqueue("echo_job", "hi")
    snap = _wait_for(q, jid, {"done"})
    assert snap["result"] == "echo-hi"


def test_queue_unknown_name_rejected(infra):
    q = infra["queue"]
    with pytest.raises(KeyError):
        q.enqueue("never_registered_job")


def test_queue_cooperative_cancel(infra):
    q = infra["queue"]
    jid = "cancel-test-job"

    def long_loop():
        deadline = time.time() + 10
        while time.time() < deadline:
            q.check_cancel(jid)  # raises CancelledError when flagged
            time.sleep(0.01)
        return "finished"

    q.enqueue(long_loop, job_id=jid)
    _wait_for(q, jid, {"running"}, timeout=10.0)
    assert q.should_cancel(jid) is False

    assert q.cancel(jid) is True
    snap = _wait_for(q, jid, {"cancelled"}, timeout=5.0)
    assert snap["status"] == "cancelled"
    assert q.should_cancel(jid) is True


def test_queue_error_captured(infra):
    q = infra["queue"]
    jid = q.enqueue(lambda: 1 / 0)
    snap = _wait_for(q, jid, {"error"})
    assert "ZeroDivisionError" in (snap["error"] or "")


def test_worker_main_no_redis_is_noop(monkeypatch):
    """python -m jobs must exit cleanly (return 0) when REDIS_URL is unset."""
    import jobs.__main__ as main_mod
    monkeypatch.delenv("REDIS_URL", raising=False)
    assert main_mod.main() == 0
