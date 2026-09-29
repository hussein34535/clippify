"""F0 — offline verification of the generated SFX pack (assets/sfx)."""
import json
import wave
from pathlib import Path

import pytest

SFX_DIR = Path(__file__).resolve().parents[1] / "assets" / "sfx"

EXPECTED = {
    "whoosh_up": 0.6,
    "whoosh_down": 0.6,
    "riser": 1.4,
    "impact": 0.35,
    "pop": 0.05,
    "click": 0.012,
    "ding": 1.0,
    "tick": 0.03,
    "sub_drop": 0.7,
    "sparkle": 0.5,
    "transition_up": 0.5,
    "transition_down": 0.5,
}


def test_all_files_exist_with_sane_size():
    for name, dur in EXPECTED.items():
        p = SFX_DIR / f"{name}.wav"
        assert p.exists(), f"missing {p}"
        # ≥60% of raw mono-16bit-44.1k PCM size
        assert p.stat().st_size >= int(dur * 44_100 * 2 * 0.6), (
            f"{name} suspiciously small ({p.stat().st_size}B)"
        )


@pytest.mark.parametrize("name,dur", sorted(EXPECTED.items()))
def test_wav_format_and_duration(name, dur):
    with wave.open(str(SFX_DIR / f"{name}.wav"), "rb") as w:
        assert w.getnchannels() == 1
        assert w.getframerate() == 44100
        assert w.getsampwidth() == 2
        actual = w.getnframes() / w.getframerate()
    assert abs(actual - dur) <= max(0.05, dur * 0.15), (
        f"{name}: expected ~{dur}s got {actual:.3f}s"
    )


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_no_clipping(name):
    import struct
    with wave.open(str(SFX_DIR / f"{name}.wav"), "rb") as w:
        frames = w.readframes(w.getnframes())
    ints = struct.unpack(f"<{len(frames)//2}h", frames)
    assert max(abs(i) for i in ints) <= 32_000


def test_manifest_matches_files():
    m = json.loads((SFX_DIR / "manifest.json").read_text(encoding="utf-8"))
    names = {s["file"] for s in m["sounds"]}
    assert names == {f"{n}.wav" for n in EXPECTED}
    for s in m["sounds"]:
        assert s["license"].startswith("Generated in-app")
