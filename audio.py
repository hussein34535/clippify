"""
audio.py — Audio extraction + energy analysis
Clippify — Local Video Clipper (no AI, no cloud)
Compatible with moviepy 2.x
"""

import os
import wave
import math
import struct
import tempfile
import subprocess

def extract(video_path: str):
    """
    Extract audio from video, save as temp mono 16kHz WAV,
    read raw PCM samples, delete the temp file, and return
    (samples_list, sample_rate).

    Returns ([], 0) if the video has no audio track.
    """
    # Resolve local or bundled ffmpeg
    local_bin = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin")
    ffmpeg_exe = os.path.join(local_bin, "ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    if not os.path.exists(ffmpeg_exe):
        try:
            import imageio_ffmpeg
            ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
        except ImportError:
            ffmpeg_exe = "ffmpeg"

    # Temporary wav output file
    temp_wav = os.path.join(tempfile.gettempdir(), f"temp_{os.path.basename(video_path)}.wav")

    try:
        # Run FFmpeg to extract WAV
        cmd = [
            ffmpeg_exe,
            "-y",
            "-i", video_path,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            temp_wav
        ]
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if res.returncode != 0 or not os.path.exists(temp_wav) or os.path.getsize(temp_wav) == 0:
            print("  [WARN] Video has no audio track or FFmpeg extraction failed.")
            return ([], 0)

        # Read raw samples using built-in wave module (no extra deps)
        samples = []
        with wave.open(temp_wav, "rb") as wf:
            sample_rate = wf.getframerate()
            n_frames    = wf.getnframes()
            raw         = wf.readframes(n_frames)
            # PCM 16-bit little-endian signed shorts
            samples = list(struct.unpack(f"<{n_frames}h", raw))

        return (samples, sample_rate)

    finally:
        if os.path.exists(temp_wav):
            try:
                os.remove(temp_wav)
            except OSError:
                pass


def energy_timeline(samples: list, sample_rate: int, window_sec: float = 0.5):
    """
    Slide a window of `window_sec` over the sample array.
    Compute RMS energy per window, normalise to 0.0–1.0.

    Returns a list of {"time_sec": float, "energy": float}.
    """
    if not samples or sample_rate == 0:
        return []

    window_size = max(1, int(sample_rate * window_sec))
    timeline    = []

    for i in range(0, len(samples), window_size):
        chunk = samples[i: i + window_size]
        if not chunk:
            continue

        # RMS
        mean_sq = sum(s * s for s in chunk) / len(chunk)
        rms     = math.sqrt(mean_sq)

        time_sec = i / sample_rate
        timeline.append({"time_sec": time_sec, "energy": rms})

    if not timeline:
        return []

    # Normalise to 0.0–1.0
    max_energy = max(e["energy"] for e in timeline)
    if max_energy == 0:
        return timeline   # all silence

    for entry in timeline:
        entry["energy"] = entry["energy"] / max_energy

    return timeline
