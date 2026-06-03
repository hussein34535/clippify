"""
clipper.py — Main entry point for ClipAI
ClipAI — Local Video Clipper (no AI, no cloud)
Compatible with moviepy 2.x

Usage
-----
python clipper.py --video path/to/video.mp4 [options]

Options
-------
--video     Path to the input video file           (required)
--clips     Number of clips to generate            (default: 5)
--duration  Duration of each clip in seconds       (default: 60)
--output    Output folder for the clips            (default: ./output)
"""

import argparse
import os
import sys

# Make sure sibling modules are importable when run directly
sys.path.insert(0, os.path.dirname(__file__))

import audio as audio_mod
import detector as detector_mod
import editor as editor_mod


# ── Helpers ───────────────────────────────────────────────────────────────────

def _fmt_time(sec: float) -> str:
    """Format seconds as HH:MM:SS."""
    sec = int(sec)
    h   = sec // 3600
    m   = (sec % 3600) // 60
    s   = sec % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


def _validate_args(args) -> None:
    if not os.path.isfile(args.video):
        sys.exit(f"✗ Video file not found: {args.video}")
    if args.clips < 1:
        sys.exit("✗ --clips must be ≥ 1")
    if args.duration < 5:
        sys.exit("✗ --duration must be ≥ 5 seconds")


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        prog="clipper",
        description="ClipAI — automatically clip the best moments from a long video.",
    )
    parser.add_argument("--video",    required=True,  help="Path to input video file")
    parser.add_argument("--clips",    type=int,   default=5,    help="Number of clips (default: 5)")
    parser.add_argument("--duration", type=float, default=60.0, help="Clip duration in seconds (default: 60)")
    parser.add_argument("--output",   default="./output",       help="Output folder (default: ./output)")

    args = parser.parse_args()
    _validate_args(args)

    os.makedirs(args.output, exist_ok=True)

    print()
    print("=" * 50)
    print("  ClipAI — Local Video Clipper")
    print("=" * 50)
    print(f"  Video    : {args.video}")
    print(f"  Clips    : {args.clips}")
    print(f"  Duration : {args.duration}s each")
    print(f"  Output   : {args.output}")
    print("=" * 50)
    print()

    # ── Step 1 ────────────────────────────────────────────────────────────────
    print("[1/5] Extracting audio...")
    samples, sample_rate = audio_mod.extract(args.video)

    if not samples:
        print("  [WARN] No audio found in video.")
        print("  -> Will create evenly-spaced clips instead.\n")

    # ── Step 2 ────────────────────────────────────────────────────────────────
    print("[2/5] Analyzing energy...")
    timeline = audio_mod.energy_timeline(samples, sample_rate)

    if timeline:
        avg_e = sum(e["energy"] for e in timeline) / len(timeline)
        print(f"  -> {len(timeline)} windows analyzed, avg energy: {avg_e:.3f}")
    else:
        print("  -> No energy data (silent or no audio).")

    # ── Step 3 ────────────────────────────────────────────────────────────────
    print("[3/5] Finding best moments...")

    # Get video duration for clamping
    video_duration = None
    try:
        from moviepy import VideoFileClip as _VFC
        _tmp = _VFC(args.video)
        video_duration = _tmp.duration
        _tmp.close()
    except Exception:
        pass

    # Edge case: video shorter than one clip
    if video_duration and video_duration <= args.duration:
        print(f"  [WARN] Video ({video_duration:.1f}s) is shorter than "
              f"requested clip duration ({args.duration}s).")
        print("  -> Will export the full video as one clip.\n")
        clips = [{"start_sec": 0.0, "end_sec": video_duration, "score": 1.0}]
    else:
        clips = detector_mod.find_clips(
            timeline,
            n_clips=args.clips,
            duration_sec=args.duration,
            video_duration=video_duration,
        )

    if not clips:
        print("  [ERROR] Could not detect any clip moments. Exiting.")
        sys.exit(1)

    for i, c in enumerate(clips, 1):
        print(f"  -> Clip {i}: {_fmt_time(c['start_sec'])} -> "
              f"{_fmt_time(c['end_sec'])}  score: {c['score']:.2f}")

    # ── Step 4 ────────────────────────────────────────────────────────────────
    print("\n[4/5] Exporting clips...")

    exported = []
    for i, c in enumerate(clips, 1):
        out_path = os.path.join(args.output, f"clip_{i}.mp4")
        print(f"  Exporting clip {i}/{len(clips)}...")
        try:
            editor_mod.export(
                video_path=args.video,
                start_sec=c["start_sec"],
                end_sec=c["end_sec"],
                output_path=out_path,
                clip_index=i,
            )
            print(f"  [OK] {out_path}")
            exported.append(out_path)
        except Exception as exc:
            print(f"  [FAIL] Failed to export clip {i}: {exc}")

    # ── Step 5 ────────────────────────────────────────────────────────────────
    print(f"\n[5/5] Done. {len(exported)} clip(s) saved to {args.output}")
    print()


if __name__ == "__main__":
    main()
