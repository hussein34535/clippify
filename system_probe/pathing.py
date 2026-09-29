"""Shared FFmpeg/FFprobe resolver.

Cascade for resolve_ffmpeg():
    1. CLIPPIFY_FFMPEG env var (validated with os.path.isfile)
    2. shutil.which('ffmpeg')
    3. imageio_ffmpeg.get_ffmpeg_exe()  (the ONLY guaranteed source on this
       machine family — ffmpeg is NOT on PATH, it ships via imageio_ffmpeg)
    4. glob of common install dirs (%LOCALAPPDATA%\\Programs\\ffmpeg*,
       C:\\ffmpeg*, Program Files / Program Files (x86))
    5. None

resolve_ffprobe() cascade:
    1. CLIPPIFY_FFPROBE env var (validated)
    2. shutil.which('ffprobe')
    3. common-dir glob
    4. None

NOTE: imageio_ffmpeg ships *no* ffprobe binary — that's why step 3 is
deliberately absent from the ffprobe cascade; a missing probe falls back to
None and callers must degrade gracefully (duration probing etc.).
"""

from __future__ import annotations

import glob
import os
import shutil
import sys
from typing import Dict, Optional

_CACHE: Dict[str, Optional[str]] = {"ffmpeg": None, "ffprobe": None}
_CACHED: Dict[str, bool] = {"ffmpeg": False, "ffprobe": False}


def reset_cache() -> None:
    """Forget memoized resolutions (used by tests and settings changes)."""
    _CACHE.clear()
    _CACHED.clear()
    _CACHE.update({"ffmpeg": None, "ffprobe": None})
    _CACHED.update({"ffmpeg": False, "ffprobe": False})


def _candidate_patterns(binary: str) -> list:
    local_app_data = os.environ.get("LOCALAPPDATA", r"C:\Users\Public\AppData\Local")
    program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    exe = binary + ".exe"
    return [
        os.path.join(local_app_data, "Programs", "ffmpeg*", "bin", exe),
        os.path.join(local_app_data, "Programs", "ffmpeg*", exe),
        r"C:\ffmpeg*\bin" + os.sep + exe,
        os.path.join(program_files, "ffmpeg*", "bin", exe),
        os.path.join(program_files_x86, "ffmpeg*", "bin", exe),
    ]


def _glob_common_dirs(binary: str) -> Optional[str]:
    for pattern in _candidate_patterns(binary):
        try:
            hits = sorted(glob.glob(pattern))
        except Exception:
            continue
        for hit in hits:
            if os.path.isfile(hit):
                return hit
    return None


def _from_imageio() -> Optional[str]:
    """imageio_ffmpeg ships its own ffmpeg build; import lazily so the module
    stays importable when the package is absent."""
    try:
        import imageio_ffmpeg  # type: ignore

        exe = imageio_ffmpeg.get_ffmpeg_exe()
        if exe and os.path.isfile(exe):
            return exe
    except Exception:
        pass
    return None


def _resolve(kind: str, env_var: str, which_name: str, allow_imageio: bool) -> Optional[str]:
    if _CACHED.get(kind):
        return _CACHE[kind]

    resolved: Optional[str] = None

    # 1. explicit env override — only trust real files
    env_path = os.environ.get(env_var)
    if env_path and os.path.isfile(env_path):
        resolved = env_path

    # 2. PATH lookup
    if resolved is None:
        resolved = shutil.which(which_name)

    # 3. bundled imageio_ffmpeg binary (ffmpeg only — no ffprobe there)
    if resolved is None and allow_imageio:
        resolved = _from_imageio()

    # 4. well-known install locations
    if resolved is None:
        resolved = _glob_common_dirs(which_name)

    _CACHE[kind] = resolved
    _CACHED[kind] = True
    return resolved


def resolve_ffmpeg(force: bool = False) -> Optional[str]:
    """Absolute path to an ffmpeg executable, or None."""
    if force:
        _CACHED["ffmpeg"] = False
    return _resolve("ffmpeg", "CLIPPIFY_FFMPEG", "ffmpeg", allow_imageio=True)


def resolve_ffprobe(force: bool = False) -> Optional[str]:
    """Absolute path to ffprobe, or None.

    imageio_ffmpeg does NOT bundle ffprobe, so on stock setups this returns
    None unless ffprobe was installed separately — callers must handle it.
    """
    if force:
        _CACHED["ffprobe"] = False
    return _resolve("ffprobe", "CLIPPIFY_FFPROBE", "ffprobe", allow_imageio=False)
