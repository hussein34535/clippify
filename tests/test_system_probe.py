"""Offline tests for system_probe (pathing / probe / router).

No real hardware calls: every subprocess/network touchpoint is monkeypatched.
Runs in well under 5 seconds.
"""

from __future__ import annotations

import importlib
import json
import sys

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

# NOTE: importlib on purpose â€” `system_probe.probe` (function) would shadow
# the submodule through plain attribute access.
pathing = importlib.import_module("system_probe.pathing")
probe_mod = importlib.import_module("system_probe.probe")
router_mod = importlib.import_module("system_probe.router")


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def _probe_dict(**overrides) -> dict:
    """Baseline probe snapshot resembling a mid machine; tests override keys."""
    cpu = {"name": "Test CPU", "cores": 6, "threads": 12}
    accel = {"nvenc": False, "qsv": False, "vaapi": False, "cuda": False}
    snapshot = {
        "cpu": dict(cpu),
        "ram_gb": 16.0,
        "gpus": [{"name": "Fake GPU", "vram_gb": 4.0}],
        "accel": accel,
        "nvidia_vram_gb": 0.0,
        "ollama": {"running": False, "models": []},
        "disk_free_gb": 120.0,
        "ffmpeg_path": r"C:\fake\ffmpeg.exe",
        "ffprobe_path": None,
    }
    if "cpu" in overrides:
        overrides["cpu"] = {**cpu, **overrides["cpu"]}
    if "accel" in overrides:
        overrides["accel"] = {**accel, **overrides["accel"]}
    snapshot.update(overrides)
    return snapshot


@pytest.fixture(autouse=True)
def _clean_caches(monkeypatch):
    pathing.reset_cache()
    monkeypatch.delenv("CLIPPIFY_FFMPEG", raising=False)
    monkeypatch.delenv("CLIPPIFY_FFPROBE", raising=False)
    yield
    pathing.reset_cache()


# --------------------------------------------------------------------------
# 1. decision matrix (table-driven)
# --------------------------------------------------------------------------
_DECISION_MATRIX = [
    # (id, overrides over _probe_dict(), expected tier)
    ("S_nvenc_6gb", dict(accel=dict(nvenc=True), nvidia_vram_gb=6.0), "S"),
    ("S_nvenc_8gb_even_low_ram", dict(
        accel=dict(nvenc=True), nvidia_vram_gb=8.0, ram_gb=2.0, cpu=dict(threads=2)), "S"),
    ("Aplus_nvenc_exactly_4gb_boundary", dict(
        accel=dict(nvenc=True), nvidia_vram_gb=4.0), "A+"),
    ("Aplus_qsv_only", dict(accel=dict(qsv=True), nvidia_vram_gb=0.0), "A+"),
    ("Aplus_qsv_beats_missing_nvidia", dict(
        accel=dict(qsv=True, cuda=False), nvidia_vram_gb=0.0, gpus=[{"name": "Intel Iris"}]), "A+"),
    ("A_nvenc_below_4gb", dict(
        accel=dict(nvenc=True), nvidia_vram_gb=3.9), "A"),
    ("A_strong_cpu_no_accel", dict(nvidia_vram_gb=0.0, gpus=[]), "A"),
    ("B_ram_just_under_8", dict(ram_gb=7.9, cpu=dict(threads=4)), "B"),
    ("B_ram_exactly_4", dict(ram_gb=4.0, cpu=dict(threads=2)), "B"),
    ("B_ram_7_threads_2", dict(ram_gb=7.0, cpu=dict(threads=2)), "B"),
    ("C_ram_3point5", dict(ram_gb=3.5, cpu=dict(threads=2)), "C"),
    ("C_ram_under_4_boundary", dict(ram_gb=3.99, cpu=dict(threads=1)), "C"),
    ("A_threads_exactly_8_boundary", dict(
        ram_gb=8.0, cpu=dict(threads=8), gpus=[], nvidia_vram_gb=0.0), "A"),
]


