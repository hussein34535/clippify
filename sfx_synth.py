"""
sfx_synth.py — Professional SFX Synthesizer for ClipAI
Generates high-quality, professional sound effects locally using numpy.
NO internet required. NO meme sounds. Pure synthesis.
"""

import numpy as np
import tempfile
import os
import struct
import wave

SR = 44100  # Sample rate


def _write_wav(samples: np.ndarray, path: str, sr: int = SR):
    """Write float32 numpy array (range -1..1) to a 16-bit WAV file."""
    samples = np.clip(samples, -1.0, 1.0)
    pcm = (samples * 32767).astype(np.int16)
    with wave.open(path, 'w') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def _make_temp_wav(samples: np.ndarray, sr: int = SR) -> str:
    fd, path = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    _write_wav(samples, path, sr)
    return path


# ─────────────────────────────────────────────────────────────────────────────
#  Envelope helpers
# ─────────────────────────────────────────────────────────────────────────────

def _envelope(n: int, attack: float = 0.01, decay: float = 0.2,
              sustain: float = 0.3, release: float = 0.5) -> np.ndarray:
    """ADSR envelope. All values are fractions of total length n."""
    env = np.zeros(n)
    a = int(attack * n)
    d = int(decay * n)
    s = int(sustain * n)
    r = n - a - d - s
    if a > 0:
        env[:a] = np.linspace(0, 1, a)
    if d > 0:
        env[a:a+d] = np.linspace(1, 0.5, d)
    if s > 0:
        env[a+d:a+d+s] = 0.5
    if r > 0:
        env[a+d+s:] = np.linspace(0.5, 0, r)
    return env


def _fade_out(samples: np.ndarray, ms: int = 50) -> np.ndarray:
    n_fade = min(int(SR * ms / 1000), len(samples))
    samples[-n_fade:] *= np.linspace(1, 0, n_fade)
    return samples


def _fade_in(samples: np.ndarray, ms: int = 10) -> np.ndarray:
    n_fade = min(int(SR * ms / 1000), len(samples))
    samples[:n_fade] *= np.linspace(0, 1, n_fade)
    return samples


# ─────────────────────────────────────────────────────────────────────────────
#  Professional SFX Generators
# ─────────────────────────────────────────────────────────────────────────────

def synth_deep_impact(duration_ms: int = 800) -> np.ndarray:
    """
    Deep cinematic bass impact — the signature professional hit.
    Sub-bass punch with fast attack and exponential decay.
    Used for: podcast emphasis, motivation, interview key moments.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Sub-bass sweep from 80Hz down to 30Hz
    freq_sweep = np.linspace(80, 30, n)
    phase = 2 * np.pi * np.cumsum(freq_sweep) / SR
    bass = np.sin(phase)

    # Add second harmonic for body
    freq2 = freq_sweep * 2
    phase2 = 2 * np.pi * np.cumsum(freq2) / SR
    bass += 0.4 * np.sin(phase2)

    # Exponential decay envelope
    env = np.exp(-t * 6)
    bass *= env

    # Normalize
    bass /= np.max(np.abs(bass) + 1e-9)
    return _fade_out(bass, 80)


def synth_whoosh(duration_ms: int = 500, direction: str = "up") -> np.ndarray:
    """
    Cinematic whoosh/swoosh transition sound.
    direction: 'up' = rising, 'down' = falling, 'through' = pass-through.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, 1, n)

    # Noise band with frequency sweep
    noise = np.random.randn(n)

    if direction == "up":
        freq_env = np.exp(t * 3)  # exponential rise
    elif direction == "down":
        freq_env = np.exp((1 - t) * 3)
    else:  # through
        freq_env = np.exp(-((t - 0.5) ** 2) * 8) + 0.2

    # Simple LP filter simulation via cumsum
    filtered = np.cumsum(noise * freq_env) * 0.001

    # Volume envelope: peak in middle
    if direction == "through":
        vol_env = np.exp(-((t - 0.4) ** 2) * 12)
    elif direction == "up":
        vol_env = t ** 0.5
    else:
        vol_env = (1 - t) ** 0.5

    filtered *= vol_env

    # Normalize
    if np.max(np.abs(filtered)) > 1e-9:
        filtered /= np.max(np.abs(filtered))

    return _fade_in(_fade_out(filtered, 30), 10)


