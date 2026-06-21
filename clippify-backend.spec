# -*- mode: python ; coding: utf-8 -*-
# clippify-backend.spec
# PyInstaller spec for Clippify backend (FastAPI + Python ML pipeline)
# Excludes ALL dead Tkinter/CustomTkinter code
# Output: dist/clippify-backend.exe

import sys
import os
from PyInstaller.utils.hooks import collect_data_files, collect_all, copy_metadata

block_cipher = None

# ── Collect imageio_ffmpeg binary (ffmpeg.exe bundled with the package) ────────
tmp_ret = collect_all('imageio_ffmpeg')
ffmpeg_datas = tmp_ret[0]
ffmpeg_binaries = tmp_ret[1]
ffmpeg_hiddenimports = tmp_ret[2]

# ── Collect av package (av.libs/*.dll) — needed by faster_whisper and imageio ─
av_ret = collect_all('av')
av_datas = av_ret[0]
av_binaries = av_ret[1]
av_hiddenimports = av_ret[2]

# ── Collect data files from key packages ──────────────────────────────────────
datas = []
datas += collect_data_files('google.genai')
datas += collect_data_files('faster_whisper')
datas += collect_data_files('imageio')
datas += collect_data_files('Pillow')

# ── Copy metadata for runtime introspection ───────────────────────────────────
datas += copy_metadata('imageio')
datas += copy_metadata('Pillow')
datas += copy_metadata('moviepy')
datas += copy_metadata('faster_whisper')

# ── Hidden imports: every local module + 3rd party AI libs ────────────────────
hiddenimports = [
    # Local modules (imported transitively from api.py)
    'models',
    'orchestrator',
    'editor',
    'audio',
    'audio_intelligence',
    'detector',
    'downloader',
    'campaign',
    'broll_manager',
    'ai_engine',
    'ai_director',
    'content_dna',
    'content_types',
    'nle_renderer',
    'timeline_models',
    'style_analyzer',
    'style_imitator',
    'video_analyzer',
    'viral_scorer',
    'viral_recommendations',
    'scene_describer',
    'caption_animator',
    'clipper',
    'keyframe_engine',
    'motion',
    'sounds',
    'sfx_synth',
    'silence_trimmer',
    'tracker',
    'bg_remover',
    'freesound_client',
    'resolve_exporter',
    'youtube_login',
    'uploader',
    # 3rd party
    'google.genai',
    'google.genai.types',
    'google.generativeai',
    'faster_whisper',
    'moviepy',
    'moviepy.editor',
    'pydub',
    'pydub.playback',
    'cv2',
    'numpy',
    'PIL',
    'PIL.Image',
    'requests',
    'dotenv',
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.lifespan',
    'uvicorn.lifespan.on',
    'fastapi',
    'fastapi.middleware.cors',
    'fastapi.responses',
] + ffmpeg_hiddenimports + av_hiddenimports

# ── Final assembly ────────────────────────────────────────────────────────────
a = Analysis(
    ['api.py'],
    pathex=[os.getcwd()],
    binaries=ffmpeg_binaries + av_binaries,
    datas=datas + ffmpeg_datas + av_datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Block ALL Tkinter/UI frameworks (dead code)
        'tkinter',
        'tkinterdnd2',
        'customtkinter',
        'PIL.ImageTk',
        'PIL.ImageDraw',
        # Unused heavy frameworks
        'matplotlib',
        'pandas',
        'scipy',
        'sympy',
        'pytest',
        'IPython',
    ],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='clippify-backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
