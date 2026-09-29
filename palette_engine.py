"""Palette engine — dominant color extraction + mood-driven palette generation.

Frame dumping goes through the FFmpeg binary resolved by
system_probe.pathing.resolve_ffmpeg(); all color math (HSL manipulation,
median-cut quantization) is pure Python — no external color library.
Frames are extracted as 24-bit BMP so they can be decoded even when
Pillow is absent (pure-python BMP reader fallback).
"""

from __future__ import annotations

import os
import subprocess
import tempfile

from system_probe.pathing import resolve_ffmpeg, resolve_ffprobe

__all__ = ["extract_dominant_colors", "generate_palette", "MOODS"]

MOODS = ("energetic", "calm", "dark", "warm")

_TOP_K = 6
_MERGE_DISTANCE = 42.0
_DUMP_WIDTH = 480
_SAMPLE_MAX_DIM = 160

_IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp"}
_VIDEO_EXTS = {
    ".mp4", ".mov", ".mkv", ".webm", ".avi",
    ".m4v", ".mpg", ".mpeg", ".wmv", ".flv", ".ts",
}

_CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


# ---------------------------------------------------------------------------
# Color math (pure python)
# ---------------------------------------------------------------------------


def _clamp(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def _hex_to_rgb(hex_color: str) -> tuple:
    hex_color = hex_color.strip().lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join(ch * 2 for ch in hex_color)
    if len(hex_color) != 8 and len(hex_color) != 6:
        raise ValueError(f"invalid hex color: {hex_color!r}")
    hex_color = hex_color[-6:]
    return (
        int(hex_color[0:2], 16),
        int(hex_color[2:4], 16),
        int(hex_color[4:6], 16),
    )


def _rgb_to_hex(r: int, g: int, b: int) -> str:
    return "#{:02X}{:02X}{:02X}".format(
        int(round(_clamp(r, 0, 255))),
        int(round(_clamp(g, 0, 255))),
        int(round(_clamp(b, 0, 255))),
    )


def _rgb_to_hsl(r: int, g: int, b: int) -> tuple:
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    c_max, c_min = max(rf, gf, bf), min(rf, gf, bf)
    delta = c_max - c_min
    lightness = (c_max + c_min) / 2.0
    if delta <= 0.0:
        return 0.0, 0.0, lightness
    if c_max == rf:
        hue = ((gf - bf) / delta) % 6.0
    elif c_max == gf:
        hue = (bf - rf) / delta + 2.0
    else:
        hue = (rf - gf) / delta + 4.0
    hue *= 60.0
    denom = 1.0 - abs(2.0 * lightness - 1.0)
    saturation = delta / denom if denom > 0 else 0.0
    return hue % 360.0, saturation, lightness


def _hsl_to_rgb(h: float, s: float, l: float) -> tuple:
    h = h % 360.0
    s = _clamp(s, 0.0, 1.0)
    l = _clamp(l, 0.0, 1.0)
    c = (1.0 - abs(2.0 * l - 1.0)) * s
    x = c * (1.0 - abs((h / 60.0) % 2.0 - 1.0))
    m = l - c / 2.0
    if h < 60:
        rp, gp, bp = c, x, 0.0
    elif h < 120:
        rp, gp, bp = x, c, 0.0
    elif h < 180:
        rp, gp, bp = 0.0, c, x
    elif h < 240:
        rp, gp, bp = 0.0, x, c
    elif h < 300:
        rp, gp, bp = x, 0.0, c
    else:
        rp, gp, bp = c, 0.0, x
    return (
        int(round((rp + m) * 255)),
        int(round((gp + m) * 255)),
        int(round((bp + m) * 255)),
    )


def _relative_luminance(rgb: tuple) -> float:
    r, g, b = rgb
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0


# ---------------------------------------------------------------------------
# Quantization — pure-python median cut
# ---------------------------------------------------------------------------


def _box_split_axis(samples: list) -> int:
    ranges = []
    for channel in range(3):
        values = [s[channel] for s in samples]
        ranges.append(max(values) - min(values))
    return ranges.index(max(ranges))


def _dominant_from_samples(samples: list, k: int = _TOP_K) -> list:
    """Median-cut quantization. Input/output items: ((r,g,b), count)."""
    if not samples:
        return []
    boxes = [samples]
    while len(boxes) < k:
        best_box, best_score, best_axis = None, 0.0, 0
        for box in boxes:
            if len(box) < 2:
                continue
            axis = _box_split_axis(box)
            values = [s[axis] for s in box]
            spread = max(values) - min(values)
            score = spread * len(box)
            if spread > 0 and score > best_score:
                best_box, best_score, best_axis = box, score, axis
        if best_box is None:
            break
        best_box.sort(key=lambda s: s[best_axis])
        mid = len(best_box) // 2
        boxes.remove(best_box)
        boxes.extend([best_box[:mid], best_box[mid:]])

    results = []
    for box in boxes:
        if not box:
            continue
        n = len(box)
        avg = tuple(sum(s[ch] for s in box) // n for ch in range(3))
        results.append((avg, n))
    return results


def _merge_clusters(weighted: list) -> list:
    """Greedy merge of near-identical cluster representatives."""
    clusters = []
    for color, weight in weighted:
        merged = False
        for cluster in clusters:
            dist = sum((cluster[0][ch] - color[ch]) ** 2 for ch in range(3)) ** 0.5
            if dist <= _MERGE_DISTANCE:
                total = cluster[1] + weight
                mixed = tuple(
                    int(round((cluster[0][ch] * cluster[1] + color[ch] * weight) / total))
                    for ch in range(3)
                )
                clusters[clusters.index(cluster)] = (mixed, total)
                merged = True
                break
        if not merged:
            clusters.append((color, weight))
    return clusters


# ---------------------------------------------------------------------------
# Frame decoding
# ---------------------------------------------------------------------------


def _decode_bmp(path: str) -> list:
    """Minimal 24-bit BMP reader (fallback when Pillow is unavailable)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] != b"BM":
        raise ValueError(f"not a BMP file: {path}")
    pixel_offset = int.from_bytes(data[10:14], "little")
    header_size = int.from_bytes(data[14:18], "little")
    if header_size >= 40:
        width = int.from_bytes(data[18:22], "little", signed=True)
        height = int.from_bytes(data[22:26], "little", signed=True)
        bpp = int.from_bytes(data[28:30], "little")
    elif header_size == 12:
        width = int.from_bytes(data[18:20], "little")
        height = int.from_bytes(data[20:22], "little")
        bpp = int.from_bytes(data[24:26], "little")
    else:
        raise ValueError(f"unsupported BMP header size {header_size}")
    if bpp != 24:
        raise ValueError(f"only 24-bit BMP supported, got {bpp}bpp")
    bottom_up = height > 0
    height, width = abs(height), abs(width)
    row_size = ((width * 3) + 3) // 4 * 4
    rows = []
    for view_row in range(height):
        y = view_row if bottom_up else height - 1 - view_row
        start = pixel_offset + y * row_size
        line = data[start:start + width * 3]
        row = []
        for x in range(0, width * 3, 3):
            row.append((line[x + 2], line[x + 1], line[x]))
        rows.append(row)
    return rows


def _sample_pixels(rows: list) -> list:
    """Downsample decoded pixel rows into a flat sample list."""
    height = len(rows)
    width = len(rows[0]) if height else 0
    step_x = max(1, width // _SAMPLE_MAX_DIM)
    step_y = max(1, height // _SAMPLE_MAX_DIM)
    samples = []
    for y in range(0, height, step_y):
        row = rows[y]
        for x in range(0, width, step_x):
            samples.append(row[x])
    return samples


def _load_pixel_rows(path: str) -> list:
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        if not path.lower().endswith(".bmp"):
            raise RuntimeError(
                f"Pillow unavailable — cannot decode {path!r}; install Pillow "
                "or feed a .bmp frame"
            )
        return _decode_bmp(path)
    with Image.open(path) as img:
        return list(img.convert("RGB").getdata())
    return []


def _rows_from_flat(flat: list) -> list:
    return [flat]


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def _dump_frames(video_path: str, workdir: str, n_frames: int) -> list:
    ffmpeg = resolve_ffmpeg()
    if not ffmpeg:
        raise RuntimeError(
            "ffmpeg executable not found — set CLIPPIFY_FFMPEG or install imageio_ffmpeg"
        )

    duration = None
    ffprobe = resolve_ffprobe()
    if ffprobe:
        try:
            proc = subprocess.run(
                [ffprobe, "-v", "error", "-show_entries", "format=duration",
                 "-of", "default=noprint_wrappers=1:nokey=1", video_path],
                capture_output=True, text=True, timeout=30,
                stdin=subprocess.DEVNULL,
                creationflags=_CREATE_NO_WINDOW,
            )
            if proc.returncode == 0:
                duration = float(proc.stdout.strip().splitlines()[0])
        except Exception:
            duration = None

    pattern = os.path.join(workdir, "frame_%04d.bmp")
    scale = f"scale={_DUMP_WIDTH}:-2"
    if duration and duration > 0.1:
        fps = n_frames / duration
        vf = f"fps={fps:.6f},{scale}"
    else:
        vf = scale

    cmd = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-i", video_path,
        "-vf", vf,
        "-frames:v", str(n_frames),
        pattern,
    ]
    proc = subprocess.run(
        cmd, capture_output=True, text=True, timeout=120,
        stdin=subprocess.DEVNULL,
        creationflags=_CREATE_NO_WINDOW,
    )
    frames = sorted(
        os.path.join(workdir, name)
        for name in os.listdir(workdir)
        if name.lower().endswith(".bmp")
    )
    if not frames:
        stderr_tail = (proc.stderr or "").strip().splitlines()[-3:]
        raise RuntimeError(
            f"ffmpeg produced no frames for {video_path!r}: {' | '.join(stderr_tail)}"
        )
    return frames


def _colors_from_frame_files(frame_paths: list) -> list:
    weighted = []
    for path in frame_paths:
        flat = _load_pixel_rows(path)
        rows = _rows_from_flat(flat)
        samples = _sample_pixels(rows)
        weighted.extend(_dominant_from_samples(samples))
    return _merge_clusters(weighted)


def extract_dominant_colors(video_path: str, n_frames: int = 5) -> list[dict]:
    """Extract dominant colors from a video (or single image) file.

    Returns a list of ``{"hex": "#RRGGBB", "percentage": float}`` dicts,
    sorted by descending coverage; percentages sum to ~100.
    """
    if not isinstance(video_path, str) or not video_path:
        raise ValueError("video_path must be a non-empty string")
    if n_frames < 1:
        raise ValueError("n_frames must be >= 1")
    if not os.path.isfile(video_path):
        raise FileNotFoundError(video_path)

    ext = os.path.splitext(video_path)[1].lower()
    if ext in _IMAGE_EXTS:
        frame_paths = [video_path]
        weighted = _colors_from_frame_files(frame_paths)
    else:
        with tempfile.TemporaryDirectory(prefix="clippify_palette_") as workdir:
            frame_paths = _dump_frames(video_path, workdir, n_frames)
            weighted = _colors_from_frame_files(frame_paths)

    total = sum(weight for _, weight in weighted) or 1
    ranked = sorted(weighted, key=lambda item: item[1], reverse=True)[:_TOP_K]
    kept_total = sum(weight for _, weight in ranked) or 1
    results = [
        {"hex": _rgb_to_hex(*color), "percentage": round(weight / kept_total * 100.0, 2)}
        for color, weight in ranked
    ]
    return results


# ---------------------------------------------------------------------------
# Palette generation
# ---------------------------------------------------------------------------

_OVERLAY_HUE_SHIFT = {"energetic": 15.0, "calm": 210.0, "dark": 0.0, "warm": 40.0}


def _apply_mood(mood: str, hue: float, sat: float, lig: float) -> tuple:
    if mood == "energetic":
        return hue, _clamp(sat * 1.35 + 0.10, 0.55, 1.0), _clamp(lig, 0.42, 0.58)
    if mood == "calm":
        return hue, _clamp(sat * 0.55, 0.10, 0.45), _clamp(lig, 0.46, 0.64)
    if mood == "dark":
        return hue, _clamp(sat * 0.90, 0.15, 0.85), _clamp(lig, 0.16, 0.30)
    if mood == "warm":
        folded_hue = hue % 72.0
        return folded_hue, _clamp(sat * 1.10 + 0.05, 0.35, 1.0), _clamp(lig, 0.40, 0.60)
    raise ValueError(f"unknown mood {mood!r}; expected one of {MOODS}")


def _pick_primary(dominant_colors: list) -> str:
    def _pct(entry: dict) -> float:
        try:
            return float(entry.get("percentage", 0.0))
        except (TypeError, ValueError, AttributeError):
            return 0.0

    candidates = sorted(dominant_colors or [], key=_pct, reverse=True)
    for entry in candidates:
        hex_value = entry.get("hex") or entry.get("color")
        if hex_value:
            return str(hex_value)
    raise ValueError("dominant_colors must contain at least one entry with a 'hex'")


def generate_palette(dominant_colors: list, mood: str) -> dict:
    """Build a full palette from dominant colors and a mood.

    Moods: "energetic", "calm", "dark", "warm".
    Color theory: accent = complementary hue, secondary = analogous hue.
    Returns {primary, secondary, accent, text_fg, text_bg, overlay_tint}
    with "#RRGGBB" values.
    """
    if mood not in MOODS:
        raise ValueError(f"unknown mood {mood!r}; expected one of {MOODS}")

    primary_hex = _pick_primary(dominant_colors)
    hue, sat, lig = _rgb_to_hsl(*_hex_to_rgb(primary_hex))
    hue, sat, lig = _apply_mood(mood, hue, sat, lig)

    secondary_lig = _clamp(lig + 0.06, 0.0, 0.92)
    accent_sat = _clamp(sat * 1.25 + 0.15, 0.55, 1.0)
    accent_lig = _clamp(lig, 0.42, 0.58)
    overlay_lig = 0.35 if mood == "dark" else 0.50

    text_bg_rgb = _hsl_to_rgb(hue, sat * 0.75, 0.07 if mood == "dark" else 0.09)
    text_fg = "#FAFAFA" if _relative_luminance(text_bg_rgb) < 0.35 else "#161616"

    palette = {
        "primary": _rgb_to_hex(*_hsl_to_rgb(hue, sat, lig)),
        "secondary": _rgb_to_hex(*_hsl_to_rgb((hue + 30.0) % 360.0, sat * 0.85, secondary_lig)),
        "accent": _rgb_to_hex(*_hsl_to_rgb((hue + 180.0) % 360.0, accent_sat, accent_lig)),
        "text_fg": text_fg,
        "text_bg": _rgb_to_hex(*text_bg_rgb),
        "overlay_tint": _rgb_to_hex(*_hsl_to_rgb(
            (hue + _OVERLAY_HUE_SHIFT[mood]) % 360.0, 0.55, overlay_lig
        )),
    }
    return palette
