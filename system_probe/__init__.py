"""system_probe — device truth, performance-tier brain and shared ffmpeg resolver.

Layout:
    pathing.py  resolve_ffmpeg()/resolve_ffprobe() shared cascade resolver
    probe.py    probe() cached hardware snapshot + decide_tier() rules
    router.py   APIRouter (GET /system/tier, GET /system/ffmpeg)

Usage (import the submodules directly — do NOT rely on `from system_probe
import probe`, which is ambiguous with the submodule):
    from system_probe.probe import probe, decide_tier
    from system_probe.pathing import resolve_ffmpeg

The integrator mounts the router later:
    from system_probe.router import router as system_router
    app.include_router(system_router)
"""

from system_probe.pathing import resolve_ffmpeg, resolve_ffprobe, reset_cache

__all__ = [
    "resolve_ffmpeg",
    "resolve_ffprobe",
    "reset_cache",
]
