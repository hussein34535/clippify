"""sound_forge.py — Advanced procedural sound forge for Clippify.

Pure-stdlib synthesis (wave/math/struct/random — no numpy, no ffmpeg).
Extends scripts/gen_sfx.py with more sophisticated DSP: filtered noise
sweeps, multi-harmonic risers, layered impacts with convolution reverb,
bit-crushed glitch zaps, a synthesized drum kit, evolving chord pads and
vinyl-crackle textures.

Every render is 44.1 kHz mono 16-bit WAV, peak-normalized to -3 dBFS,
with anti-click edge fades. Every generator accepts ``seed`` for
byte-deterministic output (pass a str/int; None = entropy).

Usage:
    sf = SoundForge()
    samples = sf.generate_whoosh(direction="up", seed="w1")
    sf.save_wav(samples, "out/whoosh.wav")
    sf.generate_pack("assets/sfx_forge", sounds=["whoosh_up", "impact"])
"""
from __future__ import annotations

import json
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
BIT_DEPTH = 16
CHANNELS = 1
PEAK_DB = -3.0
PEAK = 10.0 ** (PEAK_DB / 20.0)
FADE_MS = 10
TWO_PI = 2.0 * math.pi


# ─────────────────────────────────────────────────────────────────────────────
#  DSP helpers (pure-python, deterministic)
# ─────────────────────────────────────────────────────────────────────────────

def _fade_edges(samples, ms=FADE_MS):
    """Linear fade-in/out on both edges to kill clicks."""
    n = max(1, int(SR * ms / 1000))
    m = min(n, len(samples))
    for i in range(m):
        g = i / n
        samples[i] *= g
        samples[-1 - i] *= g
    return samples


def _normalize(samples, peak=PEAK):
    """Peak-normalize to target linear peak (default -3 dBFS)."""
    m = max((abs(s) for s in samples), default=0.0)
    if m < 1e-9:
        return samples
    k = peak / m
    for i, s in enumerate(samples):
        samples[i] = s * k
    return samples


def _master(samples):
    return _fade_edges(_normalize(samples))


def _lowpass(samples, cutoff_hz):
    """Static one-pole lowpass."""
    a = 1.0 - math.exp(-TWO_PI * cutoff_hz / SR)
    y = 0.0
    out = []
    for x in samples:
        y += a * (x - y)
        out.append(y)
    return out


def _highpass(samples, cutoff_hz):
    """First-order highpass = input − lowpass."""
    lp = _lowpass(samples, cutoff_hz)
    return [x - l for x, l in zip(samples, lp)]


def _lowpass_sweep(samples, cutoffs):
    """Time-varying one-pole lowpass; cutoffs yields one Hz value per sample."""
    y = 0.0
    out = []
    for x, fc in zip(samples, cutoffs):
        a = 1.0 - math.exp(-TWO_PI * max(10.0, fc) / SR)
        y += a * (x - y)
        out.append(y)
    return out


def _exp_decay(t, rate):
    return math.exp(-t * rate)


def _convolve(signal, kernel):
    """Direct O(n*k) convolution — kept to small kernels on purpose."""
    k = len(kernel)
    out = [0.0] * (len(signal) + k - 1)
    for i, s in enumerate(signal):
        if s == 0.0:
            continue
        for j, kj in enumerate(kernel):
            out[i + j] += s * kj
    del out[len(signal):]
    return out


def _decay_kernel(taps, tau_sec):
    """Normalized exponentially-decaying impulse response (reverb smear)."""
    kern = [_exp_decay(j / SR, 1.0 / tau_sec) for j in range(taps)]
    s = sum(kern)
    return [v / s for v in kern]


