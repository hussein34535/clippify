"""
Billing router — mounted by api.py under prefix /api/billing.

Endpoints (docs/CONTRACTS.md):
    POST /checkout {plan} → {checkout_url}  (Stripe Checkout Session; dev mock without key)
    POST /webhook         (Stripe events → update plan/credits)
    GET  /usage           → {period_start, period_end, videos_used, videos_limit}

stripe SDK is imported lazily inside handlers so a missing install never crashes the app.
"""

import json
import os
from datetime import timedelta
from typing import Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from auth import service
from auth.middleware import optional_user
from billing.quotas import PLANS, get_limit

router = APIRouter()

# Paid plans only — free needs no checkout.
PRICE_ENV_BY_PLAN = {"pro": "STRIPE_PRICE_PRO", "studio": "STRIPE_PRICE_STUDIO"}
BILLING_PERIOD_DAYS = 30


def _mock_checkout(plan: str) -> dict:
    return {
        "checkout_url": f"https://billing.example.com/mock/{plan}",
        "mock": True,
    }


def _plan_for_price(price_id: Optional[str]) -> Optional[str]:
    if not price_id:
        return None
    for plan, env_name in PRICE_ENV_BY_PLAN.items():
        if price_id and os.getenv(env_name) == price_id:
            return plan
    return None


@router.post("/checkout")
def checkout(payload: dict = Body(...), user: Optional[dict] = Depends(optional_user)):
    plan = (payload or {}).get("plan")
    if plan not in PRICE_ENV_BY_PLAN:
        raise HTTPException(status_code=400, detail="invalid_plan")

    stripe_key = os.getenv("STRIPE_SECRET_KEY")
    if not stripe_key:
        # Dev mock — no Stripe configured.
        return _mock_checkout(plan)

    try:
        import stripe
    except ImportError:
        raise HTTPException(status_code=503, detail="stripe_sdk_missing")

    base_url = os.getenv("PUBLIC_BASE_URL", "http://localhost:8000")
    price_id = os.getenv(PRICE_ENV_BY_PLAN[plan])
    if not price_id:
        raise HTTPException(
            status_code=500,
            detail=f"{PRICE_ENV_BY_PLAN[plan]} not configured for plan '{plan}'",
        )
    try:
        stripe.api_key = stripe_key
        session = stripe.checkout.Session.create(
            mode="subscription",
            line_items=[{"price": price_id, "quantity": 1}],
            success_url=os.getenv(
                "STRIPE_SUCCESS_URL", f"{base_url}/billing/success"
            ),
            cancel_url=os.getenv("STRIPE_CANCEL_URL", f"{base_url}/billing/cancel"),
            customer_email=user["email"] if user else None,
            metadata={
                "plan": plan,
                "user_id": user["id"] if user else "",
            },
        )
        return {"checkout_url": session.url, "mock": False}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"stripe_error:{exc}")


@router.post("/webhook")
async def webhook(request: Request):
    """
    Stripe webhook. With STRIPE_SECRET_KEY + STRIPE_WEBHOOK_SECRET set the signature is
    verified; otherwise the raw JSON event is accepted (local/dev mock mode).
    checkout.session.completed / invoice.paid → activate metadata.plan for metadata.user_id.
    """
    stripe_key = os.getenv("STRIPE_SECRET_KEY")
    wh_secret = os.getenv("STRIPE_WEBHOOK_SECRET")
    body = await request.body()

    event = None
    if stripe_key and wh_secret:
        try:
            import stripe
        except ImportError:
            raise HTTPException(status_code=503, detail="stripe_sdk_missing")
        try:
            stripe.api_key = stripe_key
            event = stripe.Webhook.construct_event(
                body, request.headers.get("stripe-signature", ""), wh_secret
            )
            event = json.loads(str(event))
        except Exception:
            raise HTTPException(status_code=400, detail="invalid_signature")
    else:
        try:
            event = json.loads(body)
        except Exception:
            raise HTTPException(status_code=400, detail="invalid_json")

    etype = (event or {}).get("type", "")
    if etype in ("checkout.session.completed", "invoice.paid"):
        obj = ((event.get("data") or {}).get("object")) or {}

        meta = obj.get("metadata") or {}
        plan = meta.get("plan")
        user_id = meta.get("user_id")

        if not plan:
            # Fallback: map price id from common shapes to a plan via env.
            price_id = None
            lines = obj.get("lines") or {}
            line_items = lines.get("data") or []
            if line_items:
                price_id = ((line_items[0].get("price") or {}).get("id"))
            elif obj.get("plan"):
                price_id = (obj.get("plan") or {}).get("id")
            plan = _plan_for_price(price_id)

        if plan in PLANS and user_id:
            service.set_plan(user_id, plan, reset_period=True)

    return {"received": True}


@router.get("/usage")
def usage(user: Optional[dict] = Depends(optional_user)):
    """Current billing-period usage summary."""
    if not user:
        return {
            "period_start": None,
            "period_end": None,
            "videos_used": 0,
            "videos_limit": get_limit(None),
            "auth_enabled": False,
        }
    fresh = service.get_user_by_id(user["id"]) or user
    start_raw = fresh.get("period_start")
    period_end = None
    if start_raw:
        try:
            period_end = (
                service.parse_iso(start_raw) + timedelta(days=BILLING_PERIOD_DAYS)
            ).isoformat()
        except Exception:
            period_end = None
    return {
        "period_start": start_raw,
        "period_end": period_end,
        "videos_used": int(fresh.get("credits_used") or 0),
        "videos_limit": get_limit(fresh),
        "auth_enabled": True,
    }
