"""Unit tests for run_clippify.py — python discovery, port classification,
frontend decision, and process termination. All external effects (subprocess
probes, sockets) are injected; no network or real backend is required."""

import os
import subprocess
import sys
import threading

import pytest

import run_clippify as rc

HEALTH_OK = {"status": "ok", "message": "Clippify Backend is running"}


# ---------------------------------------------------------------------------
# Python discovery
# ---------------------------------------------------------------------------

def test_env_var_candidate_comes_first(monkeypatch, tmp_path):
    fake = tmp_path / "custom_python.exe"
    fake.write_text("")
    monkeypatch.setenv("CLIPPIFY_PYTHON", str(fake))
    candidates = rc.build_python_candidates()
    assert candidates[0] == [str(fake)]


def test_no_env_var_keeps_default_order(monkeypatch):
    monkeypatch.delenv("CLIPPIFY_PYTHON", raising=False)
    candidates = rc.build_python_candidates()
    assert ["py", "-3"] in candidates
    assert candidates[-1] == ["python"]


def test_candidates_are_deduped(monkeypatch):
    monkeypatch.delenv("CLIPPIFY_PYTHON", raising=False)
    candidates = rc.build_python_candidates()
    assert sum(1 for c in candidates if c == [sys.executable]) == 1


@pytest.mark.skipif(os.name != "nt", reason="Windows-only install locations")
def test_localappdata_candidates_discovered(monkeypatch, tmp_path):
    bin_py = tmp_path / "Python" / "bin" / "python.exe"
    ver_py = tmp_path / "Python" / "Python314" / "python.exe"
    prog_py = tmp_path / "Programs" / "Python" / "Python313" / "python.exe"
    for f in (bin_py, ver_py, prog_py):
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text("")
    monkeypatch.setenv("LOCALAPPDATA", str(tmp_path))
    monkeypatch.delenv("CLIPPIFY_PYTHON", raising=False)
    candidates = rc.build_python_candidates()
    assert [str(bin_py)] in candidates
    assert [str(ver_py)] in candidates
    assert [str(prog_py)] in candidates
    # the well-known bin\python.exe is probed before the globbed versions
    assert candidates.index([str(bin_py)]) < candidates.index([str(ver_py)])


def test_choose_python_returns_first_success(monkeypatch, tmp_path):
    a = tmp_path / "a.exe"
    b = tmp_path / "b.exe"
    c = tmp_path / "c.exe"
    for f in (a, b, c):
        f.write_text("")
    monkeypatch.setattr(rc, "build_python_candidates", lambda: [[str(a)], [str(b)], [str(c)]])
    probed = []

    def probe(cmd):
        probed.append(cmd)
        return cmd == [str(b)]

    chosen = rc.choose_python(probe=probe, announce=lambda *_: None)
    assert chosen == [str(b)]
    assert probed[0] == [str(a)]
    assert probed[-1] == [str(b)]  # stops right after the first success


def test_choose_python_none_when_all_fail(monkeypatch):
    monkeypatch.setattr(rc, "build_python_candidates", lambda: [["x"], ["y"]])
    assert rc.choose_python(probe=lambda cmd: False, announce=lambda *_: None) is None


def test_choose_python_prefers_env_candidate(monkeypatch, tmp_path):
    fake = tmp_path / "envpy.exe"
    fake.write_text("")
    monkeypatch.setenv("CLIPPIFY_PYTHON", str(fake))
    order = []

    def probe(cmd):
        order.append(cmd[0])
        return cmd == [str(fake)]

    chosen = rc.choose_python(probe=probe, announce=lambda *_: None)
    assert chosen == [str(fake)]
    assert order[0] == str(fake)


# ---------------------------------------------------------------------------
# Port classification & health
# ---------------------------------------------------------------------------

def test_is_clippify_health():
    assert rc.is_clippify_health(HEALTH_OK)
    assert not rc.is_clippify_health({"status": "ok", "message": "some other server"})
    assert not rc.is_clippify_health({"message": "Clippify Backend is running"})
    assert not rc.is_clippify_health(None)
    assert not rc.is_clippify_health({"status": "error"})


def test_classify_port_states():
    free = rc.classify_port("127.0.0.1", 8000, opener=lambda h, p: False, fetcher=lambda h, p: None)
    ours = rc.classify_port("127.0.0.1", 8000, opener=lambda h, p: False, fetcher=lambda h, p: HEALTH_OK)
    busy_open_other = rc.classify_port("127.0.0.1", 8000, opener=lambda h, p: True, fetcher=lambda h, p: None)
    busy_other_server = rc.classify_port("127.0.0.1", 8000, opener=lambda h, p: False,
                                         fetcher=lambda h, p: {"status": "ok", "message": "nginx"})
    assert (free, ours, busy_open_other, busy_other_server) == ("free", "ours", "busy", "busy")


