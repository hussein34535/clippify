"""Hardware truth + performance-tier brain.

probe(force=False) returns a cached (TTL 300s) snapshot dict:

    {
      "cpu": {"name": str, "cores": int, "threads": int},
      "ram_gb": float,
      "gpus": [{"name": str, "vram_gb": float?}, ...],
      "accel": {"nvenc": bool, "qsv": bool, "vaapi": bool, "cuda": bool},
      "nvidia_vram_gb": float,
      "ollama": {"running": bool, "models": [str, ...]},
      "disk_free_gb": float,
      "ffmpeg_path": str | None,
      "ffprobe_path": str | None,
    }

Every subprocess/network call is wrapped in a timeout and swallowed into safe
defaults — probe() never raises on weird machines.

Win32_VideoController.AdapterRAM is uint32-capped (~4 GB): values at the cap
are treated as "unknown" and nvidia-smi is preferred instead.
"""

from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
import threading
import time
from typing import Any, Dict, List, Optional
from urllib.request import Request, urlopen

try:  # package-relative when imported as system_probe.probe
    from .pathing import resolve_ffmpeg, resolve_ffprobe
except ImportError:  # pragma: no cover - direct script execution fallback
    from pathing import resolve_ffmpeg, resolve_ffprobe

CACHE_TTL_S = 300.0
SUBPROC_TIMEOUT = 10
OLLAMA_TIMEOUT_S = 1
_UINT32_MAX = 4_294_967_295  # AdapterRAM cap sentinel

_LOCK = threading.Lock()
_CACHE: Optional[Dict[str, Any]] = None
_CACHE_AT: float = 0.0


# --------------------------------------------------------------------------
# low-level helpers
# --------------------------------------------------------------------------
def _run_powershell(script: str, timeout: int = SUBPROC_TIMEOUT) -> str:
    """Run a PowerShell snippet and return utf-8 stdout ('' on any failure)."""
    try:
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-Command", script],
            capture_output=True,
            encoding="utf-8",
            errors="ignore",
            timeout=timeout,
        )
        return proc.stdout or ""
    except Exception:
        return ""


def _run_checked(cmd: List[str], timeout: int = SUBPROC_TIMEOUT):
    """Run cmd; return (returncode, stdout). Never raises."""
    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            encoding="utf-8",
            errors="ignore",
            timeout=timeout,
        )
        return proc.returncode, proc.stdout or ""
    except Exception:
        return -1, ""


def _cim_rows(stdout: str) -> List[Dict[str, Any]]:
    """Parse ConvertTo-Json output: single object OR list of objects."""
    text = (stdout or "").strip()
    if not text:
        return []
    try:
        data = json.loads(text)
    except Exception:
        return []
    if isinstance(data, dict):
        data = [data]
    if not isinstance(data, list):
        return []
    return [row for row in data if isinstance(row, dict)]


def _parse_encoders(stdout: str) -> Dict[str, bool]:
    """Flag hardware encoders present in `ffmpeg -hide_banner -encoders`."""
    text = stdout or ""
    return {
        "nvenc": "h264_nvenc" in text,
        "qsv": "h264_qsv" in text,
        "vaapi": "h264_vaapi" in text,
    }


# --------------------------------------------------------------------------
# collectors
# --------------------------------------------------------------------------
def _cpu_info() -> Dict[str, Any]:
    rows = _cim_rows(
        _run_powershell(
            "Get-CimInstance Win32_Processor | "
            "Select-Object Name,NumberOfCores,NumberOfLogicalProcessors | "
            "ConvertTo-Json -Compress"
        )
    )
    name = ""
    cores = 0
    threads = 0
    for row in rows:
        cores += int(row.get("NumberOfCores") or 0)
        threads += int(row.get("NumberOfLogicalProcessors") or 0)
        if not name and row.get("Name"):
            name = str(row["Name"]).strip()
    if not name:
        name = "unknown"
    if not cores:
        cores = os.cpu_count() or 0
    if not threads:
        threads = os.cpu_count() or 0
    return {"name": name, "cores": cores, "threads": threads}


def _ram_gb_via_ctypes() -> float:
    try:
        import ctypes

        class MEMORYSTATUSEX(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong),
                ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        stat = MEMORYSTATUSEX()
        stat.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
        if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):
            return round(stat.ullTotalPhys / 1024**3, 2)
    except Exception:
        pass
    return 0.0


def _ram_gb() -> float:
    rows = _cim_rows(
        _run_powershell(
            "Get-CimInstance Win32_ComputerSystem | "
            "Select-Object TotalPhysicalMemory | ConvertTo-Json -Compress"
        )
    )
    for row in rows:
        total = row.get("TotalPhysicalMemory")
        if total:
            try:
                return round(float(total) / 1024**3, 2)
            except Exception:
                break
    return _ram_gb_via_ctypes()


