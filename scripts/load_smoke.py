#!/usr/bin/env python3
"""
load_smoke.py — dependency-free load smoke test for the Clippify backend.

Stdlib only (urllib + threading). Assumes a server is already running
(default http://localhost:8000); it does NOT start one.

Usage:
    python scripts/load_smoke.py                       # 30 threads x GET /api/health
    python scripts/load_smoke.py --url http://host:8000 --n 50 --rounds 3 --path /api/health

Prints p50/p95 latency percentiles and the error count.
Exit code: 0 = all OK (or graceful skip when server unreachable), 1 = errors occurred.
"""

import argparse
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request


def _hit_once(url: str, timeout: float):
    """One GET. Returns (latency_ms, error_str_or_None)."""
    start = time.perf_counter()
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            resp.read()
        latency_ms = (time.perf_counter() - start) * 1000.0
        return latency_ms, None
    except urllib.error.HTTPError as exc:
        latency_ms = (time.perf_counter() - start) * 1000.0
        try:
            exc.read()
        except Exception:
            pass
        return latency_ms, f"HTTP {exc.code}"
    except Exception as exc:  # URLError, socket.timeout, ConnectionError, ...
        return (time.perf_counter() - start) * 1000.0, f"{type(exc).__name__}: {exc}"


def _pctl(sorted_vals, pct: float) -> float:
    if not sorted_vals:
        return float("nan")
    k = min(len(sorted_vals) - 1, max(0, int(round(pct / 100.0 * (len(sorted_vals) - 1)))))
    return sorted_vals[k]


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Dependency-free load smoke test (GET requests, N threads)."
    )
    parser.add_argument("--url", default="http://localhost:8000",
                        help="base URL of the running server (default: %(default)s)")
    parser.add_argument("--path", default="/api/health",
                        help="endpoint path to hammer (default: %(default)s)")
    parser.add_argument("--n", type=int, default=30,
                        help="number of concurrent threads (default: %(default)s)")
    parser.add_argument("--rounds", type=int, default=1,
                        help="requests per thread (default: %(default)s)")
    parser.add_argument("--timeout", type=float, default=5.0,
                        help="per-request timeout in seconds (default: %(default)s)")
    args = parser.parse_args(argv)

    url = args.url.rstrip("/") + args.path
    n = max(1, args.n)
    rounds = max(1, args.rounds)

    # ── Preflight: graceful skip when nothing is listening ────────────────
    lat0, err0 = _hit_once(url, timeout=args.timeout)
    if err0 and ("Connection" in err0 or "refused" in err0.lower()
                 or "NameResolution" in err0 or "getaddrinfo" in err0.lower()):
        print(f"[skip] No server reachable at {url} ({err0}).")
        print("       Start it first, e.g.:  python api.py   then re-run this script.")
        return 0

    latencies = []
    errors = []
    lock = threading.Lock()

    def worker():
        for _ in range(rounds):
            lat, err = _hit_once(url, timeout=args.timeout)
            with lock:
                latencies.append(lat)
                if err:
                    errors.append(err)

    threads = [threading.Thread(target=worker, daemon=True) for _ in range(n)]
    t_start = time.perf_counter()
    for t in threads:
        t.start()
    for t in threads:
        t.join(rounds * args.timeout + 10.0)
    wall_ms = (time.perf_counter() - t_start) * 1000.0

    ordered = sorted(latencies)

    print("=" * 56)
    print(f"Load smoke: {url}")
    print(f"Threads: {n}  x Rounds: {rounds}  ->  requests sent: {len(latencies)}")
    print(f"Wall time: {wall_ms:.0f} ms")
    print("-" * 56)
    if ordered:
        print(f"min : {ordered[0]:8.1f} ms")
        print(f"p50 : {_pctl(ordered, 50):8.1f} ms")
        print(f"p95 : {_pctl(ordered, 95):8.1f} ms")
        print(f"max : {ordered[-1]:8.1f} ms")
        print(f"mean: {statistics.fmean(ordered):8.1f} ms")
    print("-" * 56)
    print(f"errors: {len(errors)} / {len(latencies)}")
    if errors:
        uniq = {}
        for e in errors:
            uniq[e] = uniq.get(e, 0) + 1
        for msg, cnt in sorted(uniq.items(), key=lambda kv: -kv[1]):
            print(f"  [{cnt:>4}x] {msg}")
    print("=" * 56)

    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
