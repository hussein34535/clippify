"""Offline tests for trend_seed.py — all network sources mocked, <5s."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys_path = str(Path(__file__).resolve().parents[1])
if sys_path not in sys.path:
    sys.path.insert(0, sys_path)

import trend_seed


@pytest.fixture
def trends_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(trend_seed, "TRENDS_DIR", str(tmp_path))
    return tmp_path


# ── local seeds ──────────────────────────────────────────────────────────────

@pytest.mark.parametrize("niche", ["podcast", "comedy", "gaming"])
def test_load_local_trends_seeded_files(niche):
    trends = trend_seed.load_local_trends(niche)
    assert len(trends) >= 5
    for t in trends:
        assert set(t) == {"title", "source", "url", "score", "tags", "sounds"}
        assert t["source"] == "local"
        assert isinstance(t["tags"], list)
        assert isinstance(t["sounds"], list)


def test_load_local_trends_missing_niche_returns_empty(trends_dir):
    assert trend_seed.load_local_trends("nope_niche") == []


def test_load_local_trends_corrupt_json_returns_empty(trends_dir):
    (trends_dir / "broken.json").write_text("{not json", encoding="utf-8")
    assert trend_seed.load_local_trends("broken") == []


# ── save/load roundtrip ──────────────────────────────────────────────────────

def test_save_trends_roundtrip_arabic(trends_dir):
    rows = [{"title": "ترند جديد للبودكاست", "source": "youtube",
             "url": "https://youtu.be/x", "score": 12.5,
             "tags": ["#بودكاست"], "sounds": ["vine boom"]}]
    path = trend_seed.save_trends("podcast", rows)
    assert Path(path).exists()
    loaded = trend_seed.load_local_trends("podcast")
    assert loaded == rows


# ── youtube graceful failure (no network) ────────────────────────────────────

def test_fetch_youtube_graceful_when_ytdlp_missing(monkeypatch):
    monkeypatch.setattr(trend_seed, "_find_ytdlp", lambda: None)
    assert trend_seed.fetch_youtube_trending() == []


def test_fetch_youtube_graceful_on_subprocess_error(monkeypatch):
    monkeypatch.setattr(trend_seed, "_find_ytdlp", lambda: ["yt-dlp-fake"])

    def boom(*a, **k):
        raise subprocess.TimeoutExpired(cmd="yt-dlp-fake", timeout=1)

    monkeypatch.setattr(trend_seed.subprocess, "run", boom)
    assert trend_seed.fetch_youtube_trending() == []


def test_fetch_youtube_parses_json_lines(monkeypatch):
    monkeypatch.setattr(trend_seed, "_find_ytdlp", lambda: ["yt-dlp-fake"])

    class P:
        returncode = 0
        stdout = json.dumps({"title": "Podcast Mic Review",
                             "webpage_url": "https://youtu.be/1",
                             "tags": ["podcast", "#mic"],
                             "track": "Lofi Beat"}) + "\n" + \
                json.dumps({"title": "Gaming Stream Highlights",
                            "url": "https://youtu.be/2"}) + "\n"

    monkeypatch.setattr(trend_seed.subprocess, "run", lambda *a, **k: P())
    out = trend_seed.fetch_youtube_trending()
    assert [t["title"] for t in out] == [
        "Podcast Mic Review", "Gaming Stream Highlights"]
    assert out[0]["sounds"] == ["Lofi Beat"]
    assert out[1]["sounds"] == []


# ── reddit parse via mocked urlopen ──────────────────────────────────────────

class _FakeResp:
    def __init__(self, payload):
        self._payload = json.dumps(payload).encode()

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self):
        return self._payload


def test_fetch_reddit_hot_parses_posts(monkeypatch):
    payload = {"data": {"children": [
        {"data": {"title": "Best mic under $100?",
                  "score": 42,
                  "permalink": "/r/podcasting/comments/abc1"}},
        {"data": {"title": "", "score": 5, "permalink": "/r/x/comments/skip"}},
    ]}}
    captured = {}

    def fake_urlopen(req, timeout=0):
        captured["url"] = req.full_url
        captured["ua"] = req.headers.get("User-agent")
        return _FakeResp(payload)

    monkeypatch.setattr(trend_seed.urllib.request, "urlopen", fake_urlopen)
    out = trend_seed.fetch_reddit_hot("podcasting")
    assert len(out) == 1
    assert out[0]["title"] == "Best mic under $100?"
    assert out[0]["score"] == 42.0
    assert out[0]["url"].endswith("/r/podcasting/comments/abc1")
    assert "podcasting/hot.json" in captured["url"]
    assert "Clippify" in captured["ua"]


def test_fetch_reddit_hot_graceful_on_network_error(monkeypatch):
    def fail(req, timeout=0):
        raise OSError("offline")

    monkeypatch.setattr(trend_seed.urllib.request, "urlopen", fail)
    assert trend_seed.fetch_reddit_hot() == []


# ── aggregation: dedup + scoring + top-20 ────────────────────────────────────

def _mock_sources(monkeypatch, local=None, yt=None, reddit=None):
    monkeypatch.setattr(trend_seed, "load_local_trends",
                        lambda n: list(local or []))
    monkeypatch.setattr(trend_seed, "fetch_youtube_trending",
                        lambda region="EG": list(yt or []))
    monkeypatch.setattr(trend_seed, "fetch_reddit_hot",
                        lambda subreddit="TikTokHelp": list(reddit or []))


def test_aggregate_dedup_similar_titles(trends_dir, monkeypatch):
    local = [{"title": "how to start a podcast today", "source": "local",
              "url": "", "score": 0, "tags": [], "sounds": []}]
    yt = [{"title": "How to Start a Podcast Today!", "source": "youtube",
           "url": "u1", "score": 0, "tags": [], "sounds": []},
          {"title": "gaming highlights of the week", "source": "youtube",
           "url": "u2", "score": 0, "tags": [], "sounds": []}]
    reddit = [{"title": "gaming highlights this week", "source": "reddit",
               "url": "r1", "score": 0, "tags": [], "sounds": []}]
    (trends_dir / "podcast.json").write_text(
        json.dumps(local), encoding="utf-8")
    monkeypatch.setattr(trend_seed, "fetch_youtube_trending",
                        lambda region="EG": yt)
    monkeypatch.setattr(trend_seed, "fetch_reddit_hot",
                        lambda subreddit="TikTokHelp": reddit)
    agg = trend_seed.aggregate_trends("podcast")
    titles = {t["title"].lower() for t in agg}
    assert len(agg) == 2
    assert any("podcast" in x for x in titles)
    assert any("gaming" in x for x in titles)


def test_aggregate_sorted_by_relevance_and_capped_at_20(monkeypatch):
    yt = [{"title": f"topic{chr(97 + i % 26)} montage",
           "source": "youtube", "url": f"u{i}", "score": 0,
           "tags": [], "sounds": []} for i in range(25)]
    yt.append({"title": "best gaming gameplay stream of the year",
               "source": "youtube", "url": "top", "score": 0,
               "tags": [], "sounds": []})
    _mock_sources(monkeypatch, yt=yt)
    agg = trend_seed.aggregate_trends("gaming")
    assert len(agg) == 20
    scores = [t["score"] for t in agg]
    assert scores == sorted(scores, reverse=True)
    assert agg[0]["title"] == "best gaming gameplay stream of the year"
    assert agg[0]["score"] > 0


def test_aggregate_empty_pool_returns_empty(monkeypatch):
    _mock_sources(monkeypatch)
    assert trend_seed.aggregate_trends("comedy") == []


# ── extractors ───────────────────────────────────────────────────────────────

def test_get_trending_hashtags_extracts_and_dedups(monkeypatch):
    yt = [{"title": "new podcast drop #shorts #فنجان", "source": "youtube",
           "url": "", "score": 0, "tags": ["#PodcastLife"], "sounds": []},
          {"title": "podcast again #SHORTS", "source": "reddit",
           "url": "", "score": 0, "tags": [], "sounds": []}]
    _mock_sources(monkeypatch, yt=yt)
    tags = trend_seed.get_trending_hashtags("podcast")
    lowered = [t.lower() for t in tags]
    assert lowered[0] == "#shorts"
    assert lowered.count("#shorts") == 1
    assert "#podcastlife" in lowered
    assert "#فنجان" in lowered


def test_get_trending_sounds_extracts_and_dedups(monkeypatch):
    yt = [{"title": "clip one", "source": "youtube", "url": "",
           "score": 0, "tags": [], "sounds": ["Vine Boom"]},
          {"title": "clip two", "source": "youtube", "url": "",
           "score": 0, "tags": [], "sounds": ["vine boom", "Air Horn"]}]
    _mock_sources(monkeypatch, yt=yt)
    assert trend_seed.get_trending_sounds("podcast") == [
        "Vine Boom", "Air Horn"]