def _resolve_nvidia_smi() -> Optional[str]:
    found = shutil.which("nvidia-smi")
    if found:
        return found
    cuda_path = os.environ.get("CUDA_PATH", "")
    for candidate in (
        os.path.join(cuda_path, "nvidia-smi.exe"),
        os.path.join(cuda_path, "bin", "nvidia-smi.exe"),
        r"C:\Windows\System32\nvidia-smi.exe",
    ):
        if candidate and os.path.isfile(candidate):
            return candidate
    return None


def _gpu_info() -> tuple:
    """Return (gpus list, nvidia_vram_gb from nvidia-smi-or-WMI fallback)."""
    gpus: List[Dict[str, Any]] = []

    # WMI names (+ vram only when NOT pinned at the uint32 cap)
    rows = _cim_rows(
        _run_powershell(
            "Get-CimInstance Win32_VideoController | "
            "Select-Object Name,AdapterRAM | ConvertTo-Json -Compress"
        )
    )
    wmi_nvidia_vram = 0.0
    for row in rows:
        gpu_name = str(row.get("Name") or "").strip()
        if not gpu_name:
            continue
        entry: Dict[str, Any] = {"name": gpu_name}
        adapter_ram = row.get("AdapterRAM") or 0
        try:
            adapter_ram = int(adapter_ram)
        except Exception:
            adapter_ram = 0
        if 0 < adapter_ram < _UINT32_MAX:
            entry["vram_gb"] = round(adapter_ram / 1024**3, 2)
            if "nvidia" in gpu_name.lower():
                wmi_nvidia_vram = entry["vram_gb"]
        gpus.append(entry)

    # Prefer nvidia-smi for authoritative NVIDIA VRAM (MiB -> GB)
    smi = _resolve_nvidia_smi()
    smi_nvidia_vram = 0.0
    if smi:
        rc, out = _run_checked(
            [smi, "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"]
        )
        if rc == 0:
            for line in out.splitlines():
                parts = [p.strip() for p in line.split(",")]
                if len(parts) < 2:
                    continue
                try:
                    mib = float(parts[1])
                except ValueError:
                    continue
                vram_gb = round(mib / 1024.0, 2)
                smi_nvidia_vram += vram_gb
                target = None
                lowered = parts[0].lower()
                for entry in gpus:
                    if lowered and lowered.split()[0] in entry["name"].lower():
                        target = entry
                        break
                if target is None:
                    target = {"name": parts[0]}
                    gpus.append(target)
                target["vram_gb"] = vram_gb
            if smi_nvidia_vram:
                return gpus, round(smi_nvidia_vram, 2)

    return gpus, wmi_nvidia_vram


def _accel(ffmpeg_path: Optional[str], nvidia_smi_ok: bool) -> Dict[str, bool]:
    flags = {"nvenc": False, "qsv": False, "vaapi": False, "cuda": nvidia_smi_ok}
    if ffmpeg_path:
        _, out = _run_checked([ffmpeg_path, "-hide_banner", "-encoders"])
        flags.update(_parse_encoders(out))
    return flags


def _ollama() -> Dict[str, Any]:
    base = os.environ.get("OLLAMA_URL", "http://localhost:11434").rstrip("/")
    try:
        with urlopen(Request(base + "/api/tags"), timeout=OLLAMA_TIMEOUT_S) as resp:
            payload = json.loads(resp.read().decode("utf-8", errors="ignore"))
        models = [
            str(m.get("name"))
            for m in (payload.get("models") or [])
            if isinstance(m, dict) and m.get("name")
        ]
        return {"running": True, "models": models}
    except Exception:
        return {"running": False, "models": []}


def _disk_free_gb() -> float:
    try:
        usage = shutil.disk_usage(os.getcwd())
        return round(usage.free / 1024**3, 2)
    except Exception:
        return 0.0


def _collect() -> Dict[str, Any]:
    cpu = _cpu_info()
    ram_gb = _ram_gb()
    gpus, nvidia_vram_gb = _gpu_info()

    smi = _resolve_nvidia_smi()
    nvidia_smi_ok = False
    if smi:
        rc, _ = _run_checked([smi])
        nvidia_smi_ok = rc == 0

    ffmpeg_path = resolve_ffmpeg()
    ffprobe_path = resolve_ffprobe()

    accel = _accel(ffmpeg_path, nvidia_smi_ok)

    # NVENC without smi but with a WMI-reported NVIDIA card: seed VRAM so the
    # tier brain isn't blind on stripped-down driver installs.
    if accel.get("nvenc") and not nvidia_vram_gb:
        for entry in gpus:
            if "nvidia" in entry["name"].lower() and entry.get("vram_gb"):
                nvidia_vram_gb = entry["vram_gb"]
                break

    return {
        "cpu": cpu,
        "ram_gb": ram_gb,
        "gpus": gpus,
        "accel": accel,
        "nvidia_vram_gb": nvidia_vram_gb or 0.0,
        "ollama": _ollama(),
        "disk_free_gb": _disk_free_gb(),
        "ffmpeg_path": ffmpeg_path,
        "ffprobe_path": ffprobe_path,
    }


