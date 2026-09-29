"""Pydantic request/response models for the auth API."""

from typing import Optional

from pydantic import BaseModel, Field


class RegisterIn(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=6, max_length=128)
    name: str = Field(default="", max_length=120)


class LoginIn(BaseModel):
    email: str
    password: str


class RefreshIn(BaseModel):
    refresh_token: str


class UserOut(BaseModel):
    id: str
    email: str
    name: str = ""
    plan: str = "free"
    credits_used: int = 0
    credits_limit: int = 3


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class AuthResponse(TokenPair):
    """register/login response: user + fresh token pair."""
    user: UserOut


class MeResponse(BaseModel):
    user: UserOut


class OkResponse(BaseModel):
    ok: bool = True
