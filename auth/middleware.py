"""
Auth middleware — contract per docs/CONTRACTS.md:

    from auth.middleware import AUTH_ENABLED, require_user

AUTH_ENABLED: env REQUIRE_AUTH == "true".
require_user: FastAPI Depends callable → user dict (no password_hash) or HTTPException 401.
optional_user: same but returns None instead of raising.
"""

import os
from typing import Optional

from fastapi import Header, HTTPException

from auth import service


def _env_flag(name: str) -> bool:
    return os.getenv(name, "").strip().lower() == "true"


# Read at import (matches the try/except ImportError usage pattern in CONTRACTS.md).
AUTH_ENABLED: bool = _env_flag("REQUIRE_AUTH")

_401_HEADERS = {"WWW-Authenticate": "Bearer"}


def _authenticate(authorization: Optional[str], required: bool) -> Optional[dict]:
    if not authorization or not authorization.lower().startswith("bearer "):
        if required:
            raise HTTPException(401, "Not authenticated", headers=_401_HEADERS)
        return None
    token = authorization.split(" ", 1)[1].strip()
    try:
        payload = service.decode_token(token, expected_type="access")
    except service.AuthError as exc:
        if required:
            raise HTTPException(401, f"Invalid or expired token ({exc})", headers=_401_HEADERS)
        return None
    user = service.get_user_by_id(payload.get("sub"))
    if not user:
        if required:
            raise HTTPException(401, "User not found", headers=_401_HEADERS)
        return None
    return user


def require_user(authorization: str = Header(default=None)) -> dict:
    """Dependency: valid Bearer access token → user dict, else 401."""
    return _authenticate(authorization, required=True)


def optional_user(authorization: str = Header(default=None)) -> Optional[dict]:
    """Dependency: user dict if a valid token is present, else None."""
    return _authenticate(authorization, required=False)