def probe(force: bool = False) -> Dict[str, Any]:
    """Cached hardware snapshot (TTL 300s). Never raises."""
    global _CACHE, _CACHE_AT
    with _LOCK:
        now = time.time()
        if not force and _CACHE is not None and (now - _CACHE_AT) < CACHE_TTL_S:
            return copy.deepcopy(_CACHE)
        try:
            snapshot = _collect()
        except Exception as exc:  # absolute last resort
            snapshot = {
                "cpu": {"name": "unknown", "cores": os.cpu_count() or 0, "threads": os.cpu_count() or 0},
                "ram_gb": _ram_gb_via_ctypes(),
                "gpus": [],
                "accel": {"nvenc": False, "qsv": False, "vaapi": False, "cuda": False},
                "nvidia_vram_gb": 0.0,
                "ollama": {"running": False, "models": []},
                "disk_free_gb": 0.0,
                "ffmpeg_path": None,
                "ffprobe_path": None,
                "_error": repr(exc),
            }
        _CACHE = snapshot
        _CACHE_AT = now
        return copy.deepcopy(snapshot)


# --------------------------------------------------------------------------
# tier brain
# --------------------------------------------------------------------------
_TIER_LABELS: Dict[str, Dict[str, str]] = {
    "S": {"label_ar": "🔥 وضع الوحش", "label_en": "Beast Mode"},
    "A+": {"label_ar": "⚡ وضع السريع", "label_en": "Fast Mode"},
    "A": {"label_ar": "💻 المتوازن", "label_en": "Balanced Mode"},
    "B": {"label_ar": "🪶 الخفيف", "label_en": "Featherweight"},
    "C": {"label_ar": "☁️ السحابي الصرف", "label_en": "Pure Cloud"},
}


def _fmt(value: float) -> str:
    return f"{value:g}"


def decide_tier(p: Dict[str, Any]) -> Dict[str, Any]:
    """Pure rules engine over a probe snapshot.

    EXACT rules:
        S   : accel.nvenc AND nvidia_vram_gb >= 6
        A+  : ram>=8 AND threads>=8 AND ((nvenc AND vram>=4) OR qsv)
        A   : ram>=8 AND threads>=8
        B   : ram >= 4
        C   : everything else
    """
    accel = p.get("accel") or {}
    nvenc = bool(accel.get("nvenc"))
    qsv = bool(accel.get("qsv"))
    cuda = bool(accel.get("cuda"))
    vram = float(p.get("nvidia_vram_gb") or 0.0)
    ram = float(p.get("ram_gb") or 0.0)
    threads = int(p.get("cpu", {}).get("threads") or 0)

    strong_cpu = ram >= 8 and threads >= 8

    if nvenc and vram >= 6:
        tier = "S"
        why_ar = f"NVENC شغال مع {_fmt(vram)}GB فيديو رام — تشفير عتادي بلا حدود، خليه يولّع."
    elif strong_cpu and ((nvenc and vram >= 4) or qsv):
        tier = "A+"
        if nvenc:
            why_ar = f"NVENC مع {_fmt(vram)}GB VRAM و{_fmt(ram)}GB رام — تشفير سريع ومتوازن."
        else:
            why_ar = f"QSV من إنتل يسرّع التشفير عتادياً مع {_fmt(ram)}GB رام."
    elif strong_cpu:
        tier = "A"
        why_ar = f"{_fmt(ram)}GB رام و{threads} ثريد — قلب المونتاج بدون تسريع كروت."
    elif ram >= 4:
        tier = "B"
        why_ar = f"{_fmt(ram)}GB رام تكفي للمشاريع الخفيفة فقط."
    else:
        tier = "C"
        why_ar = f"{_fmt(ram)}GB رام بس — سيب المعالجة للسحابة."

    accel_summary = "+".join(k for k, v in sorted(accel.items()) if v) or "none"

    labels = _TIER_LABELS[tier]
    return {
        "tier": tier,
        "label_ar": labels["label_ar"],
        "label_en": labels["label_en"],
        "why_ar": why_ar,
        "accel_summary": accel_summary,
        "cuda_available": cuda,
    }