@pytest.mark.parametrize("case_id,overrides,expected_tier", _DECISION_MATRIX, ids=[c[0] for c in _DECISION_MATRIX])
def test_decision_matrix(case_id, overrides, expected_tier):
    verdict = probe_mod.decide_tier(_probe_dict(**overrides))
    assert verdict["tier"] == expected_tier
    assert verdict["label_ar"], case_id
    assert verdict["why_ar"], case_id
    assert "accel_summary" in verdict


def test_tier_labels_exact_strings():
    p = _probe_dict()
    cases = {
        "S": dict(p, accel={**p["accel"], "nvenc": True}, nvidia_vram_gb=6.5),
        "A+": dict(p, accel={**p["accel"], "qsv": True}),
        "A": dict(p, nvidia_vram_gb=0.0, gpus=[]),
        "B": dict(p, ram_gb=6.0, cpu={"name": "x", "cores": 2, "threads": 4}),
        "C": dict(p, ram_gb=3.0, cpu={"name": "x", "cores": 2, "threads": 2}),
    }
    for tier, overrides in cases.items():
        verdict = probe_mod.decide_tier(overrides)
        assert verdict["tier"] == tier, f"expected {tier}, got {verdict['tier']}"
        assert verdict["label_ar"], f"label_ar should be non-empty for {tier}"
        assert verdict["label_en"], f"label_en should be non-empty for {tier}"

def test_accel_summary_joins_true_flags():
    verdict = probe_mod.decide_tier(_probe_dict(accel=dict(nvenc=True, qsv=True, cuda=True)))
    assert set(verdict["accel_summary"].split("+")) == {"nvenc", "qsv", "cuda"}
    assert probe_mod.decide_tier(_probe_dict())["accel_summary"] == "none"


# --------------------------------------------------------------------------
# 2. CIM parser fixtures
# --------------------------------------------------------------------------
_CPU_JSON_SINGLE = json.dumps(
    {
        "Name": "Intel(R) Core(TM) i7-10850H CPU @ 2.70GHz",
        "NumberOfCores": 6,
        "NumberOfLogicalProcessors": 12,
    }
)

_CPU_JSON_MULTI = json.dumps(
    [
        {"Name": "CPU A", "NumberOfCores": 4, "NumberOfLogicalProcessors": 8},
        {"Name": "", "NumberOfCores": 4, "NumberOfLogicalProcessors": 8},
    ]
)


def test_parse_cim_single_object():
    rows = probe_mod._cim_rows(_CPU_JSON_SINGLE)
    assert len(rows) == 1
    assert rows[0]["NumberOfLogicalProcessors"] == 12
    assert "i7-10850H" in rows[0]["Name"]


def test_parse_cim_multi_object_list():
    rows = probe_mod._cim_rows(_CPU_JSON_MULTI)
    assert len(rows) == 2
    assert sum(r["NumberOfCores"] for r in rows) == 8


def test_parse_cim_garbage_and_empty():
    assert probe_mod._cim_rows("") == []
    assert probe_mod._cim_rows("not-json at all {{{") == []
    assert probe_mod._cim_rows("42") == []


def test_cpu_info_sums_multi_socket():
    monkey_out = _CPU_JSON_MULTI
    orig = probe_mod._run_powershell
    probe_mod._run_powershell = lambda script, timeout=10: (
        monkey_out if "Win32_Processor" in script else ""
    )
    try:
        info = probe_mod._cpu_info()
    finally:
        probe_mod._run_powershell = orig
    assert info["threads"] == 16 and info["cores"] == 8
    assert info["name"] == "CPU A"


# --------------------------------------------------------------------------
# 3. ffmpeg -encoders string parser
# --------------------------------------------------------------------------
_ENCODERS_NVENC_QSV = (
    " V....D h264_nvenc           NVIDIA NVENC H.264 encoder (codec h264)\n"
    " V....D hevc_nvenc           NVIDIA NVENC hevc encoder (codec hevc)\n"
    " V....D h264_qsv             Hardware accelerated QSV H.264 (codec h264)\n"
    " V....D libx264              libx264 H.264 (codec h264)\n"
)


def test_encoders_parser_flags_nvenc_qsv_only():
    flags = probe_mod._parse_encoders(_ENCODERS_NVENC_QSV)
    assert flags == {"nvenc": True, "qsv": True, "vaapi": False}


