"""
trend_seed.py — Trend Data Provider for Clippify.

Aggregates short-form video trend signals from multiple FREE sources:
  1. Local seed/cache  → trends_data/{niche}.json  (offline, always available)
  2. YouTube trending  → yt-dlp subprocess (graceful no-op if not installed)
  3. Reddit hot posts  → public .json endpoint via pure urllib (no requests dep)

Every trend dict follows the schema:
  {title: str, source: str, url: str, score: float, tags: [str], sounds: [str]}
`score` is recomputed by aggregate_trends() as a niche keyword-relevance
rating (0-100). Higher is better.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

TRENDS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "trends_data")

_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36 ClippifyTrendSeed/1.0"
)

_DEDUP_THRESHOLD = 0.6
_TOP_N = 20
_YTDLP_TIMEOUT = 90
_REDDIT_TIMEOUT = 8

_NICHE_KEYWORDS = {
    "podcast": [
        "podcast", "بودكاست", "مقابلة", "انترفيو", "interview", "episode",
        "حلقة", "story", "قصة", "studio", "mic", "مايك", "montage", "مونتاج",
    ],
    "comedy": [
        "comedy", "كوميدي", "funny", "مضحك", "اضحك", "laugh", "ضحك",
        "sketch", "اسكتش", "prank", "مقلب", "standup", "pov",
    ],
    "gaming": [
        "gaming", "جيمينج", "game", "لعبة", "العاب", "gameplay", "بث",
        "stream", "speedrun", "esports", "valorant", "fortnite", "fps",
    ],
}

_NICHE_SUBREDDITS = {
    "podcast": "podcasting",
    "comedy": "comedy",
    "gaming": "gaming",
}

_ARABIC_STRIP_RE = re.compile(r"[\u064B-\u0652\u0670\u0640]")
_HASHTAG_RE = re.compile(r"#\w+")


# ── helpers ──────────────────────────────────────────────────────────────────

def _clean_niche(niche: str) -> str:
    return (niche or "").strip().lower()


def _normalize(text: str) -> str:
    t = _ARABIC_STRIP_RE.sub("", (text or "").lower())
    t = t.replace("\u0623", "\u0627").replace("\u0625", "\u0627").replace("\u0622", "\u0627")
    t = t.replace("\u0629", "\u0647").replace("\u0649", "\u064A")
    return t


def _tokens(text: str) -> set:
    return set(re.findall(r"\w{3,}", _normalize(text)))


def _title_similarity(a: str, b: str) -> float:
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def _make_trend(title, source, url="", tags=None, sounds=None, score=0.0) -> dict:
    return {
        "title": str(title),
        "source": str(source),
        "url": str(url or ""),
        "score": float(score or 0),
        "tags": [str(t) for t in (tags or [])],
        "sounds": [str(s) for s in (sounds or [])],
    }


def _relevance_score(trend: dict, keywords: list) -> float:
    text = _normalize(
        trend.get("title", "") + " " + " ".join(trend.get("tags", []))
    )
    usable = [_normalize(k) for k in keywords if _normalize(k)]
    if not usable:
        return 0.0
    hits = sum(1 for kw in usable if kw in text)
    return round(hits * 100.0 / len(usable), 1)


# ── source 1: local seed / cache ─────────────────────────────────────────────

def load_local_trends(niche: str) -> list:
    path = os.path.join(TRENDS_DIR, _clean_niche(niche) + ".json")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        return []
    if isinstance(data, dict):
        data = data.get("trends", [])
    if not isinstance(data, list):
        return []
    out = []
    for item in data:
        if isinstance(item, dict) and item.get("title"):
            out.append(_make_trend(
                item["title"], item.get("source", "local"),
                item.get("url", ""), item.get("tags"), item.get("sounds"),
                item.get("score", 0),
            ))
    return out


def save_trends(niche: str, trends: list) -> str:
    os.makedirs(TRENDS_DIR, exist_ok=True)
    path = os.path.join(TRENDS_DIR, _clean_niche(niche) + ".json")
    clean = [_make_trend(
        t.get("title", ""), t.get("source", "local"), t.get("url", ""),
        t.get("tags"), t.get("sounds"), t.get("score", 0),
    ) for t in (trends or []) if isinstance(t, dict) and t.get("title")]
    with open(path, "w", encoding="utf-8") as f:
        json.dump(clean, f, ensure_ascii=False, indent=2)
    return path


# ── source 2: YouTube trending via yt-dlp ────────────────────────────────────

def _find_ytdlp():
    exe = shutil.which("yt-dlp")
    if exe:
        return [exe]
    try:
        import yt_dlp  # noqa: F401
        return [sys.executable, "-m", "yt_dlp"]
    except Exception:
        return None


def fetch_youtube_trending(region: str = "EG") -> list:
    base_cmd = _find_ytdlp()
    if not base_cmd:
        return []
    url = "https://www.youtube.com/feed/trending?gl=" + (region or "EG")
    cmd = base_cmd + [
        "--skip-download", "--no-warnings", "--ignore-config",
        "--socket-timeout", "10", "--playlist-items", "12",
        "--dump-json", url,
    ]
    try:
        proc = subprocess.run(
            cmd, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=_YTDLP_TIMEOUT,
        )
    except Exception:
        return []
    if proc.returncode != 0 or not proc.stdout.strip():
        return []
    out = []
    for line in proc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            v = json.loads(line)
        except Exception:
            continue
        title = v.get("title") or ""
        if not title:
            continue
        sounds = [str(v["track"])] if v.get("track") else []
        out.append(_make_trend(
            title, "youtube",
            v.get("webpage_url") or v.get("url") or "",
            [str(t) for t in (v.get("tags") or [])][:15],
            sounds,
        ))
    return out


# ── source 3: Reddit hot via public JSON API (pure urllib) ───────────────────

def fetch_reddit_hot(subreddit: str = "TikTokHelp") -> list:
    sub = (subreddit or "TikTokHelp").strip("/ ")
    url = "https://www.reddit.com/r/{}/hot.json?limit=25&raw_json=1".format(sub)
    req = urllib.request.Request(url, headers={"User-Agent": _UA})
    try:
        with urllib.request.urlopen(req, timeout=_REDDIT_TIMEOUT) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="replace"))
    except Exception:
        return []
    out = []
    children = data.get("data", {}).get("children", []) if isinstance(data, dict) else []
    for child in children:
        d = child.get("data", {}) if isinstance(child, dict) else {}
        title = d.get("title") or ""
        if not title:
            continue
        out.append(_make_trend(
            title, "reddit",
            "https://www.reddit.com" + str(d.get("permalink", "")),
            score=d.get("score", 0),
        ))
    return out


# ── aggregation ──────────────────────────────────────────────────────────────

def aggregate_trends(niche: str) -> list:
    key = _clean_niche(niche)
    pool = []
    pool.extend(load_local_trends(key))
    pool.extend(fetch_youtube_trending())
    pool.extend(fetch_reddit_hot(_NICHE_SUBREDDITS.get(key, "TikTokHelp")))
    if not pool:
        return []
    keywords = _NICHE_KEYWORDS.get(key, [key] if key else [])
    unique = []
    for tr in pool:
        if not isinstance(tr, dict) or not tr.get("title"):
            continue
        if any(_title_similarity(tr["title"], u["title"]) >= _DEDUP_THRESHOLD
               for u in unique):
            continue
        item = _make_trend(tr["title"], tr.get("source", "local"),
                           tr.get("url", ""), tr.get("tags"), tr.get("sounds"))
        item["score"] = _relevance_score(item, keywords)
        unique.append(item)
    priority = {"local": 0, "youtube": 1, "reddit": 2}
    unique.sort(key=lambda t: (-t["score"],
                               priority.get(t["source"], 9),
                               t["title"]))
    return unique[:_TOP_N]


# ── convenience extractors ───────────────────────────────────────────────────

def get_trending_sounds(niche: str) -> list:
    seen, out = set(), []
    for tr in aggregate_trends(niche):
        for s in tr.get("sounds", []):
            s = s.strip()
            if s and s.casefold() not in seen:
                seen.add(s.casefold())
                out.append(s)
    return out


def get_trending_hashtags(niche: str) -> list:
    seen, out = set(), []
    for tr in aggregate_trends(niche):
        candidates = _HASHTAG_RE.findall(tr.get("title", ""))
        candidates += [t for t in tr.get("tags", []) if t.startswith("#")]
        for h in candidates:
            k = h.casefold()
            if k not in seen:
                seen.add(k)
                out.append(h)
    return out


if __name__ == "__main__":
    for n in ("podcast", "comedy", "gaming"):
        rows = aggregate_trends(n)
        print("[{}] {} trends | sounds={} | hashtags={}".format(
            n, len(rows), get_trending_sounds(n)[:3], get_trending_hashtags(n)[:5]))
