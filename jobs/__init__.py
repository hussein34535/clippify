"""
jobs — background task queue for Clippify v2.

Two modes, selected by env:

    REDIS_URL set   -> RQ (redis) mode; run workers with:  python -m jobs
    REDIS_URL unset -> in-process ThreadPoolExecutor fallback (dev/desktop)

Usage:
    from jobs import enqueue, status, cancel, should_cancel

    def render(session_id):
        while working:
            if should_cancel(job_id): raise CancelledError()

    jid = enqueue(render, "abc123")
    status(jid)  # {"status": "queued"|"running"|"done"|"error"|"cancelled", ...}

Named functions can be registered so string-based enqueue works across
process boundaries (required for RQ workers):

    from jobs import register
    @register("render_session")
    def render_session(...): ...
"""

from .queue import (
    CancelledError,
    JOB_REGISTRY,
    check_cancel,
    enqueue,
    register,
    should_cancel,
    status,
    cancel,
)

__all__ = [
    "enqueue", "status", "cancel", "should_cancel", "check_cancel",
    "register", "CancelledError", "JOB_REGISTRY",
]