def test_encoders_parser_vaapi_only():
    flags = probe_mod._parse_encoders(" V....D h264_vaapi Intel VAAPI (codec h264)\n")
    assert flags == {"nvenc": False, "qsv": False, "vaapi": True}


def test_encoders_parser_empty_output():
    assert probe_mod._parse_encoders("") == {"nvenc": False, "qsv": False, "vaapi": False}


def test_accel_requires_ffmpeg_path():
    flags = probe_mod._accel(None, nvidia_smi_ok=False)
    assert flags == {"nvenc": False, "qsv": False, "vaapi": False, "cuda": False}
    orig = probe_mod._run_checked
    probe_mod._run_checked = lambda cmd, timeout=10: (0, _ENCODERS_NVENC_QSV)
    try:
        flags = probe_mod._accel(r"C:\fake\ffmpeg.exe", nvidia_smi_ok=True)
    finally:
        probe_mod._run_checked = orig
    assert flags["nvenc"] and flags["qsv"] and not flags["vaapi"] and flags["cuda"]


# --------------------------------------------------------------------------
# 4. resolve_ffmpeg / resolve_ffprobe cascades
# --------------------------------------------------------------------------
class _FakeImageio:
    def __init__(self, exe):
        self._exe = exe

    def get_ffmpeg_exe(self):
        return self._exe


def test_resolve_ffmpeg_env_var_wins(monkeypatch, tmp_path):
    env_exe = tmp_path / "env-ffmpeg.exe"
    which_exe = tmp_path / "which-ffmpeg.exe"
    for f in (env_exe, which_exe):
        f.write_bytes(b"")
    monkeypatch.setenv("CLIPPIFY_FFMPEG", str(env_exe))
    monkeypatch.setattr(pathing.shutil, "which", lambda name: str(which_exe))
    assert pathing.resolve_ffmpeg(force=True) == str(env_exe)


def test_resolve_ffmpeg_env_var_invalid_falls_through(monkeypatch, tmp_path):
    which_exe = tmp_path / "which-ffmpeg.exe"
    which_exe.write_bytes(b"")
    monkeypatch.setenv("CLIPPIFY_FFMPEG", str(tmp_path / "missing.exe"))
    monkeypatch.setattr(pathing.shutil, "which", lambda name: str(which_exe))
    assert pathing.resolve_ffmpeg(force=True) == str(which_exe)


def test_resolve_ffmpeg_imageio_fallback(monkeypatch, tmp_path):
    fake = tmp_path / "imageio-ffmpeg.exe"
    fake.write_bytes(b"")
    monkeypatch.setitem(sys.modules, "imageio_ffmpeg", _FakeImageio(str(fake)))
    monkeypatch.setattr(pathing.shutil, "which", lambda name: None)
    assert pathing.resolve_ffmpeg(force=True) == str(fake)


def test_resolve_ffmpeg_glob_common_dirs(monkeypatch, tmp_path):
    bin_dir = tmp_path / "ffmpeg-n1" / "bin"
    bin_dir.mkdir(parents=True)
    hit = bin_dir / "ffmpeg.exe"
    hit.write_bytes(b"")
    monkeypatch.setattr(pathing.shutil, "which", lambda name: None)
    monkeypatch.setitem(sys.modules, "imageio_ffmpeg", None)  # force imageio step to miss
    monkeypatch.setattr(
        pathing, "_candidate_patterns", lambda binary: [str(bin_dir / "*.exe")]
    )
    assert pathing.resolve_ffmpeg(force=True) == str(hit)


def test_resolve_ffmpeg_total_miss_returns_none(monkeypatch, tmp_path):
    monkeypatch.setattr(pathing.shutil, "which", lambda name: None)
    monkeypatch.delitem(sys.modules, "imageio_ffmpeg", raising=False)
    monkeypatch.setitem(sys.modules, "imageio_ffmpeg", None)  # import -> ImportError
    monkeypatch.setattr(pathing, "_candidate_patterns", lambda binary: [str(tmp_path / "none*" / "bin" / "x.exe")])
    assert pathing.resolve_ffmpeg(force=True) is None
    # ffprobe cascade never touches imageio -> also None
    assert pathing.resolve_ffprobe(force=True) is None


