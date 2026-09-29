"""
Auth router — mounted by api.py under prefix /api/auth.

Endpoints (docs/CONTRACTS.md):
    POST /register {email,password,name} → 200 {user, access_token, refresh_token}
    POST /login    {email,password}      → 200 same shape | 401
    POST /refresh  {refresh_token}       → 200 {access_token, refresh_token}
    GET  /me       (Bearer)              → 200 {user}
    POST /logout   (Bearer)              → 200 {ok: true}
Errors: 401 bad creds/token • 409 duplicate email • 422 standard FastAPI validation.
"""

from fastapi import APIRouter, Depends, HTTPException

from auth import service
from auth.middleware import require_user
from auth.models import (
    AuthResponse,
    LoginIn,
    MeResponse,
    OkResponse,
    RefreshIn,
    RegisterIn,
    TokenPair,
    UserOut,
)
from billing.quotas import get_limit

router = APIRouter()


def _user_out(user: dict) -> UserOut:
    return UserOut(
        id=user["id"],
        email=user["email"],
        name=user.get("name", ""),
        plan=user.get("plan", "free"),
        credits_used=int(user.get("credits_used", 0)),
        credits_limit=get_limit(user),
    )


def _issue_tokens(user: dict) -> TokenPair:
    return TokenPair(
        access_token=service.create_access_token(user["id"]),
        refresh_token=service.create_refresh_token(user["id"]),
    )


@router.post("/register", response_model=AuthResponse)
def register(payload: RegisterIn):
    try:
        user = service.create_user(payload.email, payload.password, payload.name)
    except service.DuplicateEmailError:
        raise HTTPException(status_code=409, detail="email_already_exists")
    return AuthResponse(user=_user_out(user), **_issue_tokens(user).model_dump())


@router.post("/login", response_model=AuthResponse)
def login(payload: LoginIn):
    user = service.authenticate(payload.email, payload.password)
    if not user:
        raise HTTPException(status_code=401, detail="invalid_credentials")
    return AuthResponse(user=_user_out(user), **_issue_tokens(user).model_dump())


@router.post("/refresh", response_model=TokenPair)
def refresh(payload: RefreshIn):
    try:
        claims = service.decode_token(payload.refresh_token, expected_type="refresh")
    except service.AuthError:
        raise HTTPException(status_code=401, detail="invalid_refresh_token")
    user = service.get_user_by_id(claims.get("sub"))
    if not user:
        raise HTTPException(status_code=401, detail="invalid_refresh_token")
    return _issue_tokens(user)


@router.get("/me", response_model=MeResponse)
def me(user: dict = Depends(require_user)):
    # re-read so plan/credits changes since token issue are reflected
    fresh = service.get_user_by_id(user["id"]) or user
    return MeResponse(user=_user_out(fresh))


@router.post("/logout", response_model=OkResponse)
def logout(user: dict = Depends(require_user)):
    # Stateless JWT — client discards tokens. (Revocation list is a future stub.)
    return OkResponse(ok=True)
