"""
freesound_client.py — Freesound.org API integration for ClipAI
Fetches professional, high-quality SFX from freesound.org
API is FREE — get your key at: https://freesound.org/apiv2/apply/

Usage:
  Set environment variable: FREESOUND_API_KEY=your_key_here
  Or set it in the app settings.
"""

import os
import re
import random
import tempfile
import requests
import subprocess
import imageio_ffmpeg

_FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
_BASE = "https://freesound.org/apiv2"
_HEADERS = {"User-Agent": "ClipAI/1.0 (video editing tool)"}
_CACHE = {}  # query -> list of sound dicts


def get_api_key() -> str:
    """Read API key from env variable or config file."""
    # Try environment variable first
    key = os.environ.get("FREESOUND_API_KEY", "")
    if key:
        return key

    # Try config file next to app
    config_paths = [
        os.path.join(os.path.dirname(__file__), "freesound_key.txt"),
        os.path.join(os.path.expanduser("~"), ".clipai_freesound_key"),
    ]
    for path in config_paths:
        if os.path.exists(path):
            with open(path, "r") as f:
                key = f.read().strip()
            if key:
                return key

    return ""


def is_available() -> bool:
    """Returns True if a Freesound API key is configured."""
    return bool(get_api_key())


# ─────────────────────────────────────────────────────────────────────────────
#  Search & Download
# ─────────────────────────────────────────────────────────────────────────────

def search_sounds(query: str, max_results: int = 20, max_duration: float = 5.0,
                  min_rating: float = 3.0) -> list:
    """
    Search Freesound for sounds matching query.
    Returns list of sound dicts with: id, name, previews, duration, avg_rating.
    """
    cache_key = f"{query}|{max_duration}"
    if cache_key in _CACHE:
        return _CACHE[cache_key]

    api_key = get_api_key()
    if not api_key:
        return []

    try:
        params = {
            "query": query,
            "token": api_key,
            "format": "json",
            "page_size": max_results,
            "fields": "id,name,previews,duration,avg_rating,username",
            "filter": f"duration:[0 TO {max_duration}]",
            "sort": "rating_desc",
        }
        r = requests.get(f"{_BASE}/search/text/", params=params,
                         headers=_HEADERS, timeout=12)
        r.raise_for_status()
        data = r.json()
        results = data.get("results", [])

        # Filter by minimum rating
        filtered = [s for s in results if s.get("avg_rating", 0) >= min_rating]
        if not filtered and results:
            filtered = results  # Accept any if none meet rating threshold

        _CACHE[cache_key] = filtered
        return filtered

    except Exception as e:
        print(f"  [Freesound] Search failed for '{query}': {e}")
        return []


def download_preview(sound: dict) -> str:
    """
    Download the HQ preview MP3 for a sound, convert to WAV.
    Returns path to WAV file, or empty string on failure.
    """
    api_key = get_api_key()
    previews = sound.get("previews", {})

    # Prefer HQ, fallback to LQ
    preview_url = (previews.get("preview-hq-mp3") or
                   previews.get("preview-lq-mp3") or "")
    if not preview_url:
        return ""

    try:
        # Add token to URL for authenticated preview access
        if "?" in preview_url:
            url = f"{preview_url}&token={api_key}"
        else:
            url = f"{preview_url}?token={api_key}"

        r = requests.get(url, headers=_HEADERS, timeout=20)
        r.raise_for_status()

        fd, mp3_path = tempfile.mkstemp(suffix=".mp3")
        os.close(fd)
        with open(mp3_path, "wb") as f:
            f.write(r.content)

        fd2, wav_path = tempfile.mkstemp(suffix=".wav")
        os.close(fd2)
        result = subprocess.run(
            [_FFMPEG, "-y", "-i", mp3_path,
             "-acodec", "pcm_s16le", "-ar", "44100", "-ac", "1", wav_path],
            capture_output=True
        )
        try:
            os.remove(mp3_path)
        except Exception:
            pass

        if result.returncode == 0 and os.path.exists(wav_path):
            return wav_path
        return ""

    except Exception as e:
        print(f"  [Freesound] Download failed for '{sound.get('name')}': {e}")
        return ""


def get_sound(query: str, max_duration: float = 4.0) -> str:
    """
    Search and download a random top-rated sound for the query.
    Returns WAV path or empty string if unavailable.
    """
    sounds = search_sounds(query, max_results=15, max_duration=max_duration)
    if not sounds:
        return ""

    # Pick from top 5 results randomly for variety
    pick = random.choice(sounds[:min(5, len(sounds))])
    name = pick.get("name", "?")
    username = pick.get("username", "?")
    print(f"  [Freesound] Fetching: '{name}' by {username}")

    return download_preview(pick)


