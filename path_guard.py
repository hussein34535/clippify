"""
path_guard.py — Central path-safety validation for user-supplied file paths.

Clippify's local API receives absolute file paths from the desktop client.
To keep a malicious or compromised request from reading credentials (browser
profiles, .env, cookies, key files) or writing outside the project's data
folders, every path that reaches file I/O endpoints must go through these
validators. They raise fastapi.HTTPException with a JSON detail:

  400 — malformed path ("..", traversal, wrong extension, empty)
  403 — forbidden location (browser profiles, hidden dirs, .env/cookies/keys,
        or a write destination outside the allowed data directories)

Usage:
    path = validate_media_read_path(raw)     # video-stream / thumbnails / ...
    path = validate_project_read_path(raw)   # project/load
    dest = str(validate_write_path(raw))     # project/save / ducking / exports
"""

import os
from pathlib import Path
from typing import List

from fastapi import HTTPException

PROJECT_ROOT = Path(__file__).resolve().parent

# ── Extension allowlists ────────────────────────────────────────────────────
MEDIA_EXTENSIONS = {
    ".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v", ".mpg", ".mpeg",
    ".wmv", ".flv", ".ts",
    ".mp3", ".wav", ".m4a", ".aac", ".ogg", ".flac",
}
PROJECT_EXTENSIONS = {".json", ".clippify"}

# ── Forbidden locations ─────────────────────────────────────────────────────
# Browser / AI-browser profile folder names. Exact, case-insensitive component
# match (avoids false positives such as "chrome-demo.mp4" in a media folder).
FORBIDDEN_DIR_COMPONENTS = {
    "chrome", "chromium", "firefox", "mozilla",
    ".gemini", "antigravity", "antigravity-browser-profile",
    "browser-profile",
}
FORBIDDEN_FILE_EXTENSIONS = {".key", ".pem"}


def _reject(status_code: int, detail: str) -> "HTTPException":
    return HTTPException(status_code=status_code, detail=detail)


def _is_forbidden_file_name(name: str) -> bool:
    lowered = name.lower()
    if lowered == ".env" or lowered.startswith(".env."):
        return True
    if lowered.startswith("cookies") and lowered.endswith(".txt"):
        return True
    if Path(name).suffix.lower() in FORBIDDEN_FILE_EXTENSIONS:
        return True
    return False


def _check_forbidden(resolved: Path) -> None:
    """Raise 403 if the resolved path hits a hidden dir, browser profile,
    or a credential-looking file. Checked before extension rules so the
    caller gets the clearest possible reason."""
    for part in resolved.parts:
        if part in ("", ".", "/", "\\") or (len(part) == 2 and part[1] == ":"):
            continue  # drive anchor / current-dir marker
        if part.startswith("."):
            raise _reject(
                403,
                f"Access to hidden/system folders is not allowed: '{part}'",
            )
        if part.lower() in FORBIDDEN_DIR_COMPONENTS:
            raise _reject(
                403,
                "Access to browser/AI-browser profile folders is not allowed: "
                f"'{part}'",
            )
    if _is_forbidden_file_name(resolved.name):
        raise _reject(
            403,
            f"Access to credential/config files is not allowed: '{resolved.name}'",
        )


def resolve_user_path(raw: str) -> Path:
    """Normalize and safety-check a user-supplied path.

    Rejects empty paths, NUL bytes, explicit '..' traversal and forbidden
    locations. Relative paths are resolved against the project root.
    Returns the resolved absolute path (existence is NOT checked here —
    endpoints keep their own 404 handling so they never leak which
    forbidden paths exist).
    """
    if not isinstance(raw, str) or not raw.strip():
        raise _reject(400, "A non-empty 'path' is required")
    if "\x00" in raw:
        raise _reject(400, "Invalid characters in path")

    parts = Path(raw).parts
    if ".." in parts:
        raise _reject(400, "Path traversal ('..') is not allowed")

    candidate = Path(raw)
    if not candidate.is_absolute():
        candidate = PROJECT_ROOT / candidate

    try:
        resolved = candidate.resolve()
    except (OSError, ValueError) as exc:
        raise _reject(400, f"Invalid path: {exc}")

    if ".." in resolved.parts:
        raise _reject(400, "Path traversal ('..') is not allowed")

    _check_forbidden(resolved)
    return resolved


def _has_allowed_suffix(resolved: Path, allowed: set, kind: str) -> None:
    suffix = resolved.suffix.lower()
    if suffix not in allowed:
        raise _reject(
            400,
            f"Unsupported file type '{suffix or '(none)'}' — "
            f"only {kind} files are allowed: "
            f"{', '.join(sorted(allowed))}",
        )


def validate_media_read_path(raw: str) -> str:
    """Validate a path used for reading/streaming media. Returns the
    resolved path string."""
    resolved = resolve_user_path(raw)
    _has_allowed_suffix(resolved, MEDIA_EXTENSIONS, "media")
    return str(resolved)


def validate_project_read_path(raw: str) -> str:
    """Validate a path used for reading a project file. Returns the
    resolved path string."""
    resolved = resolve_user_path(raw)
    _has_allowed_suffix(resolved, PROJECT_EXTENSIONS, "project (.json / .clippify)")
    return str(resolved)


def _allowed_write_roots() -> List[Path]:
    roots = [
        PROJECT_ROOT / "projects",
        PROJECT_ROOT / "output",
        PROJECT_ROOT / "exports",
        PROJECT_ROOT / "temp",
    ]
    extra = os.getenv("CLIPPIFY_DATA_DIRS", "")
    for chunk in extra.split(","):
        chunk = chunk.strip()
        if chunk:
            roots.append(Path(chunk).expanduser())
    resolved: List[Path] = []
    for root in roots:
        try:
            r = root.resolve()
        except OSError:
            continue
        if r not in resolved:
            resolved.append(r)
    return resolved


def validate_write_path(raw: str) -> Path:
    """Validate a path used for writing (project save, render/export outputs).
    The destination must live inside the project's data directories
    (projects/, output/, exports/, temp/ — extendable via the
    CLIPPIFY_DATA_DIRS comma-separated env var)."""
    resolved = resolve_user_path(raw)
    for root in _allowed_write_roots():
        if resolved.is_relative_to(root):
            return resolved
    raise _reject(
        403,
        "Write destination is outside the allowed data directories "
        "(projects/, output/, exports/, temp/ or CLIPPIFY_DATA_DIRS): "
        f"{resolved}",
    )
