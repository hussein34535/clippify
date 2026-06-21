"""
sounds.py — Sound Effects Engine for Clippify
Priority system for professional content (podcast/interview/awareness/motivation/educational):
  1. Freesound.org API  → Real professional sounds (requires free API key)
  2. sfx_synth.py       → Local synthesis fallback (numpy, always available)

For comedy content only:
  → myinstants.com (vine boom, bruh, etc. are appropriate for comedy)
"""

import os
import re
import random
import tempfile
import subprocess
import requests
import imageio_ffmpeg
from pydub import AudioSegment

_FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()
AudioSegment.converter = _FFMPEG
_FFPROBE = _FFMPEG.replace("ffmpeg", "ffprobe")
if os.path.exists(_FFPROBE):
    AudioSegment.ffprobe = _FFPROBE

_HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
_CACHE = {}


# ─────────────────────────────────────────────────────────────────────────────
#  Comedy-Only SFX Library (myinstants.com) — COMEDY CONTENT ONLY
# ─────────────────────────────────────────────────────────────────────────────

COMEDY_SFX = {
    "hook":       ["vine boom", "cartoon impact", "slide whistle", "boing comedy"],
    "transition": ["slide whistle down", "boing spring", "funny whoosh", "cartoon transition"],
    "emphasis":   ["vine boom", "bruh", "anime wow", "fart", "crickets", "air horn"],
    "trending":   ["vine boom", "bruh", "skibidi", "ohio rizz", "npc sound", "air horn"],
}


# ─────────────────────────────────────────────────────────────────────────────
#  myinstants.com Download Engine (Comedy Only)
# ─────────────────────────────────────────────────────────────────────────────

def _search_myinstants(query: str) -> list:
    if query in _CACHE:
        return _CACHE[query]
    url = f"https://www.myinstants.com/en/search/?name={query.replace(' ', '+')}"
    try:
        r = requests.get(url, headers=_HEADERS, timeout=10)
        r.raise_for_status()
        mp3s = re.findall(r"play\('([^']+)'\)", r.text)
        if not mp3s:
            mp3s = re.findall(r"(/media/sounds/[^'\"]+\.mp3)", r.text)
        full_urls = []
        for m in mp3s:
            if m.startswith('/'):
                full_urls.append('https://www.myinstants.com' + m)
            else:
                full_urls.append(m)
        unique_urls = list(set(full_urls))
        if unique_urls:
            _CACHE[query] = unique_urls
        return unique_urls
    except Exception as e:
        print(f"  [SFX] myinstants search failed for '{query}': {e}")
        return []


def _download_sfx_url(url: str) -> AudioSegment:
    r = requests.get(url, headers=_HEADERS, timeout=15)
    r.raise_for_status()
    fd, mp3_path = tempfile.mkstemp(suffix=".mp3")
    os.close(fd)
    with open(mp3_path, "wb") as f:
        f.write(r.content)
    fd2, wav_path = tempfile.mkstemp(suffix=".wav")
    os.close(fd2)
    subprocess.run(
        [_FFMPEG, "-y", "-i", mp3_path, "-acodec", "pcm_s16le",
         "-ar", "44100", "-ac", "1", wav_path],
        capture_output=True, check=True
    )
    audio = AudioSegment.from_wav(wav_path)
    try:
        os.remove(mp3_path)
        os.remove(wav_path)
    except Exception:
        pass
    return audio


def _get_comedy_sound(query: str) -> AudioSegment:
    urls = _search_myinstants(query)
    if not urls:
        raise RuntimeError(f"No comedy sounds found for: {query}")
    return _download_sfx_url(random.choice(urls[:15]))


# ─────────────────────────────────────────────────────────────────────────────
#  Professional Sound Loader (Freesound -> Synth fallback)
# ─────────────────────────────────────────────────────────────────────────────

def _load_wav(wav_path: str) -> AudioSegment:
    """Load WAV file into AudioSegment and clean up."""
    if not wav_path or not os.path.exists(wav_path):
        return None
    try:
        seg = AudioSegment.from_wav(wav_path)
        try:
            os.remove(wav_path)
        except Exception:
            pass
        return seg
    except Exception:
        return None