def test_find_free_port_skips_busy():
    assert rc.find_free_port("127.0.0.1", start=8001, tries=5, opener=lambda h, p: p == 8001) == 8002


def test_find_free_port_none_when_all_busy():
    assert rc.find_free_port("127.0.0.1", start=8001, tries=3, opener=lambda h, p: True) is None


def test_wait_backend_ready_success_after_retries():
    calls = {"n": 0}

    def fetcher(h, p):
        calls["n"] += 1
        return None if calls["n"] < 3 else HEALTH_OK

    assert rc.wait_backend_ready("127.0.0.1", 8000, timeout=5, fetcher=fetcher, interval=0) is True
    assert calls["n"] == 3


def test_wait_backend_ready_timeout():
    assert rc.wait_backend_ready("127.0.0.1", 8000, timeout=0.15,
                                 fetcher=lambda h, p: None, interval=0.02) is False


def test_wait_backend_ready_stops_on_stop_event():
    stop = threading.Event()
    stop.set()
    assert rc.wait_backend_ready("127.0.0.1", 8000, timeout=10,
                                 fetcher=lambda h, p: None, stop=stop, interval=0) is False


def test_wait_backend_ready_announces_progress():
    lines = []
    rc.wait_backend_ready("127.0.0.1", 8000, timeout=0.3, fetcher=lambda h, p: None,
                          interval=0.05, announce=lines.append)
    assert lines and "..." in lines[0]


# ---------------------------------------------------------------------------
# Frontend decision
# ---------------------------------------------------------------------------

def test_decide_frontend_prefers_flutter():
    action, detail = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd=r"C:\flutter\bin\flutter.bat",
        release_exe="r.exe", debug_exe="d.exe")
    assert action == "flutter"
    assert detail.endswith("flutter.bat")


def test_decide_frontend_falls_back_to_release_exe():
    action, detail = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd=None, release_exe="r.exe", debug_exe="d.exe")
    assert (action, detail) == ("exe", "r.exe")


def test_decide_frontend_falls_back_to_debug_exe():
    action, detail = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd=None, release_exe=None, debug_exe="d.exe")
    assert (action, detail) == ("exe", "d.exe")


def test_decide_frontend_none_when_nothing_available():
    action, reason = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd=None, release_exe=None, debug_exe=None)
    assert action == "none"
    assert reason


def test_decide_frontend_pref_override_exe():
    action, detail = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd="f.bat",
        release_exe="r.exe", debug_exe=None, prefer="exe")
    assert (action, detail) == ("exe", "r.exe")


def test_decide_frontend_pref_override_none():
    action, _ = rc.decide_frontend(
        flutter_dir_exists=True, flutter_cmd="f.bat",
        release_exe="r.exe", debug_exe="d.exe", prefer="none")
    assert action == "none"


# ---------------------------------------------------------------------------
# Env parsing helpers & CLI
# ---------------------------------------------------------------------------

def test_get_port_env_override(monkeypatch):
    monkeypatch.setenv("CLIPPIFY_PORT", "8123")
    assert rc.get_port() == 8123


def test_get_port_invalid_falls_back(monkeypatch):
    monkeypatch.setenv("CLIPPIFY_PORT", "abc")
    assert rc.get_port() == rc.DEFAULT_PORT


def test_get_host_default_and_override(monkeypatch):
    monkeypatch.delenv("CLIPPIFY_HOST", raising=False)
    assert rc.get_host() == rc.DEFAULT_HOST
    monkeypatch.setenv("CLIPPIFY_HOST", "0.0.0.0")
    assert rc.get_host() == "0.0.0.0"


def test_parse_args_defaults():
    args = rc.parse_args([])
    assert not args.dry_run
    assert not args.backend_only
    assert args.exit_after is None


def test_parse_args_flags():
    args = rc.parse_args(["--dry-run", "--backend-only", "--exit-after", "12.5"])
    assert args.dry_run
    assert args.backend_only
    assert args.exit_after == pytest.approx(12.5)


# ---------------------------------------------------------------------------
# Real process termination (the one behavioral test with a real subprocess)
# ---------------------------------------------------------------------------

def test_terminate_tree_kills_process():
    proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    assert proc.poll() is None
    rc.terminate_tree(proc)
    assert proc.poll() is not None
