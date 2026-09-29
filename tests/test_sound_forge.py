"""Tests for sound_forge.py — advanced procedural synthesis.

Validates WAV format (44.1 kHz mono 16-bit), duration tolerance (±10%),
headroom/no-clipping (-3 dBFS peak), signal presence, seed determinism
(byte-identical hashes) and pack generation.
"""
import hashlib
import json
import math
import struct
import wave

import pytest

from sound_forge import SR, PEAK_DB, SoundForge

SF = SoundForge()


def _file_hash(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _wav_info(path):
    with wave.open(str(path), "rb") as w:
        info = {
            "channels": w.getnchannels(),
            "sampwidth": w.getsampwidth(),
            "framerate": w.getframerate(),
            "frames": w.getnframes(),
        }
        raw = w.readframes(w.getnframes())
    ints = struct.unpack(f"<{len(raw) // 2}h", raw)
    info["peak"] = max((abs(v) for v in ints), default=0)
    info["rms"] = math.sqrt(sum(v * v for v in ints) / max(1, len(ints)))
    return info


# Small durations keep the pure-python DSP well under a few seconds total.
GENERATOR_CASES = {
    "whoosh_up":      ("generate_whoosh", {"direction": "up", "dur": 0.30}, "t1"),
    "whoosh_down":    ("generate_whoosh", {"direction": "down", "dur": 0.30}, "t2"),
    "whoosh_through": ("generate_whoosh", {"direction": "through", "dur": 0.30}, "t3"),
    "riser":          ("generate_riser", {"dur": 0.50}, "t4"),
    "impact":         ("generate_impact", {"dur": 0.30}, "t5"),
    "brainzap":       ("generate_brainzap", {"dur": 0.15}, "t6"),
    "kick":           ("generate_drum_hit", {"type": "kick"}, "t7"),
    "snare":          ("generate_drum_hit", {"type": "snare"}, "t8"),
    "hihat":          ("generate_drum_hit", {"type": "hihat"}, "t9"),
    "pad":            ("generate_ambient_pad", {"dur": 0.60}, "t10"),
    "vinyl_crackle":  ("generate_vinyl_crackle", {"dur": 0.40}, "t11"),
}


def _render(name, sf=None):
    method, kwargs, seed = GENERATOR_CASES[name]
    return getattr(sf or SF, method)(seed=seed, **kwargs)


@pytest.mark.parametrize("name", sorted(GENERATOR_CASES))
def test_wav_format_duration_and_no_clipping(tmp_path, name):
    dur_expected = {
        "whoosh_up": 0.30, "whoosh_down": 0.30, "whoosh_through": 0.30,
        "riser": 0.50, "impact": 0.30, "brainzap": 0.15,
        "kick": SoundForge.DRUM_DURATIONS["kick"],
        "snare": SoundForge.DRUM_DURATIONS["snare"],
        "hihat": SoundForge.DRUM_DURATIONS["hihat"],
        "pad": 0.60, "vinyl_crackle": 0.40,
    }[name]

    samples = _render(name)
    path = SF.save_wav(samples, tmp_path / f"{name}.wav")
    info = _wav_info(path)

    assert info["channels"] == 1
    assert info["sampwidth"] == 2
    assert info["framerate"] == SR

    actual_dur = info["frames"] / SR
    assert abs(actual_dur - dur_expected) <= dur_expected * 0.10, (
        f"{name}: expected ~{dur_expected}s, got {actual_dur:.3f}s")

    # -3 dBFS target → headroom, never clipped; and not silence either.
    assert info["peak"] <= int(0.75 * 32767)
    assert info["peak"] >= 1000
    assert info["rms"] > 50.0


@pytest.mark.parametrize("name", ["whoosh_up", "impact", "snare",
                                  "vinyl_crackle"])
def test_determinism_same_seed_same_hash(tmp_path, name):
    path_a = SF.save_wav(_render(name), tmp_path / "a.wav")

    # Regenerate with the same seed via a fresh instance.
    sf2 = SoundForge()
    path_b = SF.save_wav(_render(name, sf=sf2), tmp_path / "b.wav")

    assert _file_hash(path_a) == _file_hash(path_b)


def test_different_seeds_diverge(tmp_path):
    a = SF.save_wav(SF.generate_whoosh("up", dur=0.25, seed="alpha"),
                    tmp_path / "a.wav")
    b = SF.save_wav(SF.generate_whoosh("up", dur=0.25, seed="beta"),
                    tmp_path / "b.wav")
    assert _file_hash(a) != _file_hash(b)


def test_pack_generation(tmp_path):
    sounds = ["whoosh_up", "impact", "kick"]
    out = tmp_path / "pack"
    written = SF.generate_pack(out, sounds=sounds, seed=7)

    assert set(written) == set(sounds)
    for name, p in written.items():
        assert p.exists()
        info = _wav_info(p)
        assert info["framerate"] == SR and info["sampwidth"] == 2
        assert info["peak"] <= int(0.75 * 32767)

    manifest = json.loads((out / "manifest.json").read_text(encoding="utf-8"))
    assert {s["name"] for s in manifest["sounds"]} == set(sounds)
    assert manifest["sr"] == SR and manifest["seed"] == 7


def test_pack_is_byte_deterministic(tmp_path):
    d1, d2 = tmp_path / "p1", tmp_path / "p2"
    w1 = SF.generate_pack(d1, sounds=["riser", "hihat"], seed=99)
    w2 = SF.generate_pack(d2, sounds=["riser", "hihat"], seed=99)
    for name in w1:
        assert _file_hash(w1[name]) == _file_hash(w2[name])
    m1 = (d1 / "manifest.json").read_bytes()
    m2 = (d2 / "manifest.json").read_bytes()
    assert m1 == m2


def test_pack_unknown_sound_raises(tmp_path):
    with pytest.raises(ValueError, match="unknown sound"):
        SF.generate_pack(tmp_path, sounds=["whoosh_up", "does_not_exist"])


def test_invalid_arguments_raise():
    with pytest.raises(ValueError):
        SF.generate_whoosh("sideways")
    with pytest.raises(ValueError):
        SF.generate_whoosh("up", freq_range=(500, 200))
    with pytest.raises(ValueError):
        SF.generate_drum_hit("tom")
    with pytest.raises(ValueError):
        SF.generate_riser(start_freq=3000, end_freq=100)
    with pytest.raises(ValueError):
        SF.generate_ambient_pad(chord=[])


def test_default_pack_registry_complete():
    expected = {"whoosh_up", "whoosh_down", "whoosh_through", "riser",
                "impact", "brainzap", "kick", "snare", "hihat", "pad",
                "vinyl_crackle"}
    assert set(SoundForge.GENERATOR_REGISTRY) == expected


def test_peak_target_is_minus_three_db():
    assert PEAK_DB == pytest.approx(-3.0)
    # Peak sits at -3 dBFS unless the transient max lands inside the
    # anti-click edge fades, in which case it can only be quieter.
    samples = SF.generate_riser(dur=0.4, seed="pk")
    peak = max(abs(s) for s in samples)
    peak_db = 20.0 * math.log10(peak)
    assert -6.0 <= peak_db <= PEAK_DB + 1e-6