def _get_professional_emphasis(content_type: str) -> AudioSegment:
    """
    Get emphasis sound: try Freesound first, then fall back to local synth.
    """
    # Try Freesound.org
    try:
        from freesound_client import is_available, get_professional_emphasis
        if is_available():
            wav = get_professional_emphasis(content_type)
            seg = _load_wav(wav)
            if seg:
                print(f"  [SFX] Freesound emphasis [{content_type}]: OK ({len(seg)}ms)")
                return seg
    except Exception as e:
        print(f"  [SFX] Freesound emphasis failed ({e}), using synth...")

    # Fallback to local synth
    try:
        from sfx_synth import generate_emphasis
        wav = generate_emphasis(content_type)
        seg = _load_wav(wav)
        if seg:
            print(f"  [SFX] Synth emphasis [{content_type}]: OK ({len(seg)}ms)")
            return seg
    except Exception as e:
        print(f"  [SFX] Synth emphasis also failed ({e})")

    return AudioSegment.silent(duration=500)


def _get_professional_whoosh(content_type: str) -> AudioSegment:
    """
    Get whoosh: try Freesound first, then fall back to local synth.
    """
    try:
        from freesound_client import is_available, get_professional_whoosh
        if is_available():
            wav = get_professional_whoosh(content_type)
            seg = _load_wav(wav)
            if seg:
                print(f"  [SFX] Freesound whoosh [{content_type}]: OK ({len(seg)}ms)")
                return seg
    except Exception as e:
        print(f"  [SFX] Freesound whoosh failed ({e}), using synth...")

    try:
        from sfx_synth import generate_whoosh
        wav = generate_whoosh(content_type)
        seg = _load_wav(wav)
        if seg:
            print(f"  [SFX] Synth whoosh [{content_type}]: OK ({len(seg)}ms)")
            return seg
    except Exception as e:
        print(f"  [SFX] Synth whoosh failed ({e})")

    return AudioSegment.silent(duration=400)


def _get_professional_hook(content_type: str) -> AudioSegment:
    """
    Get hook slam: try Freesound first, then fall back to local synth.
    """
    try:
        from freesound_client import is_available, get_professional_hook
        if is_available():
            wav = get_professional_hook(content_type)
            seg = _load_wav(wav)
            if seg:
                print(f"  [SFX] Freesound hook [{content_type}]: OK ({len(seg)}ms)")
                return seg
    except Exception as e:
        print(f"  [SFX] Freesound hook failed ({e}), using synth...")

    try:
        from sfx_synth import generate_hook_slam
        wav = generate_hook_slam(content_type)
        seg = _load_wav(wav)
        if seg:
            return seg
    except Exception as e:
        print(f"  [SFX] Synth hook failed ({e})")

    return AudioSegment.silent(duration=800)


def _get_professional_tension(content_type: str, duration_ms: int = 3000) -> AudioSegment:
    """
    Get tension drone: try Freesound first, then fall back to local synth.
    """
    try:
        from freesound_client import is_available, get_tension_drone
        if is_available():
            wav = get_tension_drone(content_type, duration_ms)
            seg = _load_wav(wav)
            if seg:
                print(f"  [SFX] Freesound tension drone [{content_type}]: OK")
                return seg
    except Exception as e:
        print(f"  [SFX] Freesound tension drone failed ({e}), using synth...")

    try:
        from sfx_synth import generate_tension_drone
        wav = generate_tension_drone(duration_ms)
        seg = _load_wav(wav)
        if seg:
            return seg
    except Exception as e:
        print(f"  [SFX] Synth tension failed ({e})")

    return AudioSegment.silent(duration=duration_ms)


# ─────────────────────────────────────────────────────────────────────────────
#  Public API
# ─────────────────────────────────────────────────────────────────────────────

def get_whoosh(content_type: str = "podcast") -> AudioSegment:
    """Transition whoosh — professional for serious content, comedy for comedy."""
    if content_type == "comedy":
        try:
            return _get_comedy_sound(random.choice(COMEDY_SFX["transition"]))
        except Exception:
            return AudioSegment.silent(duration=400)
    return _get_professional_whoosh(content_type)


