"""System probe API router.

Mounted by the integrator (NOT wired into api.py here):
    from system_probe.router import router as system_router
    app.include_router(system_router)   # serves /system/tier, /system/ffmpeg

Endpoints are cheap: probe() is cached 300s and resolve_ffmpeg() memoized.
The frontend onboarding screen consumes GET /system/ffmpeg.
"""

from __future__ import annotations

from importlib import import_module

from fastapi import APIRouter

# NOTE: resolved via importlib because `system_probe.probe` (the function
# re-exported anywhere) would otherwise shadow the probe submodule.
pathing_module = import_module("system_probe.pathing")
probe_module = import_module("system_probe.probe")

router = APIRouter()


@router.get("/tier")
def get_system_tier() -> dict:
    """Hardware snapshot merged with the performance-tier verdict."""
    snapshot = probe_module.probe()
    verdict = probe_module.decide_tier(snapshot)
    return {**snapshot, **verdict}


@router.get("/ffmpeg")
def get_system_ffmpeg() -> dict:
    """Resolved ffmpeg path for the onboarding flow."""
    path = pathing_module.resolve_ffmpeg()
    return {"path": path, "found": bool(path)}

