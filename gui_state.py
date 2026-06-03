import os
import json

PREFS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_prefs.json")

DEFAULT_PREFS = {
    "n_clips": 5,
    "duration": 60,
    "ai_mode": True,
    "auto_director": True,
    "trim_silence": True,
    "scale_punches": True,
    "hook_mode": True,
    "compile_clips": True,
    "translate_to_arabic": False,
    "gemma_multimodal": False,
    "auto_broll": False,
    "use_scene_captioning": False,
    "use_local_captioning": True,
    "subtitle_style": "TikTok Yellow",
    "font_name": "Impact",
    "export_quality": "High",
    "sfx_mode": "normal",
    "caption_animation_mode": "auto",
    "framing_strategy": "speaker_tracking",
    "whisper_model": "tiny",
    "output_dir": "./output",
    "temp_folder": "./temp"
}

def load_ui_prefs():
    """Load saved UI settings from ui_prefs.json with default fallbacks."""
    prefs = DEFAULT_PREFS.copy()
    if os.path.exists(PREFS_PATH):
        try:
            with open(PREFS_PATH, "r", encoding="utf-8") as f:
                saved = json.load(f)
            for k, v in saved.items():
                prefs[k] = v
            print(f"[Prefs] Loaded settings from {PREFS_PATH}")
        except Exception as e:
            print(f"[Prefs] Failed to load ui_prefs.json: {e}")
    return prefs

def save_ui_prefs(prefs):
    """Save current UI state to ui_prefs.json."""
    try:
        with open(PREFS_PATH, "w", encoding="utf-8") as f:
            json.dump(prefs, f, ensure_ascii=False, indent=2)
        print(f"[Prefs] Settings saved.")
        return True
    except Exception as e:
        print(f"[Prefs] Failed to save ui_prefs.json: {e}")
        return False
