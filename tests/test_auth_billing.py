"""
Offline tests for AGENT-3 scope: auth (register/login/refresh/me/logout),
auth middleware (401 paths), billing quotas (limits + rollover), billing router
(mock checkout / mock webhook / usage).

Everything runs against a throwaway SQLite DB via CLIPPIFY_USERS_DB=tmp dir.
No network access required.
"""

import os
import sys
import time
import importlib

import pytest

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

# Env must be configured BEFORE importing auth/billing modules.
os.environ.setdefault("JWT_SECRET", "test-jwt-secret")
os.environ["REQUIRE_AUTH"] = "true"  # force AUTH_ENABLED=True for this run
os.environ.pop("STRIPE_SECRET_KEY", None)  # guarantee mock checkout mode

# conftest.py imports api.py first, which already imported auth.middleware with the
# original env → reload it so AUTH_ENABLED reflects REQUIRE_AUTH=true.
import auth.middleware as _auth_middleware  # noqa: E402

importlib.reload(_auth_middleware)

from datetime import timedelta

from jose import jwt as jose_jwt
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from auth import service
from auth.middleware import AUTH_ENABLED, optional_user, require_user
from auth.router import router as auth_router
from billing import quotas
from billing.router import router as billing_router


# ── Fixtures ──────────────────────────────────────────────────────────────────
@pytest.fixture()
def users_db(tmp_path, monkeypatch):
    """Isolated users.db per test (tmp dir)."""
    db_file = tmp_path / "users.db"
    monkeypatch.setenv("CLIPPIFY_USERS_DB", str(db_file))
    return db_file


@pytest.fixture()
def client(users_db):
    app = FastAPI()
    app.include_router(auth_router, prefix="/api/auth")
    app.include_router(billing_router, prefix="/api/billing")
    return TestClient(app)


# ── Middleware flag ───────────────────────────────────────────────────────────
def test_auth_enabled_flag_is_bool():
    # REQUIRE_AUTH=true was set above → must be truthy
    assert AUTH_ENABLED is True


