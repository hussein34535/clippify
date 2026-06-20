"""
Pytest configuration shared across all Clippify Python tests.
"""

import os
import sys

import pytest

_PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)


def _can_import_backend() -> bool:
    try:
        import api  # noqa: F401
        return True
    except Exception as exc:
        print(f"[conftest] backend import failed: {exc}")
        return False


_BACKEND_AVAILABLE = _can_import_backend()


@pytest.fixture(scope="session")
def client():
    if not _BACKEND_AVAILABLE:
        pytest.skip(
            "Backend not importable — install requirements.txt "
            "(faster_whisper, easyocr, librosa, torch, ...) to run API tests"
        )
    from fastapi.testclient import TestClient
    from api import app
    return TestClient(app)


@pytest.fixture
def sample_video_path() -> str:
    fixture = os.path.join(os.path.dirname(__file__), "fixtures", "sample.mp4")
    if not os.path.exists(fixture):
        pytest.skip("Sample video fixture missing — drop tests/fixtures/sample.mp4 to enable")
    return fixture
