# clippify — Professional NLE Desktop Editor

**Flutter Desktop video editor** — professional-grade, AI-powered.
Built with Flutter 3.44 + FastAPI backend + FFmpeg for a CapCut/Premiere Pro level editing experience.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Flutter Desktop App                 │
│  ┌─────────┐  ┌──────────┐  ┌────────────────┐ │
│  │ Timeline │  │  Player  │  │  Inspector     │ │
│  │  (NLE)   │  │ (media_kit)│  │  (AI + Effects)│ │
│  └─────────┘  └──────────┘  └────────────────┘ │
│  ┌─────────┐  ┌──────────┐  ┌────────────────┐ │
│  │ Library │  │ Subtitle │  │  Export/Render │ │
│  └─────────┘  └──────────┘  └────────────────┘ │
│         │            │             │            │
│         ▼            ▼             ▼            │
│  ┌──────────────────────────────────────────┐   │
│  │           BackendController              │   │
│  │    (Process management, health check)     │   │
│  └──────────────────────────────────────────┘   │
└──────────────────────┬──────────────────────────┘
                       │ HTTP (port 8000)
┌──────────────────────▼──────────────────────────┐
│              FastAPI Backend (api.py)             │
│  Media-info  │  Transcription  │  AI Tools      │
│  Silence     │  Copilot        │  Project I/O   │
│  Detection   │                 │  Render/Export  │
│  YouTube DL  │                 │  Settings       │
└──────────────────────────────────────────────────┘
```

### Key Technologies

| Layer | Technology |
|-------|-----------|
| UI Framework | Flutter 3.44.2 (stable, Dart 3.12.2) |
| Video Playback | media_kit (libmpv backend) |
| State Management | Riverpod 2.x |
| Backend | Python FastAPI (port 8000) |
| Media Engine | FFmpeg / FFprobe |
| AI | Google Gemma API (cloud) + faster-whisper (local) |

---

## Features

### Timeline (Full NLE)
- Multi-track video/audio/overlay/subtitle/text
- Sidebar outside scroll — fixed 110px + horizontal scroll
- Track heights: 78/58/48/38 with 4px gaps
- Grid lines (every 5s), time ruler with timecode
- Playhead (white) + Snap line (orange)
- Zoom: Ctrl+scroll / pinch / slider (1x–500x)
- Clip resize (left/right handles) + drag-to-move
- Snap-to-playhead + snap-to-clips
- Vertical scroll for tracks, auto-scroll playhead
- Undo/Redo (Command Pattern)

### Video Player
- media_kit with libmpv
- Bidirectional sync: position → playhead / playhead → seek
- Safe seek with debounce (prevents thrashing)
- Cache settings (500MB)
- Play/pause, mute, volume, timecode, seek slider
- Playhead scrubbing with zero Riverpod rebuilds

### AI & Effects
- AI Tool Palette (219 tools)
- Copilot chat
- Color Grading Panel (Color Wheel + 8 presets)
- Audio EQ (bass/mid/treble) + effects chain
- Speed ramping with keyframes
- Transitions engine
- Inspector with keyframe editor

### Media Library
- Drag & drop from library to timeline
- Thumbnails via FFmpeg
- YouTube import (dialog)
- Local file browser

### Project Management
- Save/Load projects (JSON)
- Autosave every 5 minutes (local, no API needed)
- Export modal with encoder/format/preset selection

### Additional
- Dark/Light Theme toggle
- Keyboard shortcuts system
- Toast notifications
- Resizable panels (LayoutBuilder)
- Macros (record/playback)
- Subtitle editor
- Export pipeline (batch processing)

---

## Quick Start

### Prerequisites

```bash
# Flutter 3.44+ (stable channel)
flutter --version

# FFmpeg + FFprobe
ffmpeg -version

# Python 3.9+
python --version
```

### Install & Run

```bash
# 1. Backend
pip install -r requirements.txt
python api.py &

# 2. Flutter app
cd flutter_client
flutter pub get
flutter run -d windows
```

Or run everything from Flutter: the `BackendController` automatically starts/verifies the backend.

### Build Release

```bash
cd flutter_client
flutter build windows --release
# Output: build\windows\x64\runner\Release\flutter_client.exe
```

---

## Project Structure

```
clippify/
├── api.py                          # FastAPI backend (port 8000)
├── requirements.txt                # Python dependencies
├── AGENTS.md                       # AI development guide
├── flutter_client/
│   ├── lib/
│   │   ├── main.dart               # Entry point
│   │   ├── app.dart                # MaterialApp
│   │   ├── launch/
│   │   │   └── backend_controller.dart  # Backend lifecycle
│   │   ├── core/
│   │   │   ├── api/
│   │   │   │   └── api_client.dart      # Dio HTTP client + ApiResult<T>
│   │   │   ├── models/
│   │   │   │   └── timeline_models.dart # All data models
│   │   │   ├── theme/
│   │   │   │   └── app_theme.dart       # Dark/Light theme
│   │   │   └── cache/
│   │   │       └── cache_manager.dart   # Disk cache
│   │   ├── features/
│   │   │   ├── timeline/   # providers/, widgets/, painters/
│   │   │   ├── player/     # Video player widget
│   │   │   ├── library/    # Media library
│   │   │   ├── inspector/  # Inspector dashboard
│   │   │   ├── home/       # Main screen + layout
│   │   │   ├── export/     # Export pipeline
│   │   │   ├── subtitle/   # Subtitle editor
│   │   │   ├── ai/         # AI tools + copilot
│   │   │   └── audio/      # Audio effects engine
│   │   └── shared/         # Macros, keyboard shortcuts, utils
│   ├── test/
│   │   └── ...             # 55+ unit tests
│   └── pubspec.yaml
└── ...
```

---

## Development Status

| Metric | Current |
|--------|---------|
| `flutter analyze` | 0 errors (warnings suppressed) |
| `flutter test` | 46/46 Flutter + 16/16 Python passed |
| `flutter build windows --release` | ✅ Success |
| Flutter SDK | 3.44.2 (stable) |
| Backend | FastAPI on port 8000 |

---

## License

MIT
