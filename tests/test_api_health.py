"""
Smoke tests for the Clippify FastAPI backend.
"""

import pytest


def test_health_endpoint(client):
    response = client.get("/api/health")
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "ok", f"Unexpected health payload: {data}"


def test_settings_get(client):
    response = client.get("/api/settings")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")


def test_ai_tools_list_returns_219(client):
    response = client.get("/api/ai/tools")
    assert response.status_code == 200
    data = response.json()
    assert "tools" in data, f"Missing 'tools' key in payload: {data}"
    tools_by_category = data["tools"]
    assert isinstance(tools_by_category, dict), "tools payload must be a dict of category -> list"
    total = sum(len(tools) for tools in tools_by_category.values())
    assert total == 219, f"Expected 219 tools across all categories, got {total}"


def test_download_youtube_rejects_invalid_url(client):
    response = client.post(
        "/api/download-youtube",
        json={"url": "https://evil.example.com/watch?v=abc"},
    )
    assert response.status_code == 400, f"Expected 400 for invalid URL, got {response.status_code}"


def test_download_youtube_rejects_shell_injection(client):
    response = client.post(
        "/api/download-youtube",
        json={"url": "https://youtube.com/watch?v=abc;rm -rf /"},
    )
    assert response.status_code == 400, f"Expected 400 for shell injection, got {response.status_code}"


def test_download_youtube_rejects_http(client):
    response = client.post(
        "/api/download-youtube",
        json={"url": "http://youtube.com/watch?v=abc"},
    )
    assert response.status_code == 400, f"Expected 400 for non-HTTPS URL, got {response.status_code}"


def test_openapi_docs_available(client):
    response = client.get("/docs")
    assert response.status_code == 200


def test_websocket_endpoint(client):
    with client.websocket_connect("/ws") as ws1:
        with client.websocket_connect("/ws") as ws2:
            ws1.send_text("Hello from client 1")
            data = ws2.receive_text()
            assert data == "Hello from client 1"


def test_ai_execute_generate_title(client):
    timeline_state = {
        "tracks": {
            "subtitles": [
                {
                    "clips": [
                        {"start_time": 0.0, "end_time": 2.0, "text": "Hello world this is a test"},
                        {"start_time": 2.0, "end_time": 5.0, "text": "of the clippify ai video editor tool"}
                    ]
                }
            ],
            "video": [],
            "audio": [],
            "overlays": []
        }
    }
    response = client.post(
        "/api/ai/execute",
        json={
            "actions": [{"name": "ai.generate_title", "args": {}}],
            "timeline_state": timeline_state
        }
    )
    assert response.status_code == 200
    data = response.json()
    assert data.get("status") == "success"
    assert "results" in data
    assert len(data["results"]) == 1
    assert data["results"][0]["ok"] is True
    assert "Suggested Titles" in data["results"][0]["message"]