def _clamp01(x, lo=-1.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


# ─────────────────────────────────────────────────────────────────────────────
#  SoundForge
# ─────────────────────────────────────────────────────────────────────────────

class SoundForge:
    """Advanced procedural SFX synthesizer (stdlib-only, seedable)."""

    # ── whoosh ───────────────────────────────────────────────────────────
    def generate_whoosh(self, direction="up", dur=0.8,
                        freq_range=(200, 1200), seed=None):
        """Band-swept filtered-noise whoosh. direction: up|down|through."""
        if direction not in ("up", "down", "through"):
            raise ValueError(f"unknown whoosh direction: {direction!r}")
        f0, f1 = float(freq_range[0]), float(freq_range[1])
        if not (0.0 < f0 < f1):
            raise ValueError("freq_range must be (lo, hi) with 0 < lo < hi")
        if dur <= 0:
            raise ValueError("dur must be positive")

        rnd = random.Random(seed)
        n = int(dur * SR)
        noise = [rnd.uniform(-1.0, 1.0) for _ in range(n)]

        ratio = f1 / f0
        if direction == "up":
            cutoffs = [f0 * ratio ** (i / n) for i in range(n)]
            amp = [(p := i / n) ** 1.4 * (1.0 - p ** 5) for i in range(n)]
        elif direction == "down":
            cutoffs = [f1 * (1.0 / ratio) ** (i / n) for i in range(n)]
            amp = [(1.0 - (p := i / n)) ** 1.4 * (1.0 - (1.0 - p) ** 5)
                   for i in range(n)]
        else:  # through — band rises then falls, energy hump slightly early
            mid = math.sqrt(f0 * f1)
            cutoffs = [f0 + (mid * 1.6 - f0) *
                       math.exp(-(((i / n) - 0.45) ** 2) / 0.08)
                       for i in range(n)]
            amp = [math.exp(-(((i / n) - 0.42) ** 2) / 0.06)
                   for i in range(n)]

        body = _lowpass_sweep(noise, cutoffs)

        # Faint tonal core tracking the sweep adds "air".
        core = []
        ph = 0.0
        for i in range(n):
            p = i / n
            f = cutoffs[i] * (0.55 if direction != "through" else 0.8)
            ph += TWO_PI * f / SR
            core.append(math.sin(ph))
        mixed = []
        for b, c, a in zip(body, core, amp):
            mixed.append((b * 0.85 + c * 0.15) * a)

        return _master(mixed)

    # ── riser ────────────────────────────────────────────────────────────
    def generate_riser(self, dur=2.0, start_freq=100, end_freq=2000,
                       harmonics=3, seed=None):
        """Multi-harmonic accelerating rise with tremolo and noise shimmer."""
        if dur <= 0:
            raise ValueError("dur must be positive")
        if start_freq <= 0 or end_freq <= start_freq:
            raise ValueError("need 0 < start_freq < end_freq")
        harmonics = int(harmonics)
        if harmonics < 1:
            raise ValueError("harmonics must be >= 1")

        rnd = random.Random(seed)
        n = int(dur * SR)
        ratio = end_freq / start_freq
        norm = sum(1.0 / h for h in range(1, harmonics + 1))
        out = []
        ph = 0.0
        shimmer_ph = 0.0
        for i in range(n):
            p = i / n
            # Super-exponential curve → perceived acceleration.
            f = start_freq * ratio ** (p ** 1.6)
            ph += TWO_PI * f / SR
            s = 0.0
            for h in range(1, harmonics + 1):
                s += math.sin(ph * h) / h
            s /= norm
            trem = 0.75 + 0.25 * math.sin(TWO_PI * (6.0 + 10.0 * p) * p * dur)
            shimmer_ph += TWO_PI * (f * 1.5) / SR
            shimmer = 0.06 * p * (rnd.uniform(-1.0, 1.0) +
                                  0.5 * math.sin(shimmer_ph))
            out.append((s * trem + shimmer) * (0.30 + 0.70 * p))
        return _master(out)

    # ── impact ───────────────────────────────────────────────────────────
    def generate_impact(self, dur=0.5, punch=0.8, sub_freq=55, seed=None):
        """Layered hit: sub thump + convolved noise burst + reverb tail."""
        if dur <= 0:
            raise ValueError("dur must be positive")
        punch = min(1.0, max(0.1, float(punch)))
        if sub_freq <= 0:
            raise ValueError("sub_freq must be positive")

        rnd = random.Random(seed)
        n = int(dur * SR)
        t_last = dur

        # Layer 1 — pitch-dropping sub thump.
        sub = []
        ph = 0.0
        for i in range(n):
            t = i / SR
            p = min(1.0, t / 0.12)
            f = sub_freq * (1.6 - 0.6 * p)
            ph += TWO_PI * f / SR
            sub.append(math.tanh(1.4 * math.sin(ph)) *
                       _exp_decay(t, 5.0 + 5.0 * punch))

        # Layer 2 — sharp transient, smeared by short convolution
        # (early-reflection style reverb).
        nb = min(n, int(0.09 * SR))
        burst_raw = [rnd.uniform(-1.0, 1.0) *
                     _exp_decay(i / SR, 45.0 + 30.0 * punch)
                     for i in range(nb)]
        burst = _convolve(burst_raw, _decay_kernel(97, 0.004))[:n]

        # Layer 3 — dark decaying reverb tail.
        tail_noise = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
        tail_cutoffs = [1400.0 - 1100.0 * (i / n) for i in range(n)]
        tail_lp = _lowpass_sweep(tail_noise, tail_cutoffs)
        tail = []
        td = 0.025
        for i in range(n):
            t = i / SR
            e = 0.0 if t <= td else _exp_decay(t - td, 3.2 + 2.0 * punch)
            tail.append(tail_lp[i] * e)

        mix = []
        for i in range(n):
            v = sub[i] * (0.55 + 0.45 * punch)
            if i < len(burst):
                v += burst[i] * 0.65
            v += tail[i] * 0.38
            mix.append(_clamp01(v))
        return _master(mix)

    # ── brainzap ─────────────────────────────────────────────────────────
    def generate_brainzap(self, dur=0.3, seed=None):
        """Glitchy bit-crushed zap: swept saw, sample-hold, quantize, glitches."""
        if dur <= 0:
            raise ValueError("dur must be positive")
        rnd = random.Random(seed)
        n = int(dur * SR)

        raw = []
        ph = 0.0
        for i in range(n):
            p = i / n
            f = 2600.0 * (0.06 ** p)
            ph += TWO_PI * f / SR
            cyc = (ph / TWO_PI) % 1.0
            saw = 2.0 * cyc - 1.0
            ring = 0.8 + 0.2 * math.sin(TWO_PI * 37.0 * i / SR)
            raw.append(saw * ring * _exp_decay(p * dur, 9.0))

        # Bit crush: sample-and-hold decimation + coarse quantization + drive.
        hold = max(1, int(SR / 9000))
        levels = 14.0
        crushed = []
        held = 0.0
        for i in range(n):
            if i % hold == 0:
                held = raw[i]
            v = math.tanh(held * 3.0) / math.tanh(3.0)
            crushed.append(_clamp01(round(v * levels) / levels))

        # Glitch surgery: reverse a few random slices.
        for _ in range(4):
            if n < 8:
                break
            start = rnd.randrange(0, n - 2)
            ln = rnd.randrange(min(4, n - 1 - start), max(5, n // 3)) \
                if n > 12 else 2
            end = min(n, start + ln)
            seg = crushed[start:end]
            seg.reverse()
            crushed[start:end] = seg
        return _master(crushed)

    # ── drum hits ────────────────────────────────────────────────────────
    DRUM_DURATIONS = {"kick": 0.50, "snare": 0.40, "hihat": 0.15}

    def generate_drum_hit(self, type="kick", pitch=1.0, seed=None):
        """Synthesized kick / snare / hihat. pitch scales tuning."""
        if type not in self.DRUM_DURATIONS:
            raise ValueError(
                f"unknown drum type: {type!r} "
                f"(expected one of {sorted(self.DRUM_DURATIONS)})")
        if pitch <= 0:
            raise ValueError("pitch must be positive")

        rnd = random.Random(seed)
        dur = self.DRUM_DURATIONS[type]
        n = int(dur * SR)

        if type == "kick":
            out = []
            ph = 0.0
            for i in range(n):
                t = i / SR
                p = min(1.0, t / 0.08)
                f = (160.0 - 112.0 * p) * pitch
                ph += TWO_PI * f / SR
                body = math.tanh(1.6 * math.sin(ph)) * _exp_decay(t, 11.0)
                click = rnd.uniform(-1.0, 1.0) * _exp_decay(t, 300.0) * 0.4
                out.append(body + click)

        elif type == "snare":
            noise = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
            snap = _highpass(noise, 1400.0)
            out = []
            ph1 = ph2 = 0.0
            for i in range(n):
                t = i / SR
                ph1 += TWO_PI * 190.0 * pitch / SR
                ph2 += TWO_PI * 335.0 * pitch / SR
                body = 0.5 * (math.sin(ph1) + 0.7 * math.sin(ph2)) \
                    * _exp_decay(t, 20.0)
                out.append(_clamp01(body + 0.9 * snap[i] *
                                    _exp_decay(t, 24.0)))

        else:  # hihat — 808-style inharmonic square bank, highpassed
            ratios = (2.0, 3.0, 4.16, 5.43, 6.79, 8.21)
            base = 40.0 * pitch
            metal = []
            for i in range(n):
                t = i / SR
                s = 0.0
                for r in ratios:
                    s += math.copysign(1.0,
                                       math.sin(TWO_PI * base * r * t))
                metal.append(s / len(ratios) * _exp_decay(t, 42.0))
            bright = _highpass(metal, 7000.0)
            ping = [rnd.uniform(-1.0, 1.0) * _exp_decay(i / SR, 250.0) * 0.25
                    for i in range(n)]
            out = [_clamp01(b * 0.9 + pg) for b, pg in zip(bright, ping)]

        return _master(out)

    # ── ambient pad ──────────────────────────────────────────────────────
    def generate_ambient_pad(self, dur=3.0, chord=(220.0, 277.0, 330.0),
                             evolution=0.3, seed=None):
        """Evolving detuned chord pad with per-voice LFO breathing."""
        if dur <= 0:
            raise ValueError("dur must be positive")
        chord = tuple(float(f) for f in chord)
        if not chord or any(f <= 0 for f in chord):
            raise ValueError("chord must be non-empty positive frequencies")
        evolution = min(1.0, max(0.0, float(evolution)))

        rnd = random.Random(seed)
        n = int(dur * SR)
        att = max(1, int(n * 0.32))
        rel = max(1, int(n * 0.34))

        voices = []
        for idx, f in enumerate(chord):
            voices.append({
                "f": f,
                "lfo_hz": 0.07 + rnd.uniform(0.0, 0.22),
                "lfo_ph": rnd.uniform(0.0, TWO_PI),
                "det_ph": rnd.uniform(0.0, TWO_PI),
            })

        out = [0.0] * n
        for v in voices:
            ph_l = ph_r = 0.0
            for i in range(n):
                p = i / n
                drift = 1.0 + evolution * 0.006 * \
                    math.sin(TWO_PI * 0.11 * p * dur + v["det_ph"])
                fl = v["f"] * drift * 1.0006
                fr = v["f"] * drift * 0.9994
                ph_l += TWO_PI * fl / SR
                ph_r += TWO_PI * fr / SR
                lfo = 1.0 - (0.05 + 0.18 * evolution) * \
                    (0.5 + 0.5 * math.sin(v["lfo_ph"] +
                                          TWO_PI * v["lfo_hz"] * p * dur))
                bright_h = evolution * (0.10 + 0.22 * p)
                tone = 0.5 * (math.sin(ph_l) + math.sin(ph_r)) + \
                    bright_h * math.sin(2.0 * ph_l)
                env = 1.0
                if i < att:
                    env = 0.5 - 0.5 * math.cos(math.pi * i / att)
                elif i > n - rel:
                    env = 0.5 - 0.5 * math.cos(math.pi * (n - i) / rel)
                out[i] += tone * lfo * env / len(voices)
        return _master(out)

    # ── vinyl crackle ────────────────────────────────────────────────────
    def generate_vinyl_crackle(self, dur=2.0, density=0.3, seed=None):
        """Surface-noise floor sprinkled with Poisson-ish dust pops."""
        if dur <= 0:
            raise ValueError("dur must be positive")
        density = min(1.0, max(0.0, float(density)))

        rnd = random.Random(seed)
        n = int(dur * SR)

        floor_white = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
        hiss = _lowpass(floor_white, 2200.0)
        rumble_src = [rnd.uniform(-1.0, 1.0) for _ in range(n)]
        rumble = _lowpass(rumble_src, 110.0)
        out = [hiss[i] * 0.16 + rumble[i] * 0.28 for i in range(n)]

        expected = int(density * dur * 90)
        for _ in range(expected):
            pos = rnd.randrange(0, n)
            ln = rnd.randint(24, 170)
            amp = rnd.uniform(0.35, 1.0) * (0.4 + 0.6 * density)
            flip = 1.0 if rnd.random() < 0.5 else -1.0
            for j in range(min(ln, n - pos)):
                out[pos + j] += flip * amp * math.cos(math.pi * j / ln) \
                    * _exp_decay(j / SR, 900.0)
        return _master(out)

    # ── rendering / packing ──────────────────────────────────────────────
    def save_wav(self, samples, path):
        """Write float samples [-1,1] as 44.1 kHz mono 16-bit WAV."""
        ints = [max(-32768, min(32767, int(s * 32767))) for s in samples]
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as w:
            w.setnchannels(CHANNELS)
            w.setsampwidth(BIT_DEPTH // 8)
            w.setframerate(SR)
            w.writeframes(struct.pack(f"<{len(ints)}h", *ints))
        return path

    GENERATOR_REGISTRY = {
        "whoosh_up":       ("generate_whoosh", {"direction": "up"}),
        "whoosh_down":     ("generate_whoosh", {"direction": "down"}),
        "whoosh_through":  ("generate_whoosh", {"direction": "through"}),
        "riser":           ("generate_riser", {}),
        "impact":          ("generate_impact", {}),
        "brainzap":        ("generate_brainzap", {}),
        "kick":            ("generate_drum_hit", {"type": "kick"}),
        "snare":           ("generate_drum_hit", {"type": "snare"}),
        "hihat":           ("generate_drum_hit", {"type": "hihat"}),
        "pad":             ("generate_ambient_pad", {}),
        "vinyl_crackle":   ("generate_vinyl_crackle", {}),
    }

    def generate_pack(self, output_dir, sounds=None, seed=42):
        """Batch-render named sounds + manifest.json. Returns {name: Path}.

        Per-sound seeds are derived deterministically from (seed, name),
        so a pack regenerates byte-identical files for the same seed.
        """
        names = list(self.GENERATOR_REGISTRY) if sounds is None else list(sounds)
        unknown = [s for s in names if s not in self.GENERATOR_REGISTRY]
        if unknown:
            raise ValueError(
                f"unknown sound(s) {unknown}; "
                f"available: {sorted(self.GENERATOR_REGISTRY)}")

        out_dir = Path(output_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        written = {}
        manifest = []
        for name in names:
            method, kwargs = self.GENERATOR_REGISTRY[name]
            samples = getattr(self, method)(seed=f"{seed}|{name}", **kwargs)
            fname = f"{name}.wav"
            self.save_wav(samples, out_dir / fname)
            written[name] = out_dir / fname
            manifest.append({
                "name": name,
                "file": fname,
                "duration_sec": round(len(samples) / SR, 3),
                "peak_db": PEAK_DB,
            })

        (out_dir / "manifest.json").write_text(json.dumps({
            "sr": SR,
            "bit_depth": BIT_DEPTH,
            "channels": CHANNELS,
            "seed": seed,
            "license": "Generated in-app (own work, CC0-dedicated)",
            "sounds": manifest,
        }, ensure_ascii=False, indent=2), encoding="utf-8")
        return written