def synth_tension_drone(duration_ms: int = 3000) -> np.ndarray:
    """
    Subtle tension/suspense drone — perfect for hook intro background.
    Deep, atmospheric, professional. NOT comedic.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Low drone at 55Hz (A1) with slight vibrato
    vibrato = 1 + 0.002 * np.sin(2 * np.pi * 4 * t)  # 4Hz subtle vibrato
    drone = np.sin(2 * np.pi * 55 * t * vibrato)

    # Add subtle second harmonic
    drone += 0.3 * np.sin(2 * np.pi * 110 * t)

    # Add a very soft, slow-rising noise layer
    noise = np.random.randn(n) * 0.05
    # Smooth the noise
    smooth_noise = np.convolve(noise, np.ones(int(SR * 0.05)) / int(SR * 0.05), mode='same')

    drone += smooth_noise

    # Fade in slowly, sustain, fade out
    env = np.ones(n)
    fade_in_n = int(SR * 0.5)
    fade_out_n = int(SR * 0.8)
    env[:fade_in_n] = np.linspace(0, 1, fade_in_n)
    env[-fade_out_n:] = np.linspace(1, 0, fade_out_n)
    drone *= env

    # Very quiet — meant as background
    drone *= 0.3

    if np.max(np.abs(drone)) > 1e-9:
        drone /= np.max(np.abs(drone))
    drone *= 0.3  # Keep it quiet

    return drone


def synth_cinematic_boom(duration_ms: int = 1200) -> np.ndarray:
    """
    Epic cinematic boom — for motivation/awareness content.
    Low frequency explosion-style hit.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Layered bass hits
    # Layer 1: sub-bass punch at 40Hz
    sub = np.sin(2 * np.pi * 40 * t) * np.exp(-t * 4)

    # Layer 2: mid-bass body at 120Hz
    mid = np.sin(2 * np.pi * 120 * t) * np.exp(-t * 8) * 0.5

    # Layer 3: attack transient (noise burst)
    noise_burst_len = int(SR * 0.05)
    noise_burst = np.random.randn(n)
    noise_env = np.exp(-t * 40)
    transient = noise_burst * noise_env * 0.3

    boom = sub + mid + transient

    # Normalize
    if np.max(np.abs(boom)) > 1e-9:
        boom /= np.max(np.abs(boom))

    return _fade_out(boom, 200)


def synth_news_sting(duration_ms: int = 600) -> np.ndarray:
    """
    Clean news/interview sting — professional, sharp, attention-grabbing.
    High-frequency metallic ping.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Main tone at 880Hz (A5) — clean and professional
    tone = np.sin(2 * np.pi * 880 * t)
    # Overtone for brightness
    tone += 0.3 * np.sin(2 * np.pi * 1760 * t)
    # Sub-tone for warmth
    tone += 0.2 * np.sin(2 * np.pi * 440 * t)

    # Fast decay
    env = np.exp(-t * 12)
    tone *= env

    if np.max(np.abs(tone)) > 1e-9:
        tone /= np.max(np.abs(tone))

    return _fade_out(tone, 50)


def synth_bass_drop(duration_ms: int = 1000) -> np.ndarray:
    """
    Electronic bass drop — energetic but professional.
    For motivation, podcast key moments.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Pitch sweep from 200Hz to 50Hz
    freq = 200 * np.exp(-t * 3) + 50
    phase = 2 * np.pi * np.cumsum(freq) / SR
    drop = np.sin(phase)

    # Distortion/saturation for power
    drop = np.tanh(drop * 2) * 0.7

    # Volume envelope
    env = np.exp(-t * 3)
    drop *= env

    if np.max(np.abs(drop)) > 1e-9:
        drop /= np.max(np.abs(drop))

    return _fade_out(drop, 100)


def synth_soft_chime(duration_ms: int = 800) -> np.ndarray:
    """
    Soft bell/chime — for educational content.
    Gentle, clear, positive.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Bell-like inharmonic partials
    partials = [1.0, 2.756, 5.404, 8.933]
    amps = [1.0, 0.4, 0.2, 0.1]
    base_freq = 523.25  # C5

    chime = np.zeros(n)
    for partial, amp in zip(partials, amps):
        chime += amp * np.sin(2 * np.pi * base_freq * partial * t)

    env = np.exp(-t * 5)
    chime *= env

    if np.max(np.abs(chime)) > 1e-9:
        chime /= np.max(np.abs(chime))

    return _fade_out(chime, 50)


def synth_power_rise(duration_ms: int = 1500) -> np.ndarray:
    """
    Cinematic power rise / build-up — for motivation content.
    Rising noise sweep that builds tension before a drop.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, 1, n)

    # Pitch-rising noise sweep
    noise = np.random.randn(n)
    freq_mod = np.exp(t * 2)  # exponentially rising
    rise = noise * freq_mod

    # Convolve to smooth
    kernel_size = max(1, int(SR * 0.002))
    kernel = np.ones(kernel_size) / kernel_size
    rise = np.convolve(rise, kernel, mode='same')

    # Volume rises
    vol = t ** 2
    rise *= vol

    if np.max(np.abs(rise)) > 1e-9:
        rise /= np.max(np.abs(rise))

    return _fade_in(rise, 100)