def get_impact(content_type: str = "podcast") -> AudioSegment:
    """Emphasis impact sound — professional for serious content, comedy for comedy."""
    if content_type == "comedy":
        try:
            return _get_comedy_sound(random.choice(COMEDY_SFX["emphasis"]))
        except Exception:
            return AudioSegment.silent(duration=300)
    return _get_professional_emphasis(content_type)


def get_hook_slam(content_type: str = "podcast") -> AudioSegment:
    """Hook slam sound — professional for serious content."""
    if content_type == "comedy":
        try:
            return _get_comedy_sound(random.choice(COMEDY_SFX["hook"]))
        except Exception:
            return AudioSegment.silent(duration=500)
    return _get_professional_hook(content_type)


def get_transition_sound(content_type: str = "podcast") -> AudioSegment:
    """Alias for get_whoosh."""
    return get_whoosh(content_type)


def get_emphasis_sound(content_type: str = "podcast") -> AudioSegment:
    """Alias for get_impact."""
    return get_impact(content_type)


def get_trendy_sound(context_query: str, content_type: str = "podcast") -> AudioSegment:
    """
    Get a sound based on a context query.
    For professional content: uses Freesound/synth (ignores query for professional safety).
    For comedy: downloads from myinstants.
    """
    if content_type == "comedy":
        try:
            q = context_query
            # Normalize known comedy queries
            if q in ["tension drone", "swoosh transition", "low thud"]:
                q = "vine boom"
            return _get_comedy_sound(q)
        except Exception:
            return get_impact("comedy")
    else:
        # Professional: ignore the query string (it might be a comedy sound name)
        # and use the content-type-appropriate professional sound
        return get_impact(content_type)


def get_trending_sfx() -> AudioSegment:
    """Get a random trending viral SFX (comedy style)."""
    query = random.choice(COMEDY_SFX["trending"])
    return _get_comedy_sound(query)


def _load_any_audio(file_path: str) -> AudioSegment:
    """
    Load any audio file safely on Windows by converting it to WAV via bundled FFmpeg
    if direct load fails, bypassing pydub's ffprobe dependency.
    """
    if not file_path or not os.path.exists(file_path):
        return None
    try:
        # If it is WAV, try direct load
        if file_path.lower().endswith(".wav"):
            return AudioSegment.from_wav(file_path)
    except Exception:
        pass

    fd, temp_wav = tempfile.mkstemp(suffix="_temp_load.wav")
    os.close(fd)
    try:
        cmd = [
            _FFMPEG, "-y", "-loglevel", "error",
            "-i", file_path, "-acodec", "pcm_s16le",
            "-ar", "44100", "-ac", "1", temp_wav
        ]
        result = subprocess.run(cmd, capture_output=True, timeout=10)
        if result.returncode == 0 and os.path.exists(temp_wav) and os.path.getsize(temp_wav) > 0:
            return AudioSegment.from_wav(temp_wav)
    except Exception as e:
        print(f"  [SFX] Failed to safely load audio via FFmpeg: {e}")
    finally:
        try:
            if os.path.exists(temp_wav):
                os.remove(temp_wav)
        except Exception:
            pass
    return None


def get_finger_snap() -> AudioSegment:
    """Get a clean, professional finger snap sound."""
    # 1. Look for the integrated file inside the project folder
    integrated_path = os.path.join(os.path.dirname(__file__), "finger_snap_reverb.mp3")
    if os.path.exists(integrated_path):
        try:
            seg = _load_any_audio(integrated_path)
            if seg and len(seg) > 0:
                print(f"  [SFX] Loaded integrated premium finger snap: {integrated_path}")
                return seg + 12
        except Exception as e:
            print(f"  [SFX] Failed to load integrated snap ({e}), trying Downloads...")

    # 2. Fallback to Downloads path
    custom_path = r"C:\Users\husso\Downloads\soundreality-finger-snap-reverb-423222.mp3"
    if os.path.exists(custom_path):
        try:
            seg = _load_any_audio(custom_path)
            if seg and len(seg) > 0:
                print(f"  [SFX] Loaded custom premium finger snap: {custom_path}")
                return seg + 12
        except Exception as e:
            print(f"  [SFX] Failed to load custom finger snap ({e}), falling back to synth...")

    # 3. Fallback to synthesized finger snap
    try:
        from sfx_synth import generate_finger_snap
        wav = generate_finger_snap()
        seg = _load_wav(wav)
        if seg:
            print(f"  [SFX] Synth finger snap: OK ({len(seg)}ms)")
            return seg + 12
    except Exception as e:
        print(f"  [SFX] Synth finger snap failed ({e})")
    return AudioSegment.silent(duration=300)


