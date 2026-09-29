<!-- ═══════════════════════════════════════════════════════════════
     LOGO PLACEHOLDER — put your logo at docs/assets/logo.png then:
     <p align="center"><img src="docs/assets/logo.png" width="180" alt="Clippify"/></p>
     BANNER PLACEHOLDER — docs/assets/banner.png (1500×500 recommended)
     ═══════════════════════════════════════════════════════════════ -->

# ✂️ Clippify

> **AI-powered video editor that turns long footage into viral short-form clips — a full NLE in Flutter, driven by a Rust engine.**
> محرر فيديو مدعوم بالذكاء الاصطناعي يحوّل الفيديوهات الطويلة إلى مقاطع قصيرة جاهزة للانتشار — NLE كامل بـ Flutter ومحرك Rust.

[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-stable-DEA584?logo=rust&logoColor=white)](https://www.rust-lang.org)
[![FFmpeg](https://img.shields.io/badge/FFmpeg-media%20engine-007808?logo=ffmpeg&logoColor=white)](https://ffmpeg.org)
[![Riverpod](https://img.shields.io/badge/State-Riverpod%202-2C5E92)](https://riverpod.dev)
[![Axum](https://img.shields.io/badge/API-Axum%200.7-E43717)](https://github.com/tokio-rs/axum)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](#-license)

---

## 📖 Table of Contents

- [Why Clippify?](#-why-clippify)
- [Features](#-features)
- [Architecture](#️-architecture)
- [Quick Start](#-quick-start)
- [Documentation](#-documentation)
- [Screenshots](#-screenshots)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Why Clippify?

CapCut-level editing experience meets agentic AI. Drop in a podcast, a gameplay session,
or any long video — Clippify's **Rust director brain** understands the content, picks the
best moments, scores them like a top short-form editor, and hands you ready-to-publish
clips on a full professional timeline you can fine-tune frame by frame.

**Zero-bill AI:** a cascade of free providers (Gemini Free → Groq Free → Ollama Local)
means no mandatory subscription. Your keys stay encrypted on your machine.

## ✨ Features

### 🤖 Agentic Auto-Edit
- 🧠 **AI Director** — turns transcripts into ordered clip plans with reasoning
- ⚖️ **AI Critic** — every plan scored across 5 structural checks (hook strength, pacing…), threshold-gated
- 📝 **Local Whisper ASR** — word-level transcription via whisper.cpp, fully offline
- 📊 **Narrative parser** — story beats, jokes, tension points extracted automatically
- 🎨 **Style DNA + Palette engine** — learns editing style & dominant colors per project
- 🔥 **Trend engine** — niche hashtags & sounds suggestions

### 🎬 Professional NLE Timeline
- 🎞️ Multi-track editing: video / audio / overlay / subtitle / text tracks
- ✂️ Drag, resize, snap-to-playhead & snap-to-clips, zoom up to **500x**
- ↩️ Undo/Redo (Command Pattern), autosave every 5 minutes
- 🧲 Magnetic playhead with zero-rebuild scrubbing (60fps CustomPaint)

### 🎨 Color, Motion & Effects
- 🌈 Pro color wheels + 8 grading presets
- 🎥 Motion recipes: Ken Burns, zoom punch, shake, glitch, whip pan
- 💫 GPU particle & shape systems, custom shader pipeline
- 🔊 Audio mixer, EQ (bass/mid/treble), automation, procedural SFX forge

### 🛠️ Editor Power Tools
- ⌨️ Command palette (`Ctrl+K`) + full keyboard shortcuts system
- 🎯 Keyframe curve editor & speed ramping
- 📹 Multicam support & motion tracking
- 🧩 Plugin system + macro recorder
- 🌐 Full i18n (English / العربية) with Cairo & Rubik typography
- 📱 Responsive shell — desktop & mobile layouts from one codebase

### 🚀 Export & Deployment Modes
- 📦 Batch export pipeline with presets (TikTok / Reels / YouTube)
- 🖥️ **Standalone mode** — bundled Rust engine + FFmpeg, works fully offline
- ☁️ **Cloud mode** — FastAPI + Redis + Postgres workers, S3/R2 storage, Stripe quotas

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  Flutter Client (UI Layer)                   │
│   Timeline · Player(media_kit) · Inspector · AI Wizard       │
│   Library · Audio Mixer · Export Pipeline · Command Palette  │
│                                                              │
│        BackendService ──► local (Windows) | cloud            │
│        RustEngine bridge      FFmpegService      dio API     │
└───────────────┬─────────────────────────────┬────────────────┘
                │ HTTP :8000 / WebSocket      │ Process.run (JSON)
┌───────────────▼─────────────────────────────▼────────────────┐
│                 Clippify Engine (Rust + Axum)                │
│  /auto-edit  /auth(JWT)  /media  /providers  /settings       │
│                                                              │
│  director ──► critic(score≥0.6) ──► render (segment-parallel)│
│  llm cascade: Gemini Free → Groq Free → Ollama Local         │
│  narrative · style_dna · palette · sound_forge · fair_queue  │
└───────────────┬──────────────────────────────────────────────┘
                │ subprocess / pipes
┌───────────────▼──────────────────────────────────────────────┐
│        FFmpeg / FFprobe        whisper.cpp (optional ASR)    │
└──────────────────────────────────────────────────────────────┘
```

📄 Deep dive: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (عربي)

## 🚀 Quick Start

### 🇸🇦 بالعربية — 3 خطوات

1. **دبل-كليك على `run.bat`** — سيكتشف بايثون المشروع الصحيح تلقائياً، يشغّل سيرفر الـ API، ثم يفتح واجهة Flutter Desktop لوحدها.
   - بديل أنيق بدون نافذة سوداء: دبل-كليك على **`start_clippify.vbs`** (السجل يُكتب في `clippify_run.log` بجذر المشروع).
2. **أول مرة فقط:** ستظهر شاشة ترحيب بثلاث خطوات — اضغط **"ابدأ الآن"**.
3. **استورد فيديو** من مكتبة الوسائط → اضغط زر **Auto-Edit** ليختار الذكاء الاصطناعي أفضل اللقطات → عدّل في التايملاين كما تريد → **Export**.

> 💡 المشغّل الموحّد `run_clippify.py` يقبل وسائط مفيدة:
> `--dry-run` (فحص البيئة وطباعة الخطة بدون تشغيل) · `--backend-only` (باك إند فقط).
> للتطوير على الواجهة مباشرة: `cd flutter_client && flutter run -d windows`.

### 🇬🇧 English — 3 steps

1. **Double-click `run.bat`** — it auto-detects the right project Python, starts the FastAPI server, then launches the Flutter desktop UI.
   - Console-free alternative: double-click **`start_clippify.vbs`** (logs go to `clippify_run.log`).
2. **First launch only:** a 3-step welcome screen appears — click **"Start Now"**.
3. **Import a video** → hit **Auto-Edit** → fine-tune the timeline → **Export**.

**Prerequisites | المتطلبات:** Windows 10/11 + Python 3.10+ مع `pip install -r requirements.txt`.
لو `flutter` موجود على PATH سيُشغَّل `flutter run`؛ وإلا يُشغّل المشغّل نسخة مبنية جاهزة من
`flutter_client/build/windows/x64/runner/` إن وُجدت. (للمطورين: محرك Rust اختياري عبر `cd engine && cargo build --release` — راجع [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)).

### 🔧 Troubleshooting | استكشاف الأخطاء

| المشكلة | الحل |
|---------|------|
| **"flutter مش موجود"** | طبيعي للمستخدم العادي — المشغّل يشغّل النسخة المبنية تلقائياً. للتطوير: ثبت Flutter SDK وأضفه إلى PATH، أو ابنِ مرة واحدة: `cd flutter_client && flutter build windows --release` |
| **"البورت 8000 مشغول"** | أغلق البرنامج الآخر الذي يستخدم المنفذ، أو استخدم منفذاً بديلاً: `set CLIPPIFY_PORT=8001` (cmd) / `$env:CLIPPIFY_PORT=8001` (PowerShell) ثم عدّل `API_BASE_URL` في `flutter_client/.env` ليطابقه |
| **"المتطلبات ناقصة"** (لم يُعثر على بايثون فيه fastapi) | شغّل `pip install -r requirements.txt` ببايثون المشروع، أو اضبط `CLIPPIFY_PYTHON` على مساره مباشرة. للفحص بدون تشغيل: `python run_clippify.py --dry-run` |

### ⚙️ Environment Variables | متغيرات البيئة

| Variable | Default | الوصف |
|----------|---------|-------|
| `CLIPPIFY_PYTHON` | — | مسار بايثون الباك إند — يُجرَّب أولاً قبل الاكتشاف التلقائي (run_clippify.py) |
| `CLIPPIFY_HOST` | `127.0.0.1` | عنوان استماع الـ API |
| `CLIPPIFY_PORT` | `8000` | منفذ الـ API |
| `CLIPPIFY_CORS_ORIGINS` | — | أصول CORS إضافية مفصولة بفواصل (سطح المكتب لا يحتاج CORS) |
| `CLIPPIFY_DATA_DIRS` | — | مجلدات بيانات إضافية مسموح للباك إند العمل فيها (مفصولة بفواصل؛ الافتراضي: `projects/`, `output/`, `exports/`, `temp/`) |
| `CLIPPIFY_NO_FLUTTER` | — | `1` = باك إند فقط بدون واجهة — مفيد للاختبار وCI |
| `CLIPPIFY_FRONTEND` | — | `flutter` \| `exe` \| `none` — تجاوز قرار تشغيل الواجهة |

<details>
<summary><b>☁️ Cloud stack (optional)</b></summary>

```bash
cp .env.example .env   # fill JWT_SECRET, GEMMA_API_KEY, …
docker compose up --build
# API on :8000 · worker · redis · postgres
```
</details>

## 📚 Documentation

| Doc | Content |
|-----|---------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | المعمارية الكاملة — diagram، الوحدات الـ17 لمحرك Rust، تدفق البيانات، مبررات التقنيات |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | دليل النشر — Windows bundling، متاجر Android/iOS، Docker + Oracle Free Tier |
| [`docs/CONTRACTS.md`](docs/CONTRACTS.md) | عقود الـ API بين الطبقات |
| [`.env.example`](.env.example) | مرجع متغيرات البيئة |

## 📸 Screenshots

<!-- TODO: replace with real captures -->
| Timeline | AI Auto-Edit | Color Grading |
|:---:|:---:|:---:|
| ![Timeline placeholder](docs/assets/screenshot-timeline.png) | ![Auto-edit placeholder](docs/assets/screenshot-autoedit.png) | ![Color placeholder](docs/assets/screenshot-color.png) |
| *Multi-track NLE timeline* | *Agentic clip generation* | *Pro color wheels* |

## 🤝 Contributing

Contributions are welcome! 🎉

1. **Fork & branch** — `git checkout -b feat/my-feature`
2. **Follow the conventions** — read `AGENTS.md` for architecture rules & module ownership
3. **Verify before PR** — `flutter analyze` + `flutter test` must pass (CI runs on 3 OSes)
4. **Open a Pull Request** — describe *what* changed and *why*

> Areas looking for help: mobile parity, GPU workers, more motion recipes, plugin SDK.

## 📄 License

Released under the [MIT License](LICENSE) — © 2026 ClipAI.
