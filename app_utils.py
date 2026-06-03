# -*- coding: utf-8 -*-
"""
app_utils.py — Helper functions and system utilities for ClipAI App.
"""

import os
import sys
import subprocess

# ── Optional drag-and-drop support ─────────────────────────────────────────
try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    DND_AVAILABLE = True
except Exception:
    DND_AVAILABLE = False

# ── Optional pyperclip (clipboard) ─────────────────────────────────────────
try:
    import pyperclip
    PYPERCLIP_OK = True
except Exception:
    PYPERCLIP_OK = False


def open_folder(path: str):
    """Open a folder in the native system file explorer."""
    abs_path = os.path.abspath(path)
    try:
        if sys.platform == "win32":
            os.startfile(abs_path)
        elif sys.platform == "darwin":
            subprocess.run(["open", abs_path], check=False)
        else:
            subprocess.run(["xdg-open", abs_path], check=False)
    except Exception as e:
        print(f"Could not open folder: {e}")


def fmt_time(sec: float) -> str:
    """Format seconds into hh:mm:ss string."""
    sec = int(sec)
    return f"{sec // 3600:02d}:{(sec % 3600) // 60:02d}:{sec % 60:02d}"