def test_resolve_ffprobe_env_and_which(monkeypatch, tmp_path):
    exe = tmp_path / "ffprobe.exe"
    exe.write_bytes(b"")
    monkeypatch.setattr(pathing.shutil, "which", lambda name: str(exe))
    assert pathing.resolve_ffprobe(force=True) == str(exe)
    missing = tmp_path / "gone.exe"
    monkeypatch.setenv("CLIPPIFY_FFPROBE", str(missing))
    monkeypatch.setattr(pathing.shutil, "which", lambda name: None)
    assert pathing.resolve_ffprobe(force=True) is None


def test_resolve_cache_hit_until_reset(monkeypatch, tmp_path):
    calls = {"which": 0}

    def counting_which(name):
        calls["which"] += 1
        return None

    monkeypatch.setattr(pathing.shutil, "which", counting_which)
    monkeypatch.setitem(sys.modules, "imageio_ffmpeg", None)
    monkeypatch.setattr(pathing, "_candidate_patterns", lambda b: [str(tmp_path / "nope*")])
    first = pathing.resolve_ffmpeg()
    second = pathing.resolve_ffmpeg()
    assert first is None and second is None
    assert calls["which"] == 1  # cached
    pathing.reset_cache()
    pathing.resolve_ffmpeg()
    assert calls["which"] == 2  # re-resolved after reset


# --------------------------------------------------------------------------
# 5. router endpoints (FastAPI TestClient, probe monkeypatched)
# --------------------------------------------------------------------------
_STATIC_SNAPSHOT = _probe_dict(
    accel=dict(nvenc=True, qsv=True, cuda=True),
    nvidia_vram_gb=4.0,
)


@pytest.fixture()
def client(monkeypatch):
    monkeypatch.setattr(probe_mod, "probe", lambda force=False: dict(_STATIC_SNAPSHOT))
    monkeypatch.setattr(pathing, "resolve_ffmpeg", lambda force=False: r"C:\fake\ffmpeg.exe")
    app = FastAPI()
    app.include_router(router_mod.router)
    return TestClient(app)


def test_router_system_tier_merges_probe_and_verdict(client):
    resp = client.get("/tier")
    assert resp.status_code == 200
    body = resp.json()
    # probe passthrough
    assert body["ram_gb"] == 16.0
    assert body["cpu"]["threads"] == 12
    assert body["ffmpeg_path"].endswith("ffmpeg.exe")
    # verdict merged
    assert body["tier"] == "A+"
    assert body["label_ar"], "label_ar should be non-empty"
    assert "nvenc" in body["accel_summary"]
    assert body["why_ar"]


def test_router_system_tier_uses_cached_probe(client):
    client.get("/tier")
    client.get("/tier")


def test_router_system_ffmpeg_found(client):
    resp = client.get("/ffmpeg")
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"path": r"C:\fake\ffmpeg.exe", "found": True}


def test_router_system_ffmpeg_not_found(monkeypatch):
    monkeypatch.setattr(probe_mod, "probe", lambda force=False: dict(_STATIC_SNAPSHOT))
    monkeypatch.setattr(pathing, "resolve_ffmpeg", lambda force=False: None)
    app = FastAPI()
    app.include_router(router_mod.router)
    with TestClient(app) as c:
        body = c.get("/ffmpeg").json()
    assert body == {"path": None, "found": False}


# --------------------------------------------------------------------------
# 6. probe() caching behaviour (collect fully mocked)
# --------------------------------------------------------------------------
def test_probe_caches_for_ttl(monkeypatch):
    counter = {"n": 0}

    def fake_collect():
        counter["n"] += 1
        return _probe_dict()

    monkeypatch.setattr(probe_mod, "_collect", fake_collect)
    probe_mod.probe(force=True)
    probe_mod.probe()
    probe_mod.probe()
    assert counter["n"] == 1
    assert probe_mod.CACHE_TTL_S == 300.0