# ─────────────────────────────────────────────────────────────────────────────
#  Professional SFX Query Library
#  Optimized search queries for freesound.org
# ─────────────────────────────────────────────────────────────────────────────

PROFESSIONAL_QUERIES = {
    # ── Emphasis / Impact sounds per content type ─────────────────────────────
    "emphasis": {
        "podcast": [
            "cinematic bass impact",
            "deep bass hit",
            "low frequency impact",
            "bass thud",
            "sub bass hit",
        ],
        "awareness": [
            "cinematic boom dramatic",
            "epic impact",
            "dramatic hit",
            "tension impact",
            "cinematic thunder hit",
        ],
        "interview": [
            "news sting",
            "broadcast impact",
            "professional whoosh hit",
            "camera shutter click",
            "subtle bass thud",
        ],
        "motivation": [
            "epic power impact",
            "stadium crowd impact",
            "cinematic riser impact",
            "power bass hit",
            "motivational impact",
        ],
        "educational": [
            "notification chime",
            "soft bell ding",
            "magical sparkle",
            "ui chime positive",
            "level up chime",
        ],
    },

    # ── Transition / Whoosh sounds per content type ───────────────────────────
    "whoosh": {
        "podcast": [
            "smooth whoosh transition",
            "air whoosh",
            "cinematic swipe",
            "camera swoosh",
        ],
        "awareness": [
            "cinematic whoosh dark",
            "dramatic swoosh",
            "tension whoosh",
            "deep whoosh",
        ],
        "interview": [
            "camera whoosh",
            "clean whoosh transition",
            "news swoosh",
            "professional whoosh",
        ],
        "motivation": [
            "epic whoosh",
            "power swoosh",
            "fast cinematic swoosh",
            "impact whoosh",
        ],
        "educational": [
            "soft whoosh",
            "page turn swoosh",
            "light whoosh",
            "ui transition whoosh",
        ],
    },

    # ── Hook slam sounds (the big 3-second hit) ───────────────────────────────
    "hook": {
        "podcast": [
            "cinematic bass boom",
            "deep impact bass hit",
            "dramatic bass hit",
        ],
        "awareness": [
            "epic cinematic boom",
            "dramatic orchestral hit",
            "tension boom dramatic",
        ],
        "interview": [
            "cinematic hit sharp",
            "broadcast sting",
            "professional boom hit",
        ],
        "motivation": [
            "epic power boom",
            "motivational cinematic hit",
            "crowd roar impact",
        ],
        "educational": [
            "positive chime intro",
            "magical intro sound",
            "notification intro",
        ],
    },

    # ── Ambient tension background (hook intro atmosphere) ────────────────────
    "tension": {
        "podcast": ["subtle tension drone", "low hum ambience", "atmospheric drone"],
        "awareness": ["dark tension drone", "suspense atmosphere", "cinematic tension"],
        "interview": ["minimal tension hum", "studio ambience subtle", "low drone subtle"],
        "motivation": ["epic tension build", "power drone rising", "cinematic riser"],
        "educational": ["calm ambience", "soft background hum", "gentle atmosphere"],
    },
}


def get_professional_emphasis(content_type: str) -> str:
    """Get an emphasis/impact sound for professional content. Returns WAV path."""
    queries = PROFESSIONAL_QUERIES["emphasis"].get(content_type,
              PROFESSIONAL_QUERIES["emphasis"]["podcast"])
    query = random.choice(queries)
    return get_sound(query, max_duration=3.0)


def get_professional_whoosh(content_type: str) -> str:
    """Get a transition whoosh for professional content. Returns WAV path."""
    queries = PROFESSIONAL_QUERIES["whoosh"].get(content_type,
              PROFESSIONAL_QUERIES["whoosh"]["podcast"])
    query = random.choice(queries)
    return get_sound(query, max_duration=3.0)


def get_professional_hook(content_type: str) -> str:
    """Get the hook slam sound for professional content. Returns WAV path."""
    queries = PROFESSIONAL_QUERIES["hook"].get(content_type,
              PROFESSIONAL_QUERIES["hook"]["podcast"])
    query = random.choice(queries)
    return get_sound(query, max_duration=4.0)


def get_tension_drone(content_type: str, duration_ms: int = 3000) -> str:
    """Get a tension drone background. Returns WAV path."""
    queries = PROFESSIONAL_QUERIES["tension"].get(content_type,
              PROFESSIONAL_QUERIES["tension"]["podcast"])
    query = random.choice(queries)
    return get_sound(query, max_duration=max(5.0, duration_ms / 1000 + 1))
