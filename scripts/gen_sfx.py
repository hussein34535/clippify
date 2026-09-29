"""CreativeForge-SoundForge â€” offline procedural SFX pack generator.

Pure stdlib synthesis (no ffmpeg/pydub dependency). Deterministic output
(seed=42 by default) so regenerated packs stay byte-similar.

Usage:
    python scripts/gen_sfx.py [--out assets/sfx] [--seed 42]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
import wave
from pathlib import Path

SR = 44100
PEAK = 0.70          # target peak (linear)
FADE_MS = 10         # anti-click edge fade


# â”€â”€ DSP helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def _fade_edges(samples):
    n = max(1, int(SR * FADE_MS / 1000))
    for i in range(min(n, len(samples))):
        g = i / n
        samples[i] *= g
        samples[-1 - i] *= g
    return samples


def _normalize(samples, peak=PEAK):
    m = max(1e-9, max(abs(s) for s in samples))
    k = peak / m
    return [s * k for s in samples]


def _exp_decay(t, rate):
    return math.exp(-t * rate)


def _sweep(t0, t1, dur, f_start, f_end, curve="lin"):
    """Phase-continuous frequency sweep generator helper."""
    n = int(dur * SR)
    phase = 0.0
    out = []
    for i in range(n):
        p = i / max(1, n - 1)
        if curve == "exp":
            f = f_start * (f_end / f_start) ** p
        else:
            f = f_start + (f_end - f_start) * p
        phase += 2 * math.pi * f / SR
        yield math.sin(phase), t0 + p * (t1 - t0)


def _lowpass_noise(noise, alpha_schedule):
    """One-pole lowpass over noise; alpha_schedule yields 0..1 per index."""
    y = 0.0
    out = []
    for i, x in enumerate(noise):
        a = min(0.99, max(0.01, alpha_schedule(i)))
        y += a * (x - y)
        out.append(y)
    return out


# â”€â”€ Sound generators â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
# Each returns float samples in [-1, 1].

def s_whoosh_up(dur=0.6, rnd=None):
    n = int(dur * SR)
    noise = [rnd.uniform(-1, 1) for _ in range(n)]
    body = _lowpass_noise(noise, lambda i: 0.02 + 0.35 * (i / n) ** 2)
    tone = []
    ph = 0.0
    for i in range(n):
        ph += 2 * math.pi * (180 + 900 * (i / n) ** 2) / SR
        tone.append(0.25 * math.sin(ph))
    amp = [(i / n) ** 1.5 * (1 - (i / n) ** 6) for i in range(n)]
    return _fade_edges([b * a + t * a for b, t, a in zip(body, tone, amp)])


def s_whoosh_down(dur=0.6, rnd=None):
    return list(reversed(s_whoosh_up(dur, rnd)))


def s_riser(dur=1.4, rnd=None):
    n = int(dur * SR)
    out = []
    ph = 0.0
    for i in range(n):
        p = i / n
        f = 200 * (900 / 200) ** p           # exponential rise 200â†’900Hz
        ph += 2 * math.pi * f / SR
        trem = 0.75 + 0.25 * math.sin(2 * math.pi * 8 * p * dur)
        out.append(math.sin(ph) * trem * (0.35 + 0.65 * p))
    return _fade_edges(out)


def s_impact(dur=0.35, rnd=None):
    n = int(dur * SR)
    noise = [rnd.uniform(-1, 1) for _ in range(n)]
    return _fade_edges([
        0.8 * noise[i] * _exp_decay(i / SR, 14)
        + 0.9 * math.sin(2 * math.pi * 58 * i / SR) * _exp_decay(i / SR, 18)
        for i in range(n)
    ])


def s_pop(dur=0.05, rnd=None):
    n = int(dur * SR)
    return _fade_edges([
        (rnd.uniform(-1, 1) * 0.6 + math.sin(2 * math.pi * 900 * i / SR) * 0.5)
        * _exp_decay(i / SR, 90)
        for i in range(n)
    ])


def s_click(dur=0.012, rnd=None):
    n = int(dur * SR)
    return _fade_edges([
        (1 if i % 2 == 0 else -1) * 0.6 * _exp_decay(i / SR, 400)
        for i in range(n)
    ])


def s_ding(dur=1.0, rnd=None):
    n = int(dur * SR)
    return _fade_edges([
        (
            math.sin(2 * math.pi * 880 * t)
            + 0.55 * math.sin(2 * math.pi * 1320 * t)
            + 0.28 * math.sin(2 * math.pi * 1760 * t)
        ) * _exp_decay(t, 4.5) / 1.83
        for t in (i / SR for i in range(n))
    ])


def s_tick(dur=0.03, rnd=None):
    n = int(dur * SR)
    return _fade_edges([
        math.sin(2 * math.pi * 2400 * i / SR) * _exp_decay(i / SR, 260)
        for i in range(n)
    ])


def s_sub_drop(dur=0.7, rnd=None):
    n = int(dur * SR)
    out = []
    ph = 0.0
    for i in range(n):
        p = i / n
        f = 120 * (40 / 120) ** p
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * _exp_decay(p * dur, 3))
    return _fade_edges(out)


_PENTA = [880.0, 987.77, 1174.66, 1318.51, 1567.98, 1760.0]


def s_sparkle(dur=0.5, rnd=None):
    n = int(dur * SR)
    out = [0.0] * n
    step = int(0.08 * SR)
    for k in range(len(_PENTA)):
        start = k * step
        flen = min(int(0.06 * SR), n - start)
        if flen <= 0:
            break
        f = _PENTA[k]
        for j in range(flen):
            out[start + j] += (
                math.sin(2 * math.pi * f * j / SR) * _exp_decay(j / SR, 30) * 0.8
            )
    return _fade_edges(out)


def _chord_swell(dur, freqs, reverse=False):
    n = int(dur * SR)
    out = []
    for i in range(n):
        p = i / n
        env = math.sin(math.pi * p) ** 1.5      # smooth swell
        s = sum(math.sin(2 * math.pi * f * i / SR) for f in freqs) / len(freqs)
        out.append(s * env)
    if reverse:
        out.reverse()
    return _fade_edges(out)


def s_transition_up(dur=0.5, rnd=None):
    return _chord_swell(dur, [523.25, 659.25, 783.99])


def s_transition_down(dur=0.5, rnd=None):
    return _chord_swell(dur, [783.99, 659.25, 523.25], reverse=True)


SOUNDS = [
    ("whoosh_up",       0.6,  s_whoosh_up),
    ("whoosh_down",     0.6,  s_whoosh_down),
    ("riser",           1.4,  s_riser),
    ("impact",          0.35, s_impact),
    ("pop",             0.05, s_pop),
    ("click",           0.012,s_click),
    ("ding",            1.0,  s_ding),
    ("tick",            0.03, s_tick),
    ("sub_drop",        0.7,  s_sub_drop),
    ("sparkle",         0.5,  s_sparkle),
    ("transition_up",   0.5,  s_transition_up),
    ("transition_down", 0.5,  s_transition_down),
]

MOOD_TAGS = {
    "whoosh_up": ["transition", "energy"],
    "whoosh_down": ["transition"],
    "riser": ["buildup", "hook"],
    "impact": ["hit", "emphasis"],
    "pop": ["ui", "caption"],
    "click": ["ui"],
    "ding": ["success", "ui"],
    "tick": ["ui", "countdown"],
    "sub_drop": ["drop", "punchline"],
    "sparkle": ["magic", "reveal"],
    "transition_up": ["scene-change"],
    "transition_down": ["scene-change"],
}


# â”€â”€ WAV writer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

def write_wav(path: Path, samples):
    ints = [max(-32767, min(32767, int(s * 32767))) for s in samples]
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(struct.pack(f"<{len(ints)}h", *ints))


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate procedural SFX pack")
    ap.add_argument("--out", default="assets/sfx")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(args.seed)

    manifest = []
    for name, dur, fn in SOUNDS:
        samples = _normalize(fn(dur=dur, rnd=rnd))
        fname = f"{name}.wav"
        write_wav(out_dir / fname, samples)
        manifest.append({
            "name": name,
            "file": fname,
            "duration_sec": round(len(samples) / SR, 3),
            "mood_tags": MOOD_TAGS.get(name, []),
            "license": "Generated in-app (own work, CC0-dedicated)",
        })
        print(f"  âœ“ {fname:20s} {len(samples)/SR:5.2f}s")

    (out_dir / "manifest.json").write_text(
        json.dumps({"sr": SR, "seed": args.seed, "sounds": manifest},
                   ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"âœ” wrote {len(manifest)} sounds + manifest.json â†’ {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