# ── Full auth cycle ───────────────────────────────────────────────────────────
def test_full_auth_cycle(client):
    # 1) register
    r = client.post(
        "/api/auth/register",
        json={"email": "cycle@example.com", "password": "secret123", "name": "Cycle"},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["user"]["email"] == "cycle@example.com"
    assert data["user"]["plan"] == "free"
    assert data["user"]["credits_used"] == 0
    assert data["user"]["credits_limit"] == quotas.PLANS["free"]
    assert data["access_token"] and data["refresh_token"]
    tokens = data

    # 2) login
    r = client.post(
        "/api/auth/login",
        json={"email": "cycle@example.com", "password": "secret123"},
    )
    assert r.status_code == 200, r.text
    assert r.json()["user"]["id"] == tokens["user"]["id"]

    # 3) me
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    r = client.get("/api/auth/me", headers=headers)
    assert r.status_code == 200, r.text
    assert r.json()["user"]["id"] == tokens["user"]["id"]

    # 4) refresh
    r = client.post(
        "/api/auth/refresh", json={"refresh_token": tokens["refresh_token"]}
    )
    assert r.status_code == 200, r.text
    refreshed = r.json()
    assert refreshed["access_token"] and refreshed["refresh_token"]

    # refresh token must NOT work as an access token
    bad_headers = {"Authorization": f"Bearer {tokens['refresh_token']}"}
    r = client.get("/api/auth/me", headers=bad_headers)
    assert r.status_code == 401

    # 5) duplicate register → 409
    r = client.post(
        "/api/auth/register",
        json={"email": "cycle@example.com", "password": "other123", "name": "Dup"},
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "email_already_exists"

    # 6) bad login → 401
    r = client.post(
        "/api/auth/login",
        json={"email": "cycle@example.com", "password": "wrongpass"},
    )
    assert r.status_code == 401
    r = client.post(
        "/api/auth/login",
        json={"email": "ghost@example.com", "password": "whatever1"},
    )
    assert r.status_code == 401

    # 7) logout (Bearer) → ok
    r = client.post("/api/auth/logout", headers=headers)
    assert r.status_code == 200
    assert r.json()["ok"] is True

    # me without token → 401
    r = client.get("/api/auth/me")
    assert r.status_code == 401


# ── Quotas ────────────────────────────────────────────────────────────────────
def test_quotas_free_limit_and_rollover(users_db):
    user = service.create_user("quota@example.com", "secret123", "Quota")
    uid = user["id"]
    assert quotas.get_limit(user) == 3
    assert quotas.check_quota(user) is True

    # credits 1..3 succeed (3rd credit inclusive)
    for i in range(1, 4):
        ok, msg = quotas.consume_credit(user)
        assert ok is True, (i, msg)
    fresh = service.get_user_by_id(uid)
    assert fresh["credits_used"] == 3

    # 4th credit fails
    assert quotas.check_quota(fresh) is False
    ok, msg = quotas.consume_credit(fresh)
    assert ok is False
    assert msg == "quota_exceeded"

    # Rollover: period_start pushed >30 days back → next consume resets to 1
    old = (service.utc_now() - timedelta(days=31)).isoformat()
    service.update_usage(uid, credits_used=7, period_start=old)
    stale = service.get_user_by_id(uid)
    assert stale["credits_used"] == 7
    ok, msg = quotas.consume_credit(stale)
    assert ok is True, msg
    rolled = service.get_user_by_id(uid)
    assert rolled["credits_used"] == 1
    assert old != rolled["period_start"]

    # auth disabled (user=None) → always allowed
    assert quotas.check_quota(None) is True
    assert quotas.consume_credit(None) == (True, "auth_disabled")


def test_pro_plan_limit(users_db):
    user = service.create_user("pro@example.com", "secret123", "Pro")
    upgraded = service.set_plan(user["id"], "pro", reset_period=True)
    assert quotas.get_limit(upgraded) == 30
    assert upgraded["credits_used"] == 0


# ── Middleware 401 paths ──────────────────────────────────────────────────────
def test_require_user_missing_header_raises_401():
    with pytest.raises(HTTPException) as exc_info:
        require_user(None)
    assert exc_info.value.status_code == 401


def test_require_user_garbage_token_raises_401():
    with pytest.raises(HTTPException) as exc_info:
        require_user("Bearer this.is.garbage")
    assert exc_info.value.status_code == 401

    with pytest.raises(HTTPException) as exc_info:
        require_user("Basic dXNlcjpwYXNz")
    assert exc_info.value.status_code == 401


def test_require_user_expired_token_raises_401(users_db):
    user = service.create_user("expired@example.com", "secret123", "Expired")
    now = int(time.time())
    expired_token = jose_jwt.encode(
        {
            "sub": user["id"],
            "type": "access",
            "iat": now - 120,
            "exp": now - 60,  # expired one minute ago
        },
        service.JWT_SECRET,
        algorithm="HS256",
    )
    with pytest.raises(HTTPException) as exc_info:
        require_user(f"Bearer {expired_token}")
    assert exc_info.value.status_code == 401
    assert "expired" in exc_info.value.detail.lower()


def test_optional_user_returns_none_without_header():
    assert optional_user(None) is None


# ── Billing router ────────────────────────────────────────────────────────────
def test_checkout_mock_without_stripe_key(client, monkeypatch):
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    r = client.post("/api/billing/checkout", json={"plan": "pro"})
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["mock"] is True
    assert data["checkout_url"].startswith("https://billing.example.com/mock/pro")

    r = client.post("/api/billing/checkout", json={"plan": "studio"})
    assert r.status_code == 200
    assert "/mock/studio" in r.json()["checkout_url"]

    # free / unknown plans are rejected
    r = client.post("/api/billing/checkout", json={"plan": "free"})
    assert r.status_code == 400
    r = client.post("/api/billing/checkout", json={})
    assert r.status_code == 400


def test_webhook_mock_activates_plan(client):
    reg = client.post(
        "/api/auth/register",
        json={"email": "wh@example.com", "password": "secret123", "name": "WH"},
    )
    uid = reg.json()["user"]["id"]

    event = {
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "metadata": {"plan": "pro", "user_id": uid},
            }
        },
    }
    r = client.post("/api/billing/webhook", json=event)
    assert r.status_code == 200, r.text
    assert r.json() == {"received": True}

    user = service.get_user_by_id(uid)
    assert user["plan"] == "pro"
    assert user["credits_used"] == 0

    # usage endpoint reflects the upgrade
    tokens = client.post(
        "/api/auth/login",
        json={"email": "wh@example.com", "password": "secret123"},
    ).json()
    r = client.get(
        "/api/billing/usage",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert r.status_code == 200, r.text
    usage = r.json()
    assert usage["videos_used"] == 0
    assert usage["videos_limit"] == 30
    assert usage["period_start"] and usage["period_end"]

    # invoice.paid resets credits
    quotas.consume_credit(service.get_user_by_id(uid))
    r = client.post(
        "/api/billing/webhook",
        json={
            "type": "invoice.paid",
            "data": {"object": {"metadata": {"plan": "pro", "user_id": uid}}},
        },
    )
    assert r.status_code == 200
    assert service.get_user_by_id(uid)["credits_used"] == 0


def test_usage_without_auth_reports_zeroed(client):
    r = client.get("/api/billing/usage")
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["videos_used"] == 0
    assert data["period_start"] is None
