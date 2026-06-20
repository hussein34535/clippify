import os
import sys
import time
import subprocess
import urllib.request


def wait_for_backend(url: str, timeout: int = 15) -> bool:
    for _ in range(timeout * 2):
        try:
            urllib.request.urlopen(url, timeout=2)
            return True
        except Exception:
            time.sleep(0.5)
    return False


def main():
    root_dir = os.path.dirname(os.path.abspath(__file__))
    flutter_dir = os.path.join(root_dir, "flutter_client")

    # 1. Start Python backend
    print("Starting FastAPI backend on port 8000...")
    api_path = os.path.join(root_dir, "api.py")
    backend_proc = subprocess.Popen(
        [sys.executable, api_path],
        cwd=root_dir,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    # Wait for backend to be ready
    if wait_for_backend("http://localhost:8000/docs"):
        print("Backend ready!")
    else:
        print("Warning: Backend may not be fully up yet.")

    # 2. Launch Flutter Desktop
    print("Launching Flutter desktop app...")
    try:
        subprocess.run(
            ["flutter", "run", "-d", "windows"],
            cwd=flutter_dir,
            shell=True,
        )
    except KeyboardInterrupt:
        pass
    finally:
        backend_proc.terminate()
        try:
            backend_proc.wait(timeout=5)
        except Exception:
            backend_proc.kill()


if __name__ == "__main__":
    main()
