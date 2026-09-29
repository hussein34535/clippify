"""
jobs.queue — enqueue/status/cancel abstraction.

REDIS_URL set  -> RQ queue "clippify" (redis + rq imported lazily).
REDIS_URL unset-> ThreadPoolExecutor fallback with in-memory _jobs dict.

Cooperative cancellation: long-running tasks poll should_cancel(job_id)
(or call check_cancel(job_id) to raise CancelledError) at safe points.
"""

from __future__ import annotations

import os
import threading
import uuid
from concurrent.futures import ThreadPoolExecutor, Future

QUEUE_NAME = "clippify"

# name -> callable; lets string-based enqueues work across processes (RQ mode)
JOB_REGISTRY: dict[str, callable] = {}

_lock = threading.Lock()
_jobs: dict[str, dict] = {}          # fallback-mode job bookkeeping
_futures: dict[str, Future] = {}
_cancelled: set[str] = set()
_executor: ThreadPoolExecutor | None = None


class CancelledError(Exception):
    """Raised inside a task when cancellation was requested."""


def register(name: str):
    """Decorator: register a callable under a stable string name."""
    def deco(fn):
        JOB_REGISTRY[name] = fn
        return fn
    return deco


def _resolve(fn):
    if callable(fn):
        return fn
    if fn in JOB_REGISTRY:
        return JOB_REGISTRY[fn]
    raise KeyError(
        f"Unknown job {fn!r}. Register it first: @register({fn!r}) so RQ workers can resolve it."
    )


# ---------------------------------------------------------------------------
# Fallback (ThreadPool) mode
# ---------------------------------------------------------------------------


def _get_executor() -> ThreadPoolExecutor:
    global _executor
    if _executor is None:
        workers = int(os.environ.get("MAX_WORKERS", "2") or 2)
        _executor = ThreadPoolExecutor(max_workers=max(1, workers), thread_name_prefix="clippify")
    return _executor


def _set(job_id: str, **fields) -> None:
    with _lock:
        _jobs.setdefault(job_id, {})
        _jobs[job_id].update(fields)


def _run_task(job_id: str, fn, args, kwargs):
    if should_cancel(job_id):
        _set(job_id, status="cancelled", error="cancelled before start")
        return
    _set(job_id, status="running", error=None)
    try:
        result = fn(*args, **kwargs)
        if should_cancel(job_id):
            _set(job_id, status="cancelled", error="cancelled during run")
        else:
            _set(job_id, status="done", result=result, error=None)
    except CancelledError as exc:
        _set(job_id, status="cancelled", error=str(exc))
    except Exception as exc:  # noqa: BLE001 — record everything for status()
        _set(job_id, status="error", error=f"{type(exc).__name__}: {exc}")


def _enqueue_fallback(fn, args, kwargs, job_id: str) -> str:
    _set(job_id, status="queued", result=None, error=None)
    fut = _get_executor().submit(_run_task, job_id, fn, args, kwargs)
    with _lock:
        _futures[job_id] = fut
    fut.add_done_callback(lambda f: _futures.pop(job_id, None))
    return job_id


# ---------------------------------------------------------------------------
# RQ mode
# ---------------------------------------------------------------------------


def _rq_queue():
    import redis  # lazy: absent install must not break fallback mode
    from rq import Queue
    conn = redis.Redis.from_url(os.environ["REDIS_URL"])
    return Queue(QUEUE_NAME, connection=conn)


def _enqueue_rq(fn, args, kwargs, job_id):
    queue = _rq_queue()
    job = queue.enqueue_call(_resolve(fn), args=args, kwargs=kwargs,
                             job_id=job_id, timeout=os.environ.get("RQ_JOB_TIMEOUT", "3600"))
    return job.id


def _status_rq(job_id: str) -> dict | None:
    from rq.job import Job
    try:
        job = Job.fetch(job_id, connection=_rq_queue().connection)
    except Exception:
        return None
    mapping = {"queued": "queued", "started": "running", "finished": "done",
               "failed": "error", "canceled": "cancelled", "stopped": "cancelled"}
    st = mapping.get(job.get_status() or "", "unknown")
    out = {"status": st}
    if st == "done":
        out["result"] = job.return_value()
    elif st == "error":
        out["error"] = str(job.exc_info or "failed")[-2000:]
    return out


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def enqueue(fn_name_or_callable, *args, job_id: str | None = None, **kwargs) -> str:
    """Submit a task (callable or registered name). Returns its id."""
    jid = job_id or uuid.uuid4().hex
    if os.environ.get("REDIS_URL"):
        return _enqueue_rq(fn_name_or_callable, args, kwargs, jid)
    return _enqueue_fallback(_resolve(fn_name_or_callable), args, kwargs, jid)


def status(job_id: str) -> dict | None:
    """{"status", "result"?, "error"?} or None when unknown."""
    if os.environ.get("REDIS_URL"):
        return _status_rq(job_id)
    with _lock:
        snap = dict(_jobs.get(job_id) or {})
    return snap or None


def cancel(job_id: str) -> bool:
    """
    Request cooperative cancellation. Running tasks observe it only when they
    poll should_cancel()/check_cancel(). Returns True if known & flagged.
    """
    if os.environ.get("REDIS_URL"):
        try:
            from rq.job import Job
            Job.fetch(job_id, connection=_rq_queue().connection).cancel()
            return True
        except Exception:
            return False

    with _lock:
        known = job_id in _jobs
        fut = _futures.get(job_id)
        if known:
            _cancelled.add(job_id)
            _jobs[job_id]["status"] = "cancelling"
    if fut is not None and not fut.running():
        fut.cancel()
    if known:
        _set(job_id, status="cancelled")
    return known


def should_cancel(job_id: str) -> bool:
    """Poll this inside long-running workers at safe checkpoints."""
    if os.environ.get("REDIS_URL"):
        try:
            st = (_status_rq(job_id) or {}).get("status")
            return st == "cancelled"
        except Exception:
            return False
    with _lock:
        return job_id in _cancelled


def check_cancel(job_id: str) -> None:
    """should_cancel + raise — one-liner for worker loops."""
    if should_cancel(job_id):
        raise CancelledError(f"job {job_id} cancelled")


def reset_for_tests() -> None:
    """Clear all fallback-mode state (used by the test-suite only)."""
    global _executor
    with _lock:
        _jobs.clear()
        _futures.clear()
        _cancelled.clear()
    if _executor is not None:
        _executor.shutdown(wait=False)
        _executor = None