def synth_camera_click(duration_ms: int = 150) -> np.ndarray:
    """
    Camera shutter click — sharp, clean, professional.
    Perfect for interview content transitions.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    # Sharp noise transient
    noise = np.random.randn(n)
    env = np.exp(-t * 60)
    click = noise * env

    # Add a subtle mechanical thud
    thud = np.sin(2 * np.pi * 200 * t) * np.exp(-t * 30) * 0.5
    click += thud

    if np.max(np.abs(click)) > 1e-9:
        click /= np.max(np.abs(click))

    return click


def synth_deep_thud(duration_ms: int = 400) -> np.ndarray:
    """
    Low deep thud — subtle emphasis for podcast/interview content.
    Like a microphone thump. Professional.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)

    thud = np.sin(2 * np.pi * 60 * t) * np.exp(-t * 10)
    thud += 0.3 * np.sin(2 * np.pi * 30 * t) * np.exp(-t * 8)

    # Noise texture
    thud += np.random.randn(n) * 0.1 * np.exp(-t * 20)

    if np.max(np.abs(thud)) > 1e-9:
        thud /= np.max(np.abs(thud))

    return _fade_out(thud, 50)


def synth_finger_snap(duration_ms: int = 150) -> np.ndarray:
    """
    Synthesize a clean, professional finger snap.
    Perfect for subtle emphasis or marking the end of a hook in a podcast.
    """
    n = int(SR * duration_ms / 1000)
    t = np.linspace(0, duration_ms / 1000, n)
    
    # 1. High-frequency snap click (friction)
    noise = np.random.randn(n)
    # Fast exponential decay envelope
    click_env = np.exp(-t * 120)
    click = noise * click_env * 0.8
    
    # 2. Medium/low-frequency hand body (resonance)
    # Sine wave decay sweep from 450Hz down to 250Hz
    freq_sweep = np.linspace(450, 250, n)
    phase = 2 * np.pi * np.cumsum(freq_sweep) / SR
    body_env = np.exp(-t * 35)
    body = np.sin(phase) * body_env * 0.4
    
    snap = click + body
    
    if np.max(np.abs(snap)) > 1e-9:
        snap /= np.max(np.abs(snap))
        
    return _fade_out(snap, 20)


# ─────────────────────────────────────────────────────────────────────────────
#  Content-Type SFX Routing
# ─────────────────────────────────────────────────────────────────────────────

# Maps content_type → list of generator functions for emphasis
EMPHASIS_SYNTH = {
    "podcast":     [synth_deep_thud, synth_soft_chime],
    "awareness":   [synth_cinematic_boom, synth_deep_impact, synth_tension_drone],
    "interview":   [synth_soft_chime, synth_deep_thud, synth_camera_click],
    "motivation":  [synth_cinematic_boom, synth_power_rise, synth_bass_drop],
    "educational": [synth_soft_chime, synth_news_sting, synth_deep_thud],
    "comedy":      None,  # comedy uses myinstants for vine boom etc.
}

WHOOSH_SYNTH = {
    "podcast":     lambda: synth_whoosh(500, "through"),
    "awareness":   lambda: synth_whoosh(600, "up"),
    "interview":   lambda: synth_whoosh(400, "through"),
    "motivation":  lambda: synth_whoosh(700, "up"),
    "educational": lambda: synth_whoosh(400, "down"),
    "comedy":      None,
}

HOOK_SYNTH = {
    "podcast":     [synth_deep_impact, synth_cinematic_boom],
    "awareness":   [synth_cinematic_boom, synth_tension_drone],
    "interview":   [synth_cinematic_boom, synth_news_sting],
    "motivation":  [synth_cinematic_boom, synth_power_rise],
    "educational": [synth_news_sting, synth_soft_chime],
    "comedy":      None,
}


def generate_emphasis(content_type: str) -> str:
    """
    Generate a professional emphasis sound for the given content type.
    Returns path to WAV file.
    """
    import random
    generators = EMPHASIS_SYNTH.get(content_type)
    if not generators:
        return None  # comedy uses myinstants

    gen = random.choice(generators)
    samples = gen()
    return _make_temp_wav(samples)


def generate_whoosh(content_type: str) -> str:
    """
    Generate a professional whoosh/transition for the given content type.
    Returns path to WAV file.
    """
    gen = WHOOSH_SYNTH.get(content_type)
    if not gen:
        return None  # comedy uses myinstants

    samples = gen()
    return _make_temp_wav(samples)


def generate_hook_slam(content_type: str) -> str:
    """
    Generate the hook slam sound — the big hit on the 3-second teaser.
    Returns path to WAV file.
    """
    import random
    generators = HOOK_SYNTH.get(content_type)
    if not generators:
        return None  # comedy uses myinstants

    gen = random.choice(generators)
    samples = gen()
    return _make_temp_wav(samples)


def generate_tension_drone(duration_ms: int = 3000) -> str:
    """
    Generate a tension drone background for hook intro.
    Returns path to WAV file.
    """
    samples = synth_tension_drone(duration_ms)
    return _make_temp_wav(samples)


def generate_finger_snap() -> str:
    """Generate a clean, professional finger snap sound. Returns path to WAV file."""
    samples = synth_finger_snap()
    return _make_temp_wav(samples)


def is_professional_type(content_type: str) -> bool:
    """Returns True if this content type should use professional synth SFX (not comedy memes)."""
    return content_type != "comedy"
