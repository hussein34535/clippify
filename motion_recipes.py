"""Pre-built FFmpeg motion recipes (zoom, shake, glitch, whip pan, Ken Burns).

Every recipe is a parameterized filter template rendered per-clip by
:func:`build_filter` and chainable via :func:`compose_filters`.
"""

from __future__ import annotations

from dataclasses import dataclass, field

__all__ = ["MotionRecipe", "MOTION_RECIPES", "build_filter", "compose_filters"]


@dataclass(frozen=True)
class MotionRecipe:
    name: str
    description_ar: str
    ffmpeg_filter_template: str
    required_params: list = field(default_factory=list)


MOTION_RECIPES: dict[str, MotionRecipe] = {
    "zoom_in": MotionRecipe(
        name="zoom_in",
        description_ar="زوم بطيء من 1.0 إلى 1.15 على مدار المقطع",
        ffmpeg_filter_template=(
            "zoompan=z='min(zoom+{zoom_step},{zoom_end})':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            "d=1:s={out_w}x{out_h}:fps={fps}"
        ),
        required_params=["zoom_end"],
    ),
    "punch_in": MotionRecipe(
        name="punch_in",
        description_ar="زوم سريع إلى 1.3 عند 80% من مدة المقطع",
        ffmpeg_filter_template=(
            "zoompan=z='if(lt(in,{punch_start_frame}),1.0,"
            "min(1.0+({zoom_end}-1.0)*(in-{punch_start_frame})/{punch_ramp_frames},{zoom_end}))':"
            "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':"
            "d=1:s={out_w}x{out_h}:fps={fps}"
        ),
        required_params=["zoom_end"],
    ),
    "shake": MotionRecipe(
        name="shake",
        description_ar="اهتزاز كاميرا خفيف بإزاحات عشوائية للقص",
        ffmpeg_filter_template=(
            "crop=w='iw-{shake_px}':h='ih-{shake_px}':"
            "x='random(1)*{shake_px}':y='random(2)*{shake_px}'"
        ),
        required_params=["shake_px"],
    ),
    "glitch": MotionRecipe(
        name="glitch",
        description_ar="وميض انفصال قنوات RGB لمدة إطارين عند منتصف المقطع",
        ffmpeg_filter_template=(
            "rgbashift=rh={glitch_shift}:bh=-{glitch_shift}:"
            "enable='between(t,{glitch_t0},{glitch_t1})'"
        ),
        required_params=["glitch_shift"],
    ),
    "whip_pan": MotionRecipe(
        name="whip_pan",
        description_ar="انتقال تمويه أفقي سريع حول منتصف المقطع",
        ffmpeg_filter_template=(
            "avgblur=sizeX={whip_blur}:sizeY=1:"
            "enable='between(t,{whip_t0},{whip_t1})'"
        ),
        required_params=["whip_blur"],
    ),
    "ken_burns": MotionRecipe(
        name="ken_burns",
        description_ar="تحريك قطري بطيء مع زوم تدريجي (كين بيرنز)",
        ffmpeg_filter_template=(
            "zoompan=z='{kb_zoom_start}+({kb_zoom_end}-{kb_zoom_start})*in/{frames}':"
            "x='(iw-iw/zoom)*in/{frames}':y='(ih-ih/zoom)*in/{frames}':"
            "d=1:s={out_w}x{out_h}:fps={fps}"
        ),
        required_params=["kb_zoom_end"],
    ),
}

_DEFAULT_PARAMS: dict[str, dict] = {
    "zoom_in": {"zoom_end": 1.15},
    "punch_in": {"zoom_end": 1.3},
    "shake": {"shake_px": 16},
    "glitch": {"glitch_shift": 6},
    "whip_pan": {"whip_blur": 40},
    "ken_burns": {"kb_zoom_start": 1.0, "kb_zoom_end": 1.25},
}

_COMMON_DEFAULTS = {
    "fps": 30,
    "out_w": 720,
    "out_h": 1280,
}


def _frame_count(duration_sec: float, fps: int) -> int:
    return max(1, int(round(duration_sec * fps)))


def build_filter(recipe_name: str, duration_sec: float, params: dict | None = None) -> str:
    """Render an FFmpeg filter string for one recipe on a specific clip."""
    recipe = MOTION_RECIPES.get(recipe_name)
    if recipe is None:
        raise ValueError(
            f"unknown recipe {recipe_name!r}; known: {sorted(MOTION_RECIPES)}"
        )
    if not isinstance(duration_sec, (int, float)) or duration_sec <= 0:
        raise ValueError(f"duration_sec must be a positive number, got {duration_sec!r}")

    merged = dict(_COMMON_DEFAULTS)
    merged.update(_DEFAULT_PARAMS.get(recipe_name, {}))
    merged.update(params or {})

    for required in recipe.required_params:
        if required not in merged:
            raise ValueError(f"missing required param {required!r} for recipe {recipe_name!r}")

    fps = int(merged["fps"])
    frames = _frame_count(float(duration_sec), fps)
    punch_at = float(merged.get("punch_at", 0.80))
    punch_start_frame = max(1, int(round(frames * punch_at)))
    punch_ramp_frames = max(1, int(round(frames * float(merged.get("punch_ramp", 0.06)))))
    mid_t = round(float(duration_sec) * 0.5, 4)
    two_frames = round(2.0 / max(fps, 1), 4)
    whip_span = float(merged.get("whip_span", 0.10))

    ctx = {
        **merged,
        "duration": round(float(duration_sec), 4),
        "frames": frames,
        "zoom_step": round(
            (float(merged["zoom_end"]) - 1.0) / frames, 6
        ) if "zoom_end" in merged else 0.0,
        "punch_start_frame": punch_start_frame,
        "punch_ramp_frames": punch_ramp_frames,
        "glitch_t0": mid_t,
        "glitch_t1": round(mid_t + two_frames, 4),
        "whip_t0": round(mid_t - whip_span / 2.0, 4),
        "whip_t1": round(mid_t + whip_span / 2.0, 4),
    }

    return recipe.ffmpeg_filter_template.format(**ctx)


def compose_filters(recipe_names: list, duration_sec: float, params: dict | None = None) -> str:
    """Chain multiple recipes into a single comma-joined -vf filter string."""
    parts = [build_filter(name, duration_sec, params) for name in recipe_names]
    return ",".join(part for part in parts if part)
