"""Tests for palette_engine.py and motion_recipes.py."""

import os
import re

import pytest

from motion_recipes import MOTION_RECIPES, build_filter, compose_filters
from palette_engine import MOODS, extract_dominant_colors, generate_palette

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HEX_RE = re.compile(r"^#[0-9A-F]{6}$")
PALETTE_KEYS = {"primary", "secondary", "accent", "text_fg", "text_bg", "overlay_tint"}

_DOMINANT = [
    {"hex": "#3366CC", "percentage": 62.5},
    {"hex": "#EEDDAA", "percentage": 20.0},
    {"hex": "#111111", "percentage": 8.0},
]


# ---------------------------------------------------------------------------
# palette_engine.generate_palette
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("mood", MOODS)
def test_generate_palette_all_moods(mood):
    palette = generate_palette(_DOMINANT, mood)
    assert set(palette.keys()) == PALETTE_KEYS
    for key, value in palette.items():
        assert HEX_RE.match(value), f"{mood}/{key} -> {value!r}"


def test_generate_palette_moods_differ():
    energetic = generate_palette(_DOMINANT, "energetic")
    calm = generate_palette(_DOMINANT, "calm")
    dark = generate_palette(_DOMINANT, "dark")
    assert len({energetic["primary"], calm["primary"], dark["primary"]}) == 3


def test_generate_palette_unknown_mood_raises():
    with pytest.raises(ValueError):
        generate_palette(_DOMINANT, "neon")


def test_generate_palette_empty_colors_raises():
    for mood in MOODS:
        with pytest.raises(ValueError):
            generate_palette([], mood)


def test_generate_palette_accent_is_complementary_shift():
    palette = generate_palette([{"hex": "#FF0000", "percentage": 100.0}], "energetic")
    accent_rgb = tuple(int(palette["accent"][i:i + 2], 16) for i in (1, 3, 5))
    r, g, b = accent_rgb
    assert r < g and abs(g - b) < 40


# ---------------------------------------------------------------------------
# motion_recipes.build_filter / compose_filters
# ---------------------------------------------------------------------------


def _all_recipes():
    return sorted(MOTION_RECIPES.keys())


@pytest.mark.parametrize(
    "name,kw",
    [
        ("zoom_in", "zoompan"),
        ("zoom_in", "1.15"),
        ("punch_in", "zoompan"),
        ("punch_in", "1.3"),
        ("shake", "crop"),
        ("shake", "random(1)"),
        ("glitch", "rgbashift"),
        ("glitch", "between(t,"),
        ("whip_pan", "avgblur"),
        ("ken_burns", "zoompan"),
        ("ken_burns", "(iw-iw/zoom)"),
    ],
)
def test_build_filter_keywords(name, kw):
    rendered = build_filter(name, 12.0, {})
    assert kw in rendered, f"{name}: {rendered}"


@pytest.mark.parametrize("name", _all_recipes())
def test_build_filter_valid_for_every_recipe(name):
    rendered = build_filter(name, 8.5, {})
    assert isinstance(rendered, str) and rendered.strip()
    assert not rendered.startswith(",")
    assert "{" not in rendered and "}" not in rendered


def test_build_filter_param_override():
    rendered = build_filter("zoom_in", 10.0, {"zoom_end": 1.4})
    assert "min(zoom+0.00004,1.4)" in rendered or "1.4" in rendered


def test_build_filter_duration_scales_frames():
    short = build_filter("ken_burns", 2.0)
    long_ = build_filter("ken_burns", 60.0)
    short_frames = int(short.split("*in/")[1].split("'")[0])
    long_frames = int(long_.split("*in/")[1].split("'")[0])
    assert long_frames > short_frames * 20


def test_build_filter_unknown_recipe_raises():
    with pytest.raises(ValueError):
        build_filter("nope", 10.0)


@pytest.mark.parametrize("bad", [0, -3.0, None])
def test_build_filter_invalid_duration_raises(bad):
    with pytest.raises(ValueError):
        build_filter("zoom_in", bad)


def test_compose_filters_chains_in_order():
    chain = compose_filters(["zoom_in", "shake", "glitch"], 30.0)
    assert "," in chain
    assert chain.index("zoompan") < chain.index("crop") < chain.index("rgbashift")


def test_compose_filters_empty():
    assert compose_filters([], 10.0) == ""


# ---------------------------------------------------------------------------
# palette_engine.extract_dominant_colors
# ---------------------------------------------------------------------------


def _make_quadrant_image(path):
    from PIL import Image

    img = Image.new("RGB", (320, 320), "#FF0000")
    blue = Image.new("RGB", (160, 160), "#0000FF")
    green = Image.new("RGB", (80, 80), "#00CC00")
    white = Image.new("RGB", (80, 80), "#FFFFFF")
    img.paste(blue, (160, 0))
    img.paste(green, (160, 160))
    img.paste(white, (240, 240))
    img.save(path)
    return str(path)


def test_extract_dominant_colors_from_image(tmp_path):
    pytest.importorskip("PIL")
    image_path = _make_quadrant_image(str(tmp_path / "quad.png"))
    result = extract_dominant_colors(image_path)
    assert result, "expected non-empty dominant colors"
    total_pct = sum(entry["percentage"] for entry in result)
    assert abs(total_pct - 100.0) < 1.0
    percentages = [entry["percentage"] for entry in result]
    assert percentages == sorted(percentages, reverse=True)
    assert all(HEX_RE.match(entry["hex"]) for entry in result)
    top_hexes = {entry["hex"] for entry in result[:2]}
    assert any(h in top_hexes for h in ("#FF0000", "#FE0000", "#FF0100"))


def test_extract_dominant_colors_rejects_bad_input(tmp_path):
    with pytest.raises(FileNotFoundError):
        extract_dominant_colors(str(tmp_path / "missing.mp4"))
    with pytest.raises(ValueError):
        extract_dominant_colors(str(tmp_path / "x.mp4"), n_frames=0)


def _make_test_video(path):
    import subprocess

    from system_probe.pathing import resolve_ffmpeg

    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        pytest.skip("ffmpeg unavailable on this machine")
    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", "testsrc=size=320x240:rate=10:duration=2",
        "-frames:v", "20", "-pix_fmt", "yuv420p",
        os.path.splitext(path)[0] + ".mp4",
    ]
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=60,
            stdin=subprocess.DEVNULL,
        )
    except Exception as exc:
        pytest.skip(f"could not run ffmpeg: {exc}")
    out = os.path.splitext(path)[0] + ".mp4"
    if proc.returncode != 0 or not os.path.isfile(out):
        pytest.skip(f"could not synthesize test video: {(proc.stderr or '')[:200]}")
    return out


def test_extract_dominant_colors_from_video(tmp_path):
    pytest.importorskip("PIL")
    fixture = _make_test_video(str(tmp_path / "gen.mp4"))
    result = extract_dominant_colors(fixture, n_frames=3)
    assert result
    assert all(HEX_RE.match(entry["hex"]) for entry in result)
    percentages = [entry["percentage"] for entry in result]
    assert percentages == sorted(percentages, reverse=True)
    assert sum(percentages) == pytest.approx(100.0, abs=1.0)
