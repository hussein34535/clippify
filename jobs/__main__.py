"""
python -m jobs — worker entrypoint.

REDIS_URL set  -> runs an RQ worker on queue "clippify".
                  (GPU variant later: swap the Dockerfile.worker base image to
                   an nvidia/cuda tag and keep this command unchanged.)
REDIS_URL unset-> nothing to do: fallback mode runs tasks in-process.
"""

import os
import sys


def main() -> int:
    redis_url = os.environ.get("REDIS_URL", "").strip()
    if not redis_url:
        print("[jobs] REDIS_URL not set -> ThreadPool fallback mode; no worker process needed.")
        return 0

    try:
        from redis import Redis
        from rq import Worker
    except ImportError as exc:
        print(f"[jobs] missing dependency for worker mode: {exc}\n"
              f"       run: pip install redis rq", file=sys.stderr)
        return 1

    queues = [os.environ.get("RQ_QUEUE", "clippify")]
    worker = Worker(queues, connection=Redis.from_url(redis_url))
    print(f"[jobs] RQ worker started: queues={queues} url={redis_url}")
    worker.work(with_scheduler=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
