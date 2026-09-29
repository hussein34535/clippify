# Clippify — المعمارية الكاملة / Architecture

> **Clippify** — محرر فيديو احترافي مدعوم بالذكاء الاصطناعي لإنشاء المقاطع القصيرة (Shorts/Reels/TikTok).
> هذا المستند يشرح المعمارية الكاملة للنظام: الطبقات، الوحدات، تدفق البيانات، ومبررات اختيار التقنيات.
>
> ملفات ذات صلة: [`DEPLOYMENT.md`](./DEPLOYMENT.md) · [`CONTRACTS.md`](./CONTRACTS.md)

---

## Table of Contents

- [System Diagram](#system-diagram)
- [Modules Overview](#modules-overview)
  - [Rust Engine Modules (17)](#rust-engine-modules-17)
  - [Flutter Feature Modules (15+)](#flutter-feature-modules-15)
- [Data Flow](#data-flow)
- [Technology Choices & Rationale](#technology-choices--rationale)
- [Standalone vs Backend Mode](#standalone-vs-backend-mode)

---

## System Diagram

النظام مبني على ثلاث طبقات رئيسية: واجهة Flutter، محرك معالجة Rust، وأدوات الوسائط FFmpeg.

```
┌───────────────────────────────────────────────────────────────────┐
│                     Flutter Client (UI Layer)                     │
│                                                                   │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌─────────────────────┐ │
│  │ Timeline │ │  Player  │ │ Inspector │ │ AI Wizard + Copilot │ │
│  │  (NLE)   │ │(media_kit│ │ (Color/   │ │  (Auto-Edit Flow)   │ │
│  │          │ │ /libmpv) │ │ Keyframes)│ │                     │ │
│  └──────────┘ └──────────┘ └───────────┘ └─────────────────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌───────────┐ ┌─────────────────────┐ │
│  │ Library  │ │  Audio   │ │  Export   │ │  Shell + Layout     │ │
│  │ (Media)  │ │  Mixer   │ │ Pipeline  │ │  (Desktop/Mobile)   │ │
│  └──────────┘ └──────────┘ └───────────┘ └─────────────────────┘ │
│                        │ Riverpod State                           │
│  ┌─────────────────────▼────────────────────────────────────────┐ │
│  │              Core Services (Dart Bridge Layer)               │ │
│  │  BackendService (local/cloud) · ApiClient (dio) · AuthStore  │ │
│  │  RustEngine (CLI bridge)      · FFmpegService · CacheManager │ │
│  └───────────┬──────────────────────────────┬───────────────────┘ │
└──────────────┼──────────────────────────────┼─────────────────────┘
               │ HTTP :8000                   │ Process.run (JSON stdout)
┌──────────────▼──────────────────────────────▼─────────────────────┐
│                    Clippify Engine (Rust)                         │
│                                                                   │
│  ┌──────────────────────── Axum HTTP API ───────────────────────┐ │
│  │  /auth   /auto-edit (+WS progress)   /media   /providers     │ │
│  │  /settings   /system   /health                               │ │
│  └──────────────────────────────┬───────────────────────────────┘ │
│                                 │                                 │
│  ┌────────────┐  ┌─────────────▼────────────┐  ┌───────────────┐ │
│  │ director   │  │    auto_edit pipeline    │  │ critic        │ │
│  │ (LLM brain)│  │ probe→silence→ASR→plan→  │  │ (score ≥0.6)  │ │
│  └────────────┘  │ review→render            │  └───────────────┘ │
│  ┌────────────┐  └─────────────┬────────────┘  ┌───────────────┐ │
│  │ llm cascade│                │               │ narrative     │ │
│  │Gemini→Groq │        ┌───────▼───────┐       │ scenario      │ │
│  │  →Ollama   │        │ render (seg-  │       │ style_dna     │ │
│  └────────────┘        │ parallel+HW)  │       │ palette/trend │ │
│  ┌────────────┐        └───────┬───────┘       │ sound_forge   │ │
│  │ db(rusqlite│                │               │ fair_queue    │ │
│  │ JWT/bcrypt)│                │               │ motion recipes│ │
│  └────────────┘                │               └───────────────┘ │
└────────────────────────────────┼──────────────────────────────────┘
                                 │ subprocess (filters, pipes)
┌────────────────────────────────▼──────────────────────────────────┐
│                       Media Toolchain                             │
│   FFmpeg / FFprobe (transcode, filters, concat, thumbs, audio)    │
│   whisper.cpp (اختياري — تحويل الكلام إلى نص محلياً بدون إنترنت)  │
│   LLM Providers (Gemini Free → Groq Free → Ollama Local)          │
└───────────────────────────────────────────────────────────────────┘
```

**ملاحظات على الرسم:**

- **Flutter ↔ Rust:** التواصل عبر HTTP (Axum server على المنفذ 8000) أو عبر استدعاء CLI مباشر (`Process.run`) حيث كل أمر يطبع JSON واحداً على stdout.
- **Rust ↔ FFmpeg:** المحرك يغلّف ثنائي FFmpeg عبر أوامر فرعية وأنابيب raw video (مثلاً استخراج الألوان المهيمنة في `palette.rs`).
- **التقدم الحي:** أثناء الـ Auto-Edit يتم بث التقدم عبر WebSocket على `/ws/progress/:id`.

---

## Modules Overview

### Rust Engine Modules (17)

المحرك موجود في `engine/src/` — خادم HTTP كامل + CLI، بديل كامل لباك-إند Python القديم.

| # | Module | الوصف |
|---|--------|-------|
| 1 | `main.rs` | نقطة الدخول: ربط كل الوحدات + CLI (clap): `duration`, `silences`, `thumbnails`, `ask`, `render`, `transcribe`, `serve` (الافتراضي). |
| 2 | `types.rs` | أنواع البيانات المشتركة: `ClipSpec`, `RenderRequest`, `Silence`, `TranscribedSegment`, `LlmResponse`... |
| 3 | `media.rs` | غلاف FFmpeg شامل: فحص المدة، كشف الصمت، استخراج المصغرات، عمليات الوسائط كلها. |
| 4 | `render.rs` | خط إنتاج تصيير متوازٍ بالتقسيم لمقاطع (segments) مع تسريع عتادي ثم دمج (concatenate). |
| 5 | `director.rs` | العقل الإداري الوكيل (Agentic Brain): يحوّل ملخص النص إلى `DirectorPlan` — مقاطع مرتبة مع مبررات، عبر LLM مع fallback إرشادي pure-Rust. |
| 6 | `critic.rs` | مراجِع الخطط: يقيّم `DirectorPlan` كأنه أفضل محرر Short-form عبر 5 فحوص بنيوية (قوة الخطاف، الإيقاع...) بمتوسط من 0 إلى 1 (عتبة القبول 0.6). |
| 7 | `narrative.rs` | محلل السرد الإرشادي: يستخرج `StoryBeat`, `Joke`, `TensionPoint`, `KeyMoment` من كلمات النص المتزامنة. |
| 8 | `scenario.rs` | ملفات سيناريو (`ScenarioProfile`) لكل نوع محتوى (بودكاست، قيمينق...) مع إمكانية تحميل ملفات YAML خارجية. |
| 9 | `style_dna.rs` | بصمة الأسلوب: يستخرج DNA أسلوب المونتاج من النص والبيانات الوصفية ويحوّله إلى prompt ويحفظ/يحمّل باسم. |
| 10 | `palette.rs` | محرك الألوان: استخراج الألوان المهيمنة (raw RGB24 عبر أنبوب FFmpeg) وتوليد لوحة ألوان حسب المزاج. |
| 11 | `motion.rs` | وصفات حركة FFmpeg جاهزة: zoom, shake, glitch, whip pan, Ken Burns — قوالب فلترات قابلة للتركيب والتسلسل. |
| 12 | `sound_forge.rs` | مُخلّق مؤثرات صوتية إجرائي (DSP بـ Rust خالص): sweeps, risers, impacts, طقم درامز مُخلَّق — بدون أي crates صوتية خارجية. |
| 13 | `trend.rs` | محرك الترندات المحلي: hashtags وأصوات لكل نيتش (niche) مع تخزين محلي JSON. |
| 14 | `fair_queue.rs` | طابور قبول بعدالة الاستخدام: حصة يومية لكل هوية (user-id/IP) على SQLite خفيف لحماية المجاني المشترك من الإغراق. |
| 15 | `llm.rs` | شلال LLM بصفر فواتير: **Gemini Free → Groq Free → Ollama Local** مع BYOK مشفّر. |
| 16 | `transcribe.rs` | تفريغ صوتي عبر whisper.cpp إن وُجد؛ وإلا fallback إلى `/api/transcribe` في الباك-إند. |
| 17 | `db.rs` | طبقة SQLite (`rusqlite` bundled) للمستخدمين والجلسات والحالة العامة للمحرك. |

**طبقة `api/` (6 راوترات فوق المحرك):**

| Router | المسؤولية |
|--------|-----------|
| `api/auth.rs` | تسجيل/دخول JWT + bcrypt. |
| `api/auto_edit.rs` | منسّق خط Auto-Edit الكامل: `POST /auto-edit` (probe → silences → ASR → director → critic → render)، حالة الجلسات في الذاكرة، تقدم عبر `GET /auto-edit/status/:id` + WebSocket `/ws/progress/:id`. |
| `api/media_endpoints.rs` | رفع/استيراد الوسائط والعمليات عليها. |
| `api/providers.rs` | إدارة مزودي LLM (BYOK، الحصص، ledger الاستخدام). |
| `api/settings.rs` | إعدادات التطبيق والمحرر. |
| `api/system.rs` | فحص الصحة (`/health`) ومعلومات النظام. |

### Flutter Feature Modules (15+)

عميل Flutter في `flutter_client/lib/` — معمارية feature-first مع Riverpod.

| # | Feature | الوصف |
|---|---------|-------|
| 1 | `timeline` | محرك الـ NLE الكامل: مسارات متعددة (فيديو/صوت/overlay/ترجمات/نص)، snap، undo/redo بنمط Command، zoom حتى 500x، رسوم CustomPaint. |
| 2 | `player` | مشغّل فيديو media_kit (libmpv) مع مزامنة ثنائية الاتجاه playhead↔position وsafe-seek بـ debounce. |
| 3 | `inspector` | لوحة الخصائص: محرر keyframes، speed ramps، تدرج ألوان، محرر ترجمات، لوحة أدوات AI. |
| 4 | `ai` | أدوات الذكاء الاصطناعي + Copilot Chat داخل المحرر. |
| 5 | `wizard` | معالج Auto-Edit: حوار البدء + شاشة تقدم مباشرة لخط المعالجة الآلي. |
| 6 | `results` | شاشة نتائج Auto-Edit وجسر نقل النتائج إلى الـ timeline (`timeline_bridge`). |
| 7 | `export` | خط إنتاج التصدير: presets، معالجة دفعية، اختيار encoder/format. |
| 8 | `library` | مكتبة الوسائط: drag & drop إلى الـ timeline، مصغرات FFmpeg، استيراد يوتيوب. |
| 9 | `audio` | محرك الصوت: mixer، automation، EQ (bass/mid/treble)، سلسلة مؤثرات. |
| 10 | `color` | تدرج ألوان احترافي: عجلات ألوان (Pro Color Wheels) + 8 presets جاهزة. |
| 11 | `motion` | نظام الحركة: جزيئات (particles) وأشكال (shapes) قابلة للتوليد. |
| 12 | `keyframes` | محرر منحنيات (Curve Editor) واستيفاء keyframes. |
| 13 | `text` | محرر النصوص والعناوين داخل الفيديو. |
| 14 | `multicam` | نظام تعدد الكاميرات (Multicam). |
| 15 | `tracking` | تتبع الحركة (Motion Tracker). |
| 16 | `capture` | مجموعة التسجيل/الاقتصاص المباشر. |
| 17 | `cloud` | التعاون السحابي (Collaboration). |
| 18 | `auth` | تسجيل الدخول والملف الشخصي. |
| 19 | `command_palette` | لوحة أوامر شاملة (Ctrl+K) مع registry قابل للتوسعة. |
| 20 | `onboarding` | جولة أول تشغيل + بوابة first-run. |
| 21 | `shell` | هيكل التنقل + كشف الجهاز (Desktop/Mobile responsive shell). |
| 22 | `mobile` | صفحات مخصصة للموبايل: wizard/library/results نسخة موبايل. |
| 23 | `layout` | الهيكل العام: header/footer، نوافذ التصدير والإعدادات والحساب. |
| 24 | `proxy` | إدارة Proxy Media للمقاطع الثقيلة (تصيير سلس). |
| 25 | `home` | الشاشة الرئيسية. |
| 26 | `ui` | مكوّنات UI احترافية وحواف (professional_ui / edge_ui). |

**الطبقات المساندة (`core/` + `shared/`):**

- `core/backend/` — عقود `BackendService` (محلي/سحابي)، `authed_dio` مع تجديد التوكن، `auto_edit_api`.
- `core/native/` — جسر `RustEngine` (CLI) و`FFmpegService`.
- `core/api/` — `api_client.dart` (dio + نمط `ApiResult<T>`).
- `core/rendering/` — نظام Shaders وأدوات color matrix للمعاينة.
- `core/plugins/` — نظام إضافات (Plugin System).
- `core/cache/` — مدير كاش قرصي (500MB افتراضياً).
- `shared/l10n/` — تعريب كامل (عربي/إنجليزي) بخطوط Cairo وRubik.
- `shared/widgets/` — shortcuts، toasts، panels قابلة للتحجيم، waveform، gestures متقدمة.

---

## Data Flow

خط البيانات الرئيسي: **Import → Understand → Direct → Preview → Render → Export**

```
 Import          Understand           Direct             Preview          Render           Export
┌────────┐    ┌───────────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐   ┌──────────┐
│ File   │    │ probe duration│   │ director.rs  │   │ Results UI │   │ render.rs  │   │ Export   │
│ Picker │───▶│ detect silence│──▶│ LLM cascade  │──▶│ timeline_  │──▶│ segment-   │──▶│ Pipeline │
│ YouTube│    │ thumbnails    │   │ narrative +  │   │ bridge →   │   │ parallel   │   │ presets  │
│ Capture│    │ whisper ASR   │   │ style_dna +  │   │ NLE editor │   │ HW accel + │   │ batch +  │
│        │    │ (whisper.cpp) │   │ scenario +   │   │ (تعديل يدوي│   │ concat +   │   │ share/   │
│        │    │               │   │ palette      │   │ قبل القبول)│   │ SFX forge  │   │ save     │
└────────┘    └───────────────┘   │ critic ≥0.6  │   └────────────┘   └────────────┘   └──────────┘
                                  └──────────────┘
                                       ▲    │ WebSocket /ws/progress/:id (تقدم حي)
                                       └────┴── fair_queue (حماية الحصص المجانية)
```

### شرح المراحل

1. **Import (الاستيراد)** — من مكتبة الوسائط: ملفات محلية (file_picker)، يوتيوب، أو تسجيل مباشر (capture suite). تُنشأ مصغرات عبر FFmpeg فوراً.
2. **Understand (الفهم)** — المحرك يحلل المادة الخام: مدة الفيديو، لحظات الصمت (noise floor −30dB افتراضياً)، مصغرات، وتفريغ نصي كلمة-بكلمة عبر whisper.cpp مع timestamps.
3. **Direct (الإخراج الذكي)** — مرحلة الوكلاء: `narrative.rs` يستخرج بنية القصة، `style_dna.rs` يحدد الأسلوب، `llm.rs` يستدعي الشلال (Gemini→Groq→Ollama) عبر `director.rs` لبناء `DirectorPlan`، ثم `critic.rs` يقيّم الخطة — أي خطة تحت 0.6 تُرفض ويُعاد التوليد. `fair_queue.rs` يحمي الحصة اليومية.
4. **Preview (المعاينة)** — النتائج تظهر في شاشة Auto-Edit Results؛ زر "أرسل إلى الـ timeline" ينقل المقاطع عبر `timeline_bridge` إلى محرر NLE الكامل حيث يمكن للمستخدم التعديل يدوياً (keyframes، ألوان، صوت، نص...).
5. **Render (التصيير)** — `render.rs` يقسّم الخط الزمني إلى segments يُصيَّروا بالتوازي مع تسريع عتادي، مع وصفات `motion.rs` ومؤثرات `sound_forge.rs`، ثم يُدمجون.
6. **Export (التصدير)** — خط التصدير في Flutter يطبق presets (TikTok/Reels/YouTube...) ويكتب الملف النهائي عبر FFmpeg مع خيارات مشاركة/حفظ.

---

## Technology Choices & Rationale

### لماذا Flutter؟

| السبب | التفصيل |
|-------|---------|
| **قاعدة كود واحدة لـ 6 منصات** | Windows/Linux/macOS/Android/iOS من نفس الكود — حاسم لأن Clippify محرر دسكتب أولاً + موبايل. |
| **CustomPaint للأداء** | الـ timeline (مسارات، موجات صوتية، playhead) مرسوم بـ CustomPaint — تحكم كامل بالرسم عند 60fps دون DOM/WebView. |
| **media_kit (libmpv)** | أقوى مشغّل وسائط في منظومة Flutter — يدعم كل codecs تقريباً وseek دقيق مطلوب للمحرر. |
| **Riverpod** | حالة compile-safe وقابلية اختبار عالية؛ الـ playhead يتحدث **بدون rebuild** لأشجار widgets (zero-rebuild scrubbing). |
| **Dart FFI/Process** | جسر سهل للثنائيات الأصلية (RustEngine, FFmpeg) عبر `Process.run` بنتائج JSON. |

### لماذا Rust؟

| السبب | التفصيل |
|-------|---------|
| **أداء بلا GC** | المعالجة الوسيطية (تصيير متوازٍ، DSP للمؤثرات، تحليل النصوص) تحتاج throughput عالي وlatency منخفض — لا garbage collection pauses. |
| **ثنائي واحد مستقل** | `clippify_engine.exe` واحد يُدمج بجانب تطبيق Flutter = توزيع بسيط بلا تثبيت Python أو runtime خارجي. |
| **بديل كامل لبايك-إند Python** | Cargo.toml يصفه حرفياً: *"full backend replacement"* — Axum بدل FastAPI، rusqlite بدل sqlite3، jsonwebtoken+bcrypt بدل python-jose/passlib. |
| **Safety + Concurrency** | tokio للأ async I/O المكثف (طلبات LLM، أنابيب FFmpeg) مع ضمانات ذاكرة Rust. |
| **DSP خالص** | `sound_forge.rs` يخلّق مؤثرات صوتية بمعالجة إشارة رقمية مكتوبة يدوياً — صعب وآمن في نفس الوقت. |

### لماذا FFmpeg؟

| السبب | التفصيل |
|-------|---------|
| **المعيار الصناعي** | كل شيء وسائط: transcode، فلاتر (zoom/pan/glitch)، concat، استخراج frames وصوت — لا بديل يغطي هذا النطاق. |
| **filter graph قابل للبرمجة** | `motion.rs` يبني سلاسل فلاتر parameterized ديناميكياً لكل مقطع — فعلياً DSL للحركة. |
| **أنابيب raw video** | `palette.rs` يسحب frames كـ raw RGB24 عبر stdout — تحليل ألوان بدون مكتبات decode. |
| **توزيع سهل** | ثنائي static يُدمج تلقائياً (`scripts/prepare_desktop.ps1` ينسخه من imageio-ffmpeg) — التطبيق يعمل standalone بلا PATH. |

### لماذا شلال LLM مجاني (Zero-Bill Cascade)؟

```
Gemini (free tier) ──فشل/حصة──▶ Groq (free tier, llama-3.3-70b) ──▶ Ollama (محلي, مجاني دائماً)
```

- **تكلفة صفرية للمستخدم**: لا اشتراك إلزامي؛ مفاتيح المستخدم الخاصة (BYOK) مشفّرة Fernet في `providers.db`.
- **خصوصية**: Ollama يعمل محلياً بالكامل — بيانات المستخدم لا تغادر الجهاز.
- **حصص عادلة**: `fair_queue.rs` يفرض حصصاً يومية لكل هوية مع cooldowns وledger استخدام.

---

## Standalone vs Backend Mode

وضعان تشغيليان يُختاران آلياً في `BackendService.chooseBackend()`:

```
                    ┌─────────────────────────────┐
                    │  LOCAL_MODE env / Platform  │
                    └──────────────┬──────────────┘
                 isWindows && != 'cloud'?
                    ├── نعم ──▶ BackendMode.local
                    └── لا ───▶ BackendMode.cloud
```

### Standalone Mode (محلي — سطح المكتب)

| البند | التفصيل |
|------|---------|
| **المنصات** | Windows (أساسياً). |
| **الباك-إند** | ثنائي `clippify_engine.exe` (Rust/Axum) يشتغل على `http://localhost:8000`. |
| **الإقلاع** | `BackendController` يشغّل/يتحقق من المحرك تلقائياً عند فتح التطبيق. |
| **الوسائط** | `ffmpeg.exe` مدمج بجانب الـ exe (بلا PATH ولا إنترنت). |
| **ASR** | whisper.cpp محلي (نموذج `WHISPER_MODEL`). |
| **LLM** | الشلال المحلي (Ollama دائماً متاح offline للمهام الحرجة). |
| **الخصوصية** | كل شيء على الجهاز؛ الإنترنت فقط لمفاتيح LLM الاختيارية. |

### Backend Mode (سحابي — موبايل/عملاء خفيفة)

| البند | التفصيل |
|------|---------|
| **المنصات** | Android/iOS وأي عميل غير Windows، أو Windows مع `LOCAL_MODE=cloud`. |
| **الباك-إند** | Stack سحابي: FastAPI API + RQ Worker + Redis + Postgres (docker-compose) على `https://api.clippify.app` (أو `CLOUD_API_URL`). |
| **المصادقة** | JWT إلزامي (`REQUIRE_AUTH=true`) مع تجديد توكن في `authed_dio.dart`. |
| **المعالجة** | طوابير مهام (Redis/RQ) وعمال GPU/CPU قابلة للتوسع أفقياً. |
| **التخزين** | S3/R2/MinIO عند تعريف `S3_BUCKET`، وإلا `./storage` محلي على السيرفر. |
| **الفوترة** | Stripe quotas (Pro/Studio) مع checkout URLs. |

> **العقد الموحد:** كلا الوضعين يحققان نفس عقود `docs/CONTRACTS.md` — بقية التطبيق لا تعرف الفرق إلا عبر `service.isCloud`.

---

*آخر تحديث: 2026-08 · مالك الملف: Squad-W5D [DocsDeploy]*
