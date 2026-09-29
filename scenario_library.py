"""
scenario_library.py — YAML-driven scenario profiles for Clippify.

Each scenario/<name>.yaml defines a full editing profile for one content type:
    name_ar, name_en, hook_strategy (LLM prompt fragment), caption_theme,
    zoom_style, color_grade, sfx_mood, pacing (cuts_per_minute),
    min_clip_sec, max_clip_sec, broll_density, emphasis_words_boost.

Usage:
    from scenario_library import get_profile, list_profiles
    profile = get_profile("comedy")     # dict; falls back to podcast
    all_ids  = list_profiles()          # ["comedy", "cooking", ...]

Unknown / missing / corrupt profiles fall back to the podcast profile,
which itself falls back to BUILTIN_PODCAST if its YAML is unreadable —
so get_profile never raises and never returns None.
"""

import os
from pathlib import Path

SCENARIOS_DIR = Path(__file__).resolve().parent / "scenarios"
DEFAULT_TYPE = "podcast"

# Fields every complete profile must define.
REQUIRED_FIELDS = (
    "name_ar", "name_en", "hook_strategy", "caption_theme", "zoom_style",
    "color_grade", "sfx_mood", "pacing", "min_clip_sec", "max_clip_sec",
    "broll_density", "emphasis_words_boost",
)

# Last-resort profile used only when scenarios/podcast.yaml is unreadable
# AND PyYAML is unavailable — keeps get_profile total (never raises).
BUILTIN_PODCAST = {
    "name_ar": "بودكاست",
    "name_en": "podcast",
    "hook_strategy": (
        "Find the single most compelling calm sentence from this transcript "
        "that would stop someone mid-scroll."
    ),
    "caption_theme": "Minimalist Clean",
    "zoom_style": "gentle",
    "color_grade": "none",
    "sfx_mood": "soft_chill",
    "pacing": 4,
    "min_clip_sec": 25.0,
    "max_clip_sec": 60.0,
    "broll_density": 0.15,
    "emphasis_words_boost": 1.2,
}

_cache: dict = {}


def _profile_path(content_type: str) -> Path:
    return SCENARIOS_DIR / f"{content_type}.yaml"


def _load_yaml_file(path: Path):
    """Return parsed dict from a YAML file, or None on any failure."""
    try:
        import yaml
    except ImportError:
        return None
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh)
    except OSError:
        return None
    except Exception:
        return None
    return data if isinstance(data, dict) else None


def _load_profile(content_type: str) -> dict:
    """Load + validate a single profile. Returns {} when unusable."""
    data = _load_yaml_file(_profile_path(content_type))
    if data is None:
        return {}
    missing = [f for f in REQUIRED_FIELDS if f not in data]
    if missing:
        return {}
    return data


def get_profile(content_type: str) -> dict:
    """
    Return the editing profile for `content_type` as a fresh dict.

    Falls back to the podcast profile for unknown/empty names, unreadable
    files, or incomplete profiles. Always returns a copy — callers may
    mutate freely without corrupting the cache.
    """
    ct = (content_type or "").strip().lower()
    for ext in (".yaml", ".yml"):
        if ct.endswith(ext):
            ct = ct[: -len(ext)]
    if not ct:
        ct = DEFAULT_TYPE

    if ct not in _cache:
        profile = _load_profile(ct)
        if not profile:
            # Fallback chain: requested → podcast → builtin podcast.
            if ct != DEFAULT_TYPE:
                return get_profile(DEFAULT_TYPE)
            fallback = _load_yaml_file(_profile_path(DEFAULT_TYPE))
            profile = fallback if fallback else dict(BUILTIN_PODCAST)
            if not profile:
                profile = dict(BUILTIN_PODCAST)
        _cache[ct] = dict(profile)

    return dict(_cache[ct])


def list_profiles() -> list:
    """Sorted ids of every valid scenario profile in scenarios/."""
    try:
        files = sorted(os.listdir(SCENARIOS_DIR))
    except OSError:
        return []
    out = []
    for fname in files:
        stem, ext = os.path.splitext(fname)
        if ext.lower() in (".yaml", ".yml") and stem:
            if _load_profile(stem):
                out.append(stem)
    return out


def reload_profiles() -> None:
    """Drop the cache so the next get_profile re-reads YAML from disk."""
    _cache.clear()
