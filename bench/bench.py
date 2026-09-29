#!/usr/bin/env python3
"""SpeedProbe baseline benchmark for Clippify.

Measures, with cold hard numbers:
  a) synth source      : ffmpeg lavfi testsrc2 1280x720@30 30s + sine 440
  b) transcribe        : faster-whisper tiny (+ base in --full), load vs run timed separately
  c) render matrix     : 9:16 720x1280 30s -> x264 veryfast CRF23, nvenc (if accel), qsv (if listed)
  d) import-cold       : `import api` module cost in a fresh subprocess
  e) assemble          : docs/BASELINE.json

ffmpeg resolution order:
  system_probe.pathing.resolve_ffmpeg() -> imageio_ffmpeg.get_ffmpeg_exe() -> shutil.which("ffmpeg")

system_probe (Squad-G0) is imported GUARDED: if absent, full inline fallbacks keep this working.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# --------------------------------------------------------------------------
# GUARDED system_probe import (Squad-G0 may still be writing it)
# --------------------------------------------------------------------------
sys.path.insert(0, str(REPO_ROOT))

system_probe = None  # module handle if present


def _try_import_system_probe():
    global system_probe
    try:
        import system_probe as _sp  # noqa: F401

        system_probe = _sp
    except Exception as exc:  # absent or broken -> fallbacks only
        print(f"[bench] system_probe unavailable ({type(exc).__name__}); using inline fallbacks")


def probe_machine() -> dict:
    """machine info via system_probe.probe() guarded else minimal psutil-free fields."""
    try:
        if system_probe is not None and hasattr(system_probe, "probe"):
            p = system_probe.probe()
            if isinstance(p, dict):
                return p
    except Exception as exc:
        print(f"[bench] probe() failed ({type(exc).__name__}); falling back to minimal fields")
    machine = {
        "platform": platform.platform(),
        "python": sys.version.split()[0],
        "cpu_count": os.cpu_count(),
        "processor": platform.processor() or "unknown",
    }
    # GPU name via nvidia-smi if present (no psutil dependency)
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            machine["gpu"] = out.stdout.strip().splitlines()[0].strip()
    except Exception:
        pass
    return machine


def detect_accel() -> dict:
    """accel detection: probe first, else nvidia-smi presence."""
    info = {"nvenc": False, "qsv_listed": False}
    try:
        if system_probe is not None:
            pathing = getattr(system_probe, "pathing", None)
            if pathing is not None and hasattr(pathing, "detect_accel"):
                got = pathing.detect_accel()
                if isinstance(got, dict):
                    info.update(got)
                    return info
    except Exception:
        pass
    try:
        out = subprocess.run(["nvidia-smi"], capture_output=True, text=True, timeout=10)
        info["nvenc"] = out.returncode == 0
    except Exception:
        pass
    return info


# --------------------------------------------------------------------------
# ffmpeg resolution
# --------------------------------------------------------------------------

def resolve_ffmpeg() -> str:
    # 1) system_probe.pathing.resolve_ffmpeg()
    try:
        if system_probe is not None:
            pathing = getattr(system_probe, "pathing", None)
            if pathing is not None and hasattr(pathing, "resolve_ffmpeg"):
                p = pathing.resolve_ffmpeg()
                if p and Path(str(p)).exists():
                    return str(p)
    except Exception:
        pass
    # 2) imageio_ffmpeg
    try:
        import imageio_ffmpeg

        p = imageio_ffmpeg.get_ffmpeg_exe()
        if p:
            return str(p)
    except Exception:
        pass
    # 3) shutil.which
    w = shutil.which("ffmpeg")
    if w:
        return w
    raise SystemExit("[bench] FATAL: no ffmpeg found (probe/imageio/PATH all failed)")


def run_cmd(cmd: list[str], timeout_s: float) -> tuple[bool, float, str, str]:
    """Run cmd, return (ok, wall_seconds, stdout_tail, stderr_tail)."""
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            cwd=str(REPO_ROOT),
        )
        dt = time.perf_counter() - t0
        ok = proc.returncode == 0
        out_t = proc.stdout or ""  # FULL stdout (-encoders list is long)
        err_t = (proc.stderr or "")[-800:]
        return ok, dt, out_t, err_t
    except subprocess.TimeoutExpired:
        return False, time.perf_counter() - t0, "", f"TIMEOUT after {timeout_s}s"
    except Exception as exc:
        return False, time.perf_counter() - t0, "", f"{type(exc).__name__}: {exc}"


def verify_out(path: Path, min_bytes: int = 100 * 1024) -> bool:
    try:
        return path.exists() and path.stat().st_size > min_bytes
    except OSError:
        return False


# --------------------------------------------------------------------------
# Steps
# --------------------------------------------------------------------------

def synth_source(ffmpeg: str, dst: Path) -> float:
    """testsrc2 1280x720@30 30s + sine 440. Returns seconds taken."""
    cmd = [
        ffmpeg, "-y",
        "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=30",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=30",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k",
        "-pix_fmt", "yuv420p",
        str(dst),
    ]
    ok, dt, _out, tail = run_cmd(cmd, timeout_s=120)
    if not ok or not verify_out(dst):
        raise SystemExit(f"[bench] FATAL: source synth failed:\n{tail}")
    print(f"[bench] synth source OK ({dt:.2f}s, {dst.stat().st_size // 1024} KB)")
    return dt


def extract_wav(ffmpeg: str, src: Path, dst: Path) -> None:
    cmd = [ffmpeg, "-y", "-i", str(src), "-ar", "16000", "-ac", "1", str(dst)]
    ok, _dt, _out, tail = run_cmd(cmd, timeout_s=120)
    if not ok:
        raise SystemExit(f"[bench] FATAL: wav extraction failed:\n{tail}")


def bench_transcribe(wav: Path, models: list[str]) -> dict:
    """Returns {tiny_load, tiny_run, base_load, base_run} — null when skipped."""
    from faster_whisper import WhisperModel

    res: dict[str, float | None] = {
        "tiny_load": None, "tiny_run": None, "base_load": None, "base_run": None,
    }
    for name in models:
        size_note = {
            "tiny": "~75 MB",
            "base": "~145 MB",
        }.get(name, "(size unknown)")
        print(f"[bench] whisper '{name}': first run may download model {size_note} ...")
        t0 = time.perf_counter()
        model = WhisperModel(name, device="cpu", compute_type="int8")  # deterministic CPU int8
        load_s = time.perf_counter() - t0
        t0 = time.perf_counter()
        segments, info = model.transcribe(str(wav), language="en", beam_size=1)
        n_seg = 0
        for _seg in segments:  # consume generator -> actual work happens here
            n_seg += 1
        run_s = time.perf_counter() - t0
        key_load, key_run = f"{name}_load", f"{name}_run"
        res[key_load] = round(load_s, 3)
        res[key_run] = round(run_s, 3)
        print(f"[bench]   load={load_s:.3f}s run={run_s:.3f}s segments={n_seg}")
        del model
    return res


def list_encoders(ffmpeg: str) -> set[str]:
    ok, _dt, out, _err = run_cmd([ffmpeg, "-hide_banner", "-encoders"], timeout_s=30)
    return set() if not ok else set(out.split())


def bench_render(ffmpeg: str, src: Path, outdir: Path, encoders: set[str], accel: dict) -> dict:
    """9:16 720x1280 30s renders. Times via perf_counter around subprocess wait."""
    vf = "scale=720:1280:force_original_aspect_ratio=increase,crop=720:1280,fps=30"
    variants: list[tuple[str, list[str]]] = [
        ("x264_s", ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23"]),
    ]
    if accel.get("nvenc") and "h264_nvenc" in encoders:
        variants.append(("nvenc_s", ["-c:v", "h264_nvenc", "-preset", "p4", "-rc", "vbr", "-cq", "23"]))
    else:
        variants.append(("nvenc_s", None))  # placeholder -> explicit null + note
    if "h264_qsv" in encoders:
        variants.append(("qsv_s", ["-c:v", "h264_qsv", "-global_quality", "23"]))
    else:
        variants.append(("qsv_s", None))

    results: dict[str, float | None] = {}
    notes: list[str] = []
    for key, venc in variants:
        if venc is None:
            results[key] = None
            if key.startswith("nvenc"):
                why = (
                    "h264_nvenc not listed by this ffmpeg build"
                    if accel.get("nvenc")
                    else "no GPU via nvidia-smi"
                )
            else:
                why = "h264_qsv not listed by this ffmpeg build"
            notes.append(f"render:{key[:-2]} SKIPPED — {why}")
            continue
        out = outdir / f"out_{key[:-2]}.mp4"
        cmd = [
            ffmpeg, "-y", "-i", str(src),
            "-vf", vf,
            *venc,
            "-c:a", "aac", "-b:a", "128k",
            str(out),
        ]
        ok, dt, _out, tail = run_cmd(cmd, timeout_s=300)
        if ok and verify_out(out):
            results[key] = round(dt, 3)
            print(f"[bench] render {key[:-2]}: {dt:.2f}s ({out.stat().st_size // 1024} KB)")
        else:
            results[key] = None
            notes.append(f"render:{key[:-2]} FAILED/TINY OUTPUT — {tail.strip().splitlines()[-1] if tail.strip() else 'no stderr'}")
            print(f"[bench] render {key[:-2]}: FAILED ({dt:.2f}s)")
    return results, notes


def bench_api_import() -> float | None:
    """Cold `import api` cost in a fresh interpreter."""
    code = "import time;t0=time.perf_counter();import api;print(time.perf_counter()-t0)"
    try:
        proc = subprocess.run(
            [sys.executable, "-c", code],
            capture_output=True,
            text=True,
            timeout=180,
            cwd=str(REPO_ROOT),
        )
        val = float(proc.stdout.strip().splitlines()[-1])
        return round(val, 3)
    except Exception as exc:
        print(f"[bench] api import measure failed: {exc}")
        return None


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="Clippify SpeedProbe baseline")
    ap.add_argument("--quick", action="store_true", default=True, help="tiny whisper only (default)")
    ap.add_argument("--full", action="store_true", help="tiny + base whisper")
    args = ap.parse_args()
    mode = "full" if args.full else "quick"

    print(f"[bench] mode={mode}")
    _try_import_system_probe()
    ffmpeg = resolve_ffmpeg()
    print(f"[bench] ffmpeg = {ffmpeg}")

    notes: list[str] = []
    tmp = Path(tempfile.mkdtemp(prefix="clippify_bench_"))
    src = tmp / "bench_src.mp4"
    wav = tmp / "bench_src.wav"

    synth_source(ffmpeg, src)
    extract_wav(ffmpeg, src, wav)

    models = ["tiny", "base"] if mode == "full" else ["tiny"]
    if mode == "quick":
        notes.append("quick mode: base whisper skipped (tiny only)")

    transcribe = {k: None for k in ("tiny_load", "tiny_run", "base_load", "base_run")}
    try:
        got = bench_transcribe(wav, models)
        transcribe.update(got)
    except Exception as exc:
        notes.append(f"transcribe failed: {type(exc).__name__}: {exc}")

    accel = detect_accel()
    encoders = list_encoders(ffmpeg)
    render, rnotes = bench_render(ffmpeg, src, tmp, encoders, accel)
    notes.extend(rnotes)

    api_import_s = bench_api_import()

    tiny_dl = (transcribe.get("tiny_load") or 0) > 60
    if tiny_dl:
        notes.append("tiny load >60s — includes first-run download; rerun shows warm-load number")

    baseline = {
        "timestamp_iso": datetime.now(timezone.utc).isoformat(),
        "mode": mode,
        "machine": probe_machine(),
        "results": {
            "transcribe": transcribe,
            "render": render,
            "api_import_s": api_import_s,
        },
        "notes": notes,
    }

    docs = REPO_ROOT / "docs"
    docs.mkdir(exist_ok=True)
    out_json = docs / "BASELINE.json"
    out_json.write_text(json.dumps(baseline, indent=2), encoding="utf-8")
    print(f"\n[bench] wrote {out_json}")

    shutil.rmtree(tmp, ignore_errors=True)

    print("\n=== BASELINE SUMMARY ===")
    t = transcribe
    print(f"whisper tiny  load={t['tiny_load']}s run={t['tiny_run']}s")
    print(f"whisper base  load={t['base_load']}s run={t['base_run']}s")
    print(f"render x264   = {render['x264_s']}s")
    print(f"render nvenc  = {render['nvenc_s']}s")
    print(f"render qsv    = {render['qsv_s']}s")
    print(f"import api    = {api_import_s}s")

    have_core = t.get("tiny_run") is not None and render.get("x264_s") is not None
    return 0 if have_core else 1


if __name__ == "__main__":
    sys.exit(main())
