"""
Billing quotas — monthly video credits per plan (docs/CONTRACTS.md):

    free: 3 | pro: 30 | studio: 300

All functions accept the user dict from auth.middleware (must contain "id").
user=None (auth disabled) → always allowed: (True, "auth_disabled").
"""

from datetime import timedelta
from typing import Optional, Tuple

from auth import service

PLANS = {"free": 3, "pro": 30, "studio": 300}
DEFAULT_PLAN = "free"
PERIOD_DAYS = 30


def get_limit(user: Optional[dict]) -> int:
    """Monthly credits limit for the user's plan (default free)."""
    if not user:
        return PLANS[DEFAULT_PLAN]
    return PLANS.get(user.get("plan") or DEFAULT_PLAN, PLANS[DEFAULT_PLAN])


def _effective_usage(user: dict) -> Tuple[int, str]:
    """(credits_used, period_start_iso) applying rollover if the 30-day period elapsed."""
    used = int(user.get("credits_used") or 0)
    start_raw = user.get("period_start")
    now = service.utc_now()
    try:
        start = service.parse_iso(start_raw) if start_raw else None
    except Exception:
        start = None
    if start is None or (now - start) > timedelta(days=PERIOD_DAYS):
        # Period rolled over → reset counter, anchor new period at now.
        return 0, now.isoformat()
    return used, start_raw


def check_quota(user: Optional[dict]) -> bool:
    """True if the user still has credit left this period."""
    if user is None:
        return True
    fresh = service.get_user_by_id(user.get("id")) or user
    used, _ = _effective_usage(fresh)
    return used < get_limit(fresh)


def consume_credit(user: Optional[dict]) -> Tuple[bool, str]:
    """
    Consume one credit for the user, persisting to users.db.
    Returns (ok, msg); msg == "quota_exceeded" when over the plan limit.
    Rollover: if >30 days since period_start → reset credits_used to 0 first.
    """
    if user is None:
        return (True, "auth_disabled")
    uid = user.get("id")
    if not uid:
        return (True, "auth_disabled")

    fresh = service.get_user_by_id(uid) or dict(user)
    used, start_iso = _effective_usage(fresh)
    limit = get_limit(fresh)

    if used >= limit:
        return (False, "quota_exceeded")

    used += 1
    service.update_usage(uid, credits_used=used, period_start=start_iso)
    return (True, f"credit_consumed:{used}/{limit}")