def build_sfx_mix(total_duration_ms: int, emphasis_times: list,
                  add_whoosh: bool = True, context_queries: list = None,
                  content_type: str = "podcast", hook_end_ms: int = 0,
                  sfx_mode: str = "normal", slow_motion_start_ms: int = 0) -> str:
    """
    Build a complete SFX audio track.
    - sfx_mode 'none': Returns completely silent track.
    - sfx_mode 'hook_only': Places exactly one sound effect at the hook end (if hook exists) and nothing else.
    - Podcast content: If a hook is present, places exactly ONE finger snap at the end of the hook, and NO other sounds.
    - Other content types: Places appropriate professional or comedy SFX.
    """
    mix = AudioSegment.silent(duration=total_duration_ms)
    is_comedy = (content_type == "comedy")

    # ── SFX MODE: NONE ────────────────────────────────────────────────────────
    if sfx_mode == "none":
        print(f"  [SFX] SFX Mode is NONE: creating silent track.")
        fd, path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        mix.export(path, format="wav")
        return path

    # ── SFX MODE: HOOK ONLY ───────────────────────────────────────────────────
    if sfx_mode == "hook_only":
        if hook_end_ms > 0:
            print(f"  [SFX] Hook Only Mode: Adding EXACTLY ONE sound at the end of the hook ({hook_end_ms}ms)")
            try:
                if content_type == "podcast":
                    snd = get_finger_snap()
                    pos = max(0, hook_end_ms - 1600)
                else:
                    snd = get_hook_slam(content_type)
                    pos = max(0, hook_end_ms - 150)
                mix = mix.overlay(snd, position=pos)
            except Exception as e:
                print(f"  [SFX] Hook Only SFX failed: {e}")
        else:
            print(f"  [SFX] Hook Only Mode (no hook): Remaining silent.")
        
        fd, path = tempfile.mkstemp(suffix=".wav")
        os.close(fd)
        mix.export(path, format="wav")
        return path

    # ── PODCAST CUSTOM BEHAVIOR: Exactly 1 snap at the end of the hook ────────
    if content_type == "podcast":
        if hook_end_ms > 0:
            print(f"  [SFX] Podcast Mode: Adding EXACTLY ONE finger snap at the end of the hook ({hook_end_ms}ms)")
            try:
                snap = get_finger_snap()
                # Place the snap before the transition starts
                pos = max(0, hook_end_ms - 1600)
                mix = mix.overlay(snap, position=pos)
            except Exception as e:
                print(f"  [SFX] Podcast finger snap failed: {e}")
            
            # Export and return immediately (no drone, no whooshes, no thuds!)
            fd, path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            mix.export(path, format="wav")
            return path
        else:
            # If no hook, podcast is very sparse: only 1 deep thud/soft chime at the very first transition, nothing else!
            print(f"  [SFX] Podcast Mode (no hook): Sparse SFX, adding at most 1 sound.")
            if emphasis_times:
                first_emp = emphasis_times[0]
                pos = int((first_emp[0] + first_emp[1]) / 2)
                pos = max(0, pos - 150)
                try:
                    imp = get_impact("podcast")
                    mix = mix.overlay(imp, position=pos)
                except Exception:
                    pass
            fd, path = tempfile.mkstemp(suffix=".wav")
            os.close(fd)
            mix.export(path, format="wav")
            return path

    # Detect Freesound availability
    try:
        from freesound_client import is_available
        has_freesound = is_available() and not is_comedy
    except Exception:
        has_freesound = False

    # ── SFX MODE: SPARSE LIMITATION ───────────────────────────────────────────
    if sfx_mode == "sparse" and len(emphasis_times) > 3:
        indices = [0, len(emphasis_times) // 2, len(emphasis_times) - 1]
        indices = sorted(list(set(indices)))
        emphasis_times = [emphasis_times[i] for i in indices]
        if context_queries:
            context_queries = [context_queries[i] for i in indices if i < len(context_queries)]
        print(f"  [SFX] Sparse Mode: limited emphasis hits to {len(emphasis_times)}")

    if not is_comedy:
        source = "Freesound.org" if has_freesound else "local synth"
        print(f"  [SFX] Building PROFESSIONAL SFX mix via {source} for '{content_type}'...")
    else:
        print(f"  [SFX] Building COMEDY SFX mix (myinstants) for '{content_type}'...")

    # ── Ambient tension background (hook intro, first 3 seconds) ─────────────
    if not is_comedy:
        try:
            drone = _get_professional_tension(content_type, min(3000, total_duration_ms))
            drone = drone - 18  # Very quiet background (-18dB)
            mix = mix.overlay(drone, position=0)
            print(f"  [SFX] Tension drone added (hook atmosphere)")
        except Exception as e:
            print(f"  [SFX] Tension drone skipped: {e}")
    else:
        try:
            amb = _get_comedy_sound("funny")
            amb = amb[:3000] - 20
            mix = mix.overlay(amb, position=0)
        except Exception:
            pass

    # ── Opening whoosh ────────────────────────────────────────────────────────
    if add_whoosh:
        try:
            w = get_whoosh(content_type)
            mix = mix.overlay(w, position=50)
            print(f"  [SFX] Opening whoosh added")
        except Exception as e:
            print(f"  [SFX] whoosh failed: {e}")

    # ── Emphasis hits at key moments ──────────────────────────────────────────
    for idx, (start_ms, end_ms) in enumerate(emphasis_times):
        pos = int((start_ms + end_ms) / 2)
        pos = max(0, pos - 150)
        try:
            if is_comedy:
                # Comedy: use context queries if available
                if context_queries and idx < len(context_queries):
                    imp = get_trendy_sound(context_queries[idx], content_type)
                else:
                    imp = get_impact(content_type)
            else:
                # Professional: always use proper synth/freesound sounds
                imp = get_impact(content_type)

            mix = mix.overlay(imp, position=pos)
        except Exception as e:
            print(f"  [SFX] emphasis hit {idx+1} failed: {e}")

        # Add transition whoosh before each emphasis (disabled in sparse mode)
        if sfx_mode != "sparse" and pos > 400:
            try:
                w2 = get_whoosh(content_type)
                mix = mix.overlay(w2, position=pos - 350)
            except Exception as e:
                print(f"  [SFX] whoosh2 failed: {e}")

    # ── Slow-motion Bass Drop SFX Overlay ──────────────────────────────────────
    if slow_motion_start_ms > 0 and sfx_mode != "none":
        try:
            from sfx_synth import synth_bass_drop, _write_wav
            samples = synth_bass_drop(1500)
            fd_b, path_b = tempfile.mkstemp(suffix=".wav")
            os.close(fd_b)
            _write_wav(samples, path_b)
            bass_drop_audio = AudioSegment.from_wav(path_b)
            try:
                os.remove(path_b)
            except Exception:
                pass
            
            # Boost volume a bit
            bass_drop_audio = bass_drop_audio + 6
            # Overlay slightly before the start to align the sweep peak
            drop_pos = max(0, slow_motion_start_ms - 200)
            mix = mix.overlay(bass_drop_audio, position=drop_pos)
            print(f"  [SFX] Added dramatic bass drop SFX at {slow_motion_start_ms}ms for slow-motion peak.")
        except Exception as e:
            print(f"  [SFX] Failed to add slow-motion bass drop SFX: {e}")

    fd, path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    mix.export(path, format="wav")
    print(f"  [SFX] SFX mix complete: {len(emphasis_times)} emphasis hits -> {path}")
    return path
