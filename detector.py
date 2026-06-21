"""
detector.py — Clip moment detection logic
Clippify — Local Video Clipper (no AI, no cloud)
"""

import math


def _rolling_average(values: list, window: int) -> list:
    """Simple rolling / moving average over a flat list of floats."""
    if not values or window <= 0:
        return values

    smoothed = []
    half = window // 2
    n = len(values)

    for i in range(n):
        lo = max(0, i - half)
        hi = min(n, i + half + 1)
        chunk = values[lo:hi]
        smoothed.append(sum(chunk) / len(chunk))

    return smoothed


def _overlap_ratio(a_start, a_end, b_start, b_end) -> float:
    """Return the fraction of the shorter clip that overlaps the other."""
    overlap = max(0.0, min(a_end, b_end) - max(a_start, b_start))
    shorter = min(a_end - a_start, b_end - b_start)
    if shorter == 0:
        return 0.0
    return overlap / shorter


def find_clips(timeline: list, n_clips: int, duration_sec: float,
               video_duration: float = None):
    """
    Detect the best clip moments from the energy timeline.

    Steps
    -----
    1. Smooth the energy curve (rolling avg window=10).
    2. Find peaks: energy > mean + 0.5 * std.
    3. Build a clip window around each peak.
    4. Clamp to video boundaries.
    5. Sort by score descending.
    6. Remove overlapping clips (>50% overlap → keep higher score).
    7. Return top n_clips.

    Parameters
    ----------
    timeline      : list of {"time_sec": float, "energy": float}
    n_clips       : how many clips to return
    duration_sec  : target duration of each clip in seconds
    video_duration: total video length in seconds (for clamping).
                    If None, clamping uses last timeline entry only.

    Returns
    -------
    list of {"start_sec": float, "end_sec": float, "score": float}
    sorted by score descending, length <= n_clips.
    """
    if not timeline:
        return []

    # ── 1. Smooth ────────────────────────────────────────────────────────────
    energies = [e["energy"] for e in timeline]
    times    = [e["time_sec"] for e in timeline]
    smoothed = _rolling_average(energies, window=10)

    # ── 2. Peaks ─────────────────────────────────────────────────────────────
    n = len(smoothed)
    if n == 0:
        return []

    mean_e = sum(smoothed) / n
    variance = sum((x - mean_e) ** 2 for x in smoothed) / n
    std_e = math.sqrt(variance)
    threshold = mean_e + 0.5 * std_e

    peaks = [
        {"time_sec": times[i], "score": smoothed[i]}
        for i in range(n)
        if smoothed[i] > threshold
    ]

    if not peaks:
        # Fallback: just use evenly spaced windows
        max_time = times[-1] if times else 0
        step = max(duration_sec, max_time / max(n_clips, 1))
        peaks = [
            {"time_sec": step * k, "score": 0.5}
            for k in range(n_clips)
        ]

    # ── 3 & 4. Build windows + clamp ─────────────────────────────────────────
    max_time = video_duration if video_duration else (times[-1] if times else 0)

    clips = []
    for p in peaks:
        start = p["time_sec"] - duration_sec / 4.0
        start = max(0.0, start)
        end   = start + duration_sec
        if end > max_time > 0:
            end   = max_time
            start = max(0.0, end - duration_sec)
        clips.append({
            "start_sec": start,
            "end_sec":   end,
            "score":     p["score"],
        })

    # ── 5. Sort by score ─────────────────────────────────────────────────────
    clips.sort(key=lambda c: c["score"], reverse=True)

    # ── 6. Remove overlapping clips (>50%) ───────────────────────────────────
    kept = []
    for candidate in clips:
        overlap_found = False
        for existing in kept:
            ratio = _overlap_ratio(
                candidate["start_sec"], candidate["end_sec"],
                existing["start_sec"],  existing["end_sec"],
            )
            if ratio > 0.5:
                overlap_found = True
                break
        if not overlap_found:
            kept.append(candidate)
        if len(kept) >= n_clips:
            break

    # Sort kept clips chronologically for nicer output
    kept.sort(key=lambda c: c["start_sec"])

    return kept
