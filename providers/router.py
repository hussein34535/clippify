"""
BYOK + free-chain provider management (mounted by api.py later, e.g.
`app.include_router(providers.router, prefix="/api/providers")`).

Endpoints:
    GET    /status               → [{provider, mode, available_today, cap, cooldown_until}]
    POST   /key {provider, key}  → store the user's own API key (BYOK precedence)
    DELETE /key/{provider}       → remove stored key
"""

from fastapi import APIRouter, Body, HTTPException

from providers import ledger, store

router = APIRouter()

# Providers surfaced in /status (ollama is local → never 'off').
KNOWN_PROVIDERS = ["ollama", "gemini", "groq"]

_ENV_KEY_BY_PROVIDER = {"gemini": "GEMMA_API_KEY", "groq": "GROQ_API_KEY"}


def _mode(provider: str) -> str:
    if store.get_key(provider):
        return "byok"
    if provider == "ollama" or os_key(provider):
        return "free"
    return "off"


def os_key(provider: str):
    import os

    name = _ENV_KEY_BY_PROVIDER.get(provider)
    return os.getenv(name, "") if name else ""


@router.get("/status")
def status():
    out = []
    for provider in KNOWN_PROVIDERS:
        cap = ledger.cap_for(provider)
        out.append(
            {
                "provider": provider,
                "mode": _mode(provider),
                "available_today": ledger.available(provider),
                "cap": cap,
                "cooldown_until": ledger.cooldown_until(provider),
            }
        )
    return out


@router.post("/key")
def set_key(payload: dict = Body(...)):
    provider = (payload or {}).get("provider", "").strip()
    key = (payload or {}).get("key", "").strip()
    if not provider or not key:
        raise HTTPException(status_code=400, detail="provider and key must be non-empty")
    store.set_key(provider, key)
    return {"ok": True, "provider": provider, "mode": _mode(provider)}


@router.delete("/key/{provider}")
def del_key(provider: str):
    if not store.delete_key(provider):
        raise HTTPException(status_code=404, detail="no_stored_key")
    return {"ok": True, "provider": provider}
