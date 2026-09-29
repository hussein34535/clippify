#!/usr/bin/env python3
"""Clippify Studio — مشغّل موحّد بضغطة واحدة (One-click launcher).

يكتشف تلقائياً بايثون المشروع الصحيح (الذي يحتوي fastapi/uvicorn)،
يشغّل الباك إند (api.py على FastAPI)، ينتظر جاهزيته عبر /api/health،
ثم يفتح واجهة Flutter Desktop (flutter run أو النسخة المبنية الجاهزة).

يعمل بأي بايثون متاح (حتى embedded) — المنطق كله stdlib فقط.

الاستخدام:
    python run_clippify.py                # تشغيل كامل (باك إند + واجهة)
    python run_clippify.py --dry-run      # فحص البيئة وطباعة الخطة فقط
    python run_clippify.py --backend-only # باك إند فقط (أو CLIPPIFY_NO_FLUTTER=1)

متغيرات البيئة:
    CLIPPIFY_PYTHON   مسار بايثون المشروع (يُجرّب أولاً)
    CLIPPIFY_HOST     عنوان الباك إند (افتراضي 127.0.0.1)
    CLIPPIFY_PORT     منفذ الباك إند (افتراضي 8000)
    CLIPPIFY_NO_FLUTTER   1 = باك إند فقط بدون واجهة (اختبار/CI)
    CLIPPIFY_FRONTEND     flutter | exe | none — تجاوز قرار الواجهة
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FLUTTER_DIR = ROOT / "flutter_client"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000
HEALTH_WAIT_TIMEOUT = 90.0

_PROBE_SNIPPET = "import fastapi, uvicorn"
_NO_WINDOW = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW

# Handles of Job Objects keeping spawned children bound to this launcher
# (Windows only, best-effort): if the launcher dies hard, children die too.
_JOB_HANDLES: list = []


# ---------------------------------------------------------------------------
# Environment helpers
# ---------------------------------------------------------------------------

def get_host() -> str:
    """Host من CLIPPIFY_HOST أو 127.0.0.1 — متوافق مع api.py."""
    return os.environ.get("CLIPPIFY_HOST", "").strip() or DEFAULT_HOST


def get_port() -> int:
    """Port من CLIPPIFY_PORT أو 8000 (قيمة غير صالحة → تحذير + 8000)."""
    raw = os.environ.get("CLIPPIFY_PORT", "").strip()
    if not raw:
        return DEFAULT_PORT
    try:
        return int(raw)
    except ValueError:
        print(f"[تحذير] CLIPPIFY_PORT={raw!r} غير صالح — سيتم استخدام {DEFAULT_PORT}.")
        return DEFAULT_PORT


# ---------------------------------------------------------------------------
# Python discovery
# ---------------------------------------------------------------------------

def build_python_candidates() -> list[list[str]]:
    """مرشحو بايثون بالترتيب: CLIPPIFY_PYTHON → sys.executable →
    %LOCALAPPDATA%\\Python\\bin\\python.exe → بايثونات %LOCALAPPDATA% → py -3 → python."""
    candidates: list[list[str]] = []

    env_py = os.environ.get("CLIPPIFY_PYTHON", "").strip()
    if env_py:
        candidates.append([env_py])

    if sys.executable:
        candidates.append([sys.executable])

    local = os.environ.get("LOCALAPPDATA", "").strip()
    if local:
        base = Path(local)
        well_known = base / "Python" / "bin" / "python.exe"
        if well_known.is_file():
            candidates.append([str(well_known)])
        for pattern in ("Python/*/bin/python.exe", "Python/*/python.exe",
                        "Programs/Python/*/python.exe"):
            for hit in sorted(base.glob(pattern)):
                if hit.is_file():
                    candidates.append([str(hit)])

    candidates.append(["py", "-3"])
    candidates.append(["python"])

    # dedupe مع الحفاظ على الترتيب (Windows غير حساس لحالة الأحرف)
    seen: set[tuple[str, ...]] = set()
    unique: list[list[str]] = []
    for cmd in candidates:
        key = tuple(part.lower() if os.name == "nt" else part for part in cmd)
        if key in seen:
            continue
        seen.add(key)
        unique.append(cmd)
    return unique


def probe_candidate(cmd: list[str], timeout: float = 20.0) -> bool:
    """True لو يستطيع المرشح استيراد fastapi و uvicorn."""
    try:
        result = subprocess.run(
            [*cmd, "-c", _PROBE_SNIPPET],
            capture_output=True,
            timeout=timeout,
            creationflags=_NO_WINDOW,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def choose_python(probe=None, announce=None) -> list[str] | None:
    """أول مرشح ناجح، أو None لو الجميع فشل."""
    probe = probe or probe_candidate
    say = announce or (lambda msg: print(msg, flush=True))
    for cmd in build_python_candidates():
        ok = probe(cmd)
        say(f"      فحص {_fmt_cmd(cmd)}: {'[OK]' if ok else '[X]'}")
        if ok:
            return cmd
    return None


# ---------------------------------------------------------------------------
# Port / health helpers
# ---------------------------------------------------------------------------

def port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    """True لو يمكن فتح اتصال TCP على host:port."""
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def fetch_health(host: str, port: int, timeout: float = 2.0) -> dict | None:
    """JSON من /api/health أو None."""
    url = f"http://{host}:{port}/api/health"
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            if getattr(resp, "status", 200) != 200:
                return None
            return json.loads(resp.read().decode("utf-8", "replace"))
    except (OSError, ValueError):
        return None


def is_clippify_health(payload: dict | None) -> bool:
    """True لو الاستجابة تبدو كخادم Clippify."""
    if not isinstance(payload, dict):
        return False
    message = str(payload.get("message", "")).lower()
    return payload.get("status") == "ok" and "clippify" in message


def classify_port(host: str, port: int, opener=None, fetcher=None) -> str:
    """تصنيف حالة المنفذ: "free" | "ours" | "busy"."""
    opener = opener or port_open
    fetcher = fetcher or fetch_health
    payload = fetcher(host, port)
    if payload is not None:
        return "ours" if is_clippify_health(payload) else "busy"
    if opener(host, port):
        return "busy"
    return "free"


def find_free_port(host: str, start: int = 8001, tries: int = 30, opener=None) -> int | None:
    """أول منفذ حر بدءاً من start، أو None."""
    opener = opener or port_open
    for port in range(start, start + tries):
        if not opener(host, port):
            return port
    return None


def wait_backend_ready(
    host: str,
    port: int,
    timeout: float = HEALTH_WAIT_TIMEOUT,
    fetcher=None,
    stop: threading.Event | None = None,
    interval: float = 1.0,
    announce=None,
    abort=None,
) -> bool:
    """انتظار /api/health حتى الجاهزية مع رسائل تقدم كل 5 ثوانٍ.

    abort: دالة اختيارية تُستدعى كل دورة — لو أعادت True نتوقف فوراً
    (مثلاً عملية الباك إند خرجت أثناء الانتظار).
    """
    fetcher = fetcher or fetch_health
    say = announce or (lambda msg: print(msg, flush=True))
    deadline = time.monotonic() + timeout
    next_progress = 0.0
    while True:
        payload = fetcher(host, port)
        if payload is not None:
            return True
        if stop is not None and stop.is_set():
            return False
        if abort is not None and abort():
            return False
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        elapsed = timeout - remaining
        if elapsed >= next_progress:
            say(f"      ... انتظار جاهزية الباك إند ({int(elapsed)}s/{int(timeout)}s)")
            next_progress += 5
        time.sleep(min(interval, remaining))


# ---------------------------------------------------------------------------
# Process management
# ---------------------------------------------------------------------------

def terminate_tree(proc: subprocess.Popen) -> None:
    """إنهاء العملية وشجرتها (taskkill /T على Windows) — فقط ما أطلقه هذا المشغّل.

    لو فشل taskkill لأي سبب (غير موجود في PATH، رفض وصول)، نرجع مباشرة
    إلى proc.terminate()/kill() لضمان قتل العملية الأم على الأقل.
    """
    if proc.poll() is not None:
        return
    tree_killed = False
    if os.name == "nt":
        try:
            result = subprocess.run(
                ["taskkill", "/PID", str(proc.pid), "/T", "/F"],
                capture_output=True,
                timeout=10,
                creationflags=_NO_WINDOW,
                check=False,
            )
            tree_killed = result.returncode == 0
        except (OSError, subprocess.SubprocessError):
            tree_killed = False
    else:
        proc.terminate()
        tree_killed = True
    if not tree_killed:
        try:
            proc.terminate()
        except OSError:
            pass
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        try:
            proc.kill()
            proc.wait(timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            pass


def _attach_job(proc: subprocess.Popen) -> None:
    """ربط العملية بـ Job Object (Windows) — ضمان موت الأطفال عند موت المشغّل قسراً."""
    if os.name != "nt":
        return
    try:
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)

        class _IO_COUNTERS(ctypes.Structure):
            _fields_ = [(name, ctypes.c_uint64) for name in (
                "ReadOperationCount", "WriteOperationCount", "OtherOperationCount",
                "ReadTransferCount", "WriteTransferCount", "OtherTransferCount")]

        class _BASIC_LIMITS(ctypes.Structure):
            _fields_ = [
                ("PerProcessUserTimeLimit", ctypes.c_int64),
                ("PerJobUserTimeLimit", ctypes.c_int64),
                ("LimitFlags", wintypes.DWORD),
                ("MinimumWorkingSetSize", ctypes.c_size_t),
                ("MaximumWorkingSetSize", ctypes.c_size_t),
                ("ActiveProcessLimit", wintypes.DWORD),
                ("Affinity", ctypes.c_size_t),
                ("PriorityClass", wintypes.DWORD),
                ("SchedulingClass", wintypes.DWORD),
            ]

        class _EXTENDED_LIMITS(ctypes.Structure):
            _fields_ = [
                ("BasicLimitInformation", _BASIC_LIMITS),
                ("IoInfo", _IO_COUNTERS),
                ("ProcessMemoryLimit", ctypes.c_size_t),
                ("JobMemoryLimit", ctypes.c_size_t),
                ("PeakProcessMemoryUsed", ctypes.c_size_t),
                ("PeakJobMemoryUsed", ctypes.c_size_t),
            ]

        job = kernel32.CreateJobObjectW(None, None)
        info = _EXTENDED_LIMITS()
        info.BasicLimitInformation.LimitFlags = 0x2000  # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        if kernel32.SetInformationJobObject(job, 9, ctypes.byref(info), ctypes.sizeof(info)) and \
                kernel32.AssignProcessToJobObject(job, int(proc._handle)):
            _JOB_HANDLES.append(job)  # إبقاء الـ handle حياً حتى خروج المشغّل
    except (OSError, TypeError, ValueError, AttributeError):
        pass  # best-effort عمداً — التنظيف الطبيعي عبر terminate_tree يبقى مساراً أساسياً


def start_backend(py_cmd: list[str], host: str, port: int) -> subprocess.Popen:
    """تشغيل api.py بالبايثون المختار مع تمرير CLIPPIFY_HOST/CLIPPIFY_PORT."""
    env = os.environ.copy()
    env["CLIPPIFY_HOST"] = host
    env["CLIPPIFY_PORT"] = str(port)
    proc = subprocess.Popen([*py_cmd, "api.py"], cwd=str(ROOT), env=env)
    _attach_job(proc)
    return proc


def start_flutter(flutter_cmd: str) -> subprocess.Popen:
    """تشغيل flutter run -d windows داخل flutter_client/."""
    proc = subprocess.Popen(
        [flutter_cmd, "run", "-d", "windows"],
        cwd=str(FLUTTER_DIR),
    )
    _attach_job(proc)
    return proc


def start_exe(exe_path: str) -> subprocess.Popen:
    """تشغيل النسخة المبنية مباشرة."""
    proc = subprocess.Popen([exe_path], cwd=str(Path(exe_path).parent))
    _attach_job(proc)
    return proc


# ---------------------------------------------------------------------------
# Frontend decision
# ---------------------------------------------------------------------------

def decide_frontend(
    *,
    flutter_dir_exists: bool,
    flutter_cmd: str | None,
    release_exe: str | None,
    debug_exe: str | None,
    prefer: str | None = None,
) -> tuple[str, str]:
    """قرار الواجهة: ("flutter", cmd) | ("exe", path) | ("none", سبب)."""
    if prefer == "none":
        return ("none", "CLIPPIFY_FRONTEND=none")
    flutter_ok = flutter_dir_exists and bool(flutter_cmd)
    if prefer == "flutter" and flutter_ok:
        return ("flutter", flutter_cmd)
    if prefer == "exe":
        if release_exe:
            return ("exe", release_exe)
        if debug_exe:
            return ("exe", debug_exe)
    # الترتيب الافتراضي: flutter run إن توفر، وإلا النسخة المبنية الجاهزة
    if flutter_ok:
        return ("flutter", flutter_cmd)
    if release_exe:
        return ("exe", release_exe)
    if debug_exe:
        return ("exe", debug_exe)
    return ("none", "لا يوجد Flutter SDK في PATH ولا نسخة مبنية جاهزة (build/windows/x64/runner)")


def plan_frontend() -> tuple[str, str]:
    """decide_frontend بقيم حقيقية من القرص و PATH."""
    release = FLUTTER_DIR / "build" / "windows" / "x64" / "runner" / "Release" / "flutter_client.exe"
    debug = FLUTTER_DIR / "build" / "windows" / "x64" / "runner" / "Debug" / "flutter_client.exe"
    return decide_frontend(
        flutter_dir_exists=FLUTTER_DIR.is_dir(),
        flutter_cmd=shutil.which("flutter"),
        release_exe=str(release) if release.is_file() else None,
        debug_exe=str(debug) if debug.is_file() else None,
        prefer=os.environ.get("CLIPPIFY_FRONTEND", "").strip().lower() or None,
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _fmt_cmd(cmd: list[str]) -> str:
    try:
        return subprocess.list2cmdline(cmd)
    except (TypeError, ValueError):
        return " ".join(cmd)


def _setup_streams() -> None:
    """ضمان عدم انهيار الطباعة العربية على أي كونسول/تحويل مخرجات."""
    for stream in (sys.stdout, sys.stderr):
        try:
            if hasattr(stream, "reconfigure"):
                if stream.isatty():
                    stream.reconfigure(errors="replace")
                else:
                    stream.reconfigure(encoding="utf-8", errors="replace")
        except (OSError, ValueError, AttributeError):
            pass  # الكونسول قد لا يدعم إعادة التهيئة — نتجاهل بأمان


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="run_clippify.py",
        description="مشغّل Clippify الموحّد — باك إند FastAPI + واجهة Flutter Desktop",
    )
    parser.add_argument("--dry-run", action="store_true",
                        help="فحص البيئة وطباعة الخطة دون تشغيل أي عملية")
    parser.add_argument("--backend-only", action="store_true",
                        help="تشغيل الباك إند فقط بدون واجهة (مثل CLIPPIFY_NO_FLUTTER=1)")
    parser.add_argument("--exit-after", type=float, default=None, metavar="SECONDS",
                        help="إيقاف تلقائي بعد N ثانية (للاختبار وCI)")
    parser.add_argument("--no-banner", action="store_true", help="إخفاء البانر")
    return parser.parse_args(argv)


def print_banner() -> None:
    print("=" * 60)
    print("      C L I P P I F Y   S T U D I O")
    print("      مشغّل بضغطة واحدة — One-Click Launcher")
    print("=" * 60)


def _cleanup(frontend: subprocess.Popen | None, backend: subprocess.Popen | None,
             backend_ours: bool, host: str, port: int) -> None:
    """إغلاق العمليات التي أطلقها المشغّل فقط — بالترتيب: الواجهة ثم الباك إند."""
    print("[إيقاف] إنهاء العمليات التي أطلقها المشغّل...")
    if frontend is not None and frontend.poll() is None:
        print(f"  إغلاق الواجهة (PID {frontend.pid})...")
        terminate_tree(frontend)
    if backend_ours and backend is not None and backend.poll() is None:
        print(f"  إيقاف الباك إند (PID {backend.pid})...")
        terminate_tree(backend)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not port_open(host, port, timeout=0.5):
                print(f"  [OK] تم تحرير المنفذ {port}.")
                break
            time.sleep(0.5)
        else:
            print(f"  [تحذير] المنفذ {port} ما زال مشغولاً بعد الإيقاف.")
    print("[OK] تم الإغلاق.")


def main(argv=None) -> int:
    args = parse_args(argv)
    _setup_streams()
    if not args.no_banner:
        print_banner()

    stop = threading.Event()
    if args.exit_after is not None:
        timer = threading.Timer(max(args.exit_after, 0.0), stop.set)
        timer.daemon = True
        timer.start()

    no_flutter_env = os.environ.get("CLIPPIFY_NO_FLUTTER", "").strip().lower() in ("1", "true", "yes", "on")
    backend_only = args.backend_only or no_flutter_env

    host, port = get_host(), get_port()

    # [1/4] اختيار بايثون المشروع
    print("[1/4] البحث عن بايثون مناسب للمشروع (يحتاج fastapi + uvicorn)...")
    py_cmd = choose_python()
    if py_cmd is None:
        print("  [X] لم يتم العثور على بايثون يحتوي على متطلبات المشروع.")
        print("      الحل: ثبت المتطلبات ثم أعد المحاولة:")
        print("          pip install -r requirements.txt")
        print("      أو حدد مسار بايثون المشروع عبر متغير البيئة CLIPPIFY_PYTHON.")
        return 1
    print(f"  [OK] سيتم استخدام: {_fmt_cmd(py_cmd)}")

    # [2/4] فحص المنفذ
    print(f"[2/4] فحص المنفذ {port} على {host}...")
    status = classify_port(host, port)
    backend: subprocess.Popen | None = None
    backend_ours = False
    if status == "ours":
        print("  [OK] يوجد سيرفر Clippify يعمل على هذا المنفذ — سيتم استخدامه مباشرة.")
    elif status == "busy":
        alt = find_free_port(host, port + 1)
        print("  [X] المنفذ مشغول بعملية أخرى ليست Clippify.")
        if alt:
            print(f"      الحل 1: أغلق البرنامج الآخر الذي يستخدم المنفذ {port}.")
            print(f"      الحل 2: استخدم منفذاً بديلاً مثل {alt}:")
            print(f"          cmd:        set CLIPPIFY_PORT={alt}")
            print(f"          powershell: $env:CLIPPIFY_PORT={alt}")
            print("      ملاحظة: لو غيّرت المنفذ، عدّل API_BASE_URL في flutter_client/.env ليطابقه.")
        else:
            print(f"      الحل: أغلق البرنامج الآخر الذي يستخدم المنفذ {port}.")
        return 1
    elif args.dry_run:
        print(f"  [DRY-RUN] سيتم تشغيل الباك إند بالأمر: {_fmt_cmd(py_cmd)} api.py")
    else:
        print(f"  تشغيل الباك إند: {_fmt_cmd(py_cmd)} api.py")
        backend = start_backend(py_cmd, host, port)
        backend_ours = True
        print(f"  PID={backend.pid} — انتظار الجاهزية عبر /api/health (حتى {int(HEALTH_WAIT_TIMEOUT)} ثانية)...")
        ready = wait_backend_ready(
            host, port, timeout=HEALTH_WAIT_TIMEOUT, stop=stop,
            abort=lambda: backend.poll() is not None,
        )
        if not ready:
            if stop.is_set():
                print("  [X] تم إلغاء الانتظار.")
            elif backend.poll() is not None:
                print(f"  [X] عملية الباك إند خرجت مبكراً (كود {backend.returncode}) — راجع رسائل الخطأ أعلاه.")
            else:
                print(f"  [X] الباك إند لم يستجب خلال {int(HEALTH_WAIT_TIMEOUT)} ثانية.")
            print("      عادة السبب نقص متطلبات أو خطأ في api.py — جرّب: python api.py يدوياً.")
            _cleanup(None, backend, backend_ours, host, port)
            return 1
        print(f"  [OK] الباك إند جاهز على http://{host}:{port}")

    if args.dry_run:
        action, detail = ("none", "backend-only (CLIPPIFY_NO_FLUTTER)") if backend_only else plan_frontend()
        print("[3/4] قرار الواجهة (dry-run):")
        print(f"  [DRY-RUN] {action}: {detail}")
        print("[4/4] dry-run انتهى — لم يتم تشغيل أي عملية. [OK]")
        return 0

    # [3/4] تشغيل الواجهة
    frontend: subprocess.Popen | None = None
    if backend_only:
        print("[3/4] وضع الباك إند فقط (CLIPPIFY_NO_FLUTTER) — تخطي تشغيل الواجهة.")
        if backend is None:
            print("  ملاحظة: السيرفر كان يعمل مسبقاً — Ctrl+C سيغلق هذا المشغّل فقط.")
    else:
        print("[3/4] تشغيل واجهة Flutter Desktop...")
        action, detail = plan_frontend()
        if action == "flutter":
            print(f"  الأمر: {_fmt_cmd([detail, 'run', '-d', 'windows'])}")
            frontend = start_flutter(detail)
        elif action == "exe":
            print(f"  تشغيل النسخة المبنية: {detail}")
            frontend = start_exe(detail)
        else:
            print(f"  [X] لا يمكن تشغيل الواجهة: {detail}")
            print("      الخيارات:")
            print("        1) ثبت Flutter SDK وأضفه إلى PATH ثم أعد المحاولة.")
            print("        2) أو ابنِ نسخة مسبقاً: cd flutter_client && flutter build windows --release")
            if backend_ours and backend is not None:
                print("  سيتم إيقاف الباك إند لأن الواجهة غير متاحة.")
                _cleanup(None, backend, backend_ours, host, port)
            elif backend is None:
                print("  ملاحظة: سيرفر Clippify الموجود مسبقاً ستبقى يعمل.")
            return 1
        print("  [OK] الواجهة قيد التشغيل.")

    # [4/4] المراقبة حتى الإغلاق
    print("[4/4] Clippify يعمل — أغلق نافذة التطبيق أو اضغط Ctrl+C للإيقاف.")
    try:
        while True:
            if stop.is_set():
                print("\nانتهى وقت التشغيل المحدد (--exit-after) — إيقاف نظيف.")
                break
            if frontend is not None and frontend.poll() is not None:
                print("\nتم إغلاق نافذة التطبيق.")
                break
            if backend_ours and backend is not None and backend.poll() is not None:
                print("\n[تحذير] عملية الباك إند خرجت بشكل غير متوقع — الواجهة قد تعيد تشغيله بنفسها.")
                backend = None
            time.sleep(1.0)
    except KeyboardInterrupt:
        print("\nتم استلام Ctrl+C — إيقاف كل العمليات...")
    finally:
        _cleanup(frontend, backend, backend_ours, host, port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
