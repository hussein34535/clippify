# Clippify — دليل النشر / Deployment Guide

> كيف تبني وتوزّع Clippify على كل المنصات: **سطح المكتب (Windows)**، **الموبايل (Android/iOS)**، و**السحابة (Docker + Oracle Free Tier)**.
>
> ملفات ذات صلة: [`ARCHITECTURE.md`](./ARCHITECTURE.md) · [`CONTRACTS.md`](./CONTRACTS.md) · [`../.env.example`](../.env.example)

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Desktop Deployment (Windows)](#desktop-deployment-windows)
- [Mobile Deployment (Android / iOS)](#mobile-deployment-android--ios)
- [Cloud Deployment (Server)](#cloud-deployment-server)
  - [Docker Compose](#docker-compose)
  - [Oracle Cloud Free Tier](#oracle-cloud-free-tier)
- [Environment Variables Reference](#environment-variables-reference)
- [Post-Deploy Checklist](#post-deploy-checklist)
- [Backups](#backups)

---

## Prerequisites

| الأداة | الإصدار | ملاحظات |
|--------|---------|---------|
| Flutter SDK | 3.44+ (stable) | `flutter --version` |
| Rust toolchain | stable (rustup) | لبناء المحرك: `cargo --version` |
| FFmpeg / FFprobe | أحدث ثابت | للتطوير؛ في التوزيع يُدمج تلقائياً |
| Python | 3.9+ | لسكربتات التجهيز فقط (`imageio-ffmpeg`) |
| Android Studio / Xcode | حسب المنصة | للموبايل فقط |
| Docker Engine | 24+ | للسحابة فقط |

---

## Desktop Deployment (Windows)

### 1. بناء محرك Rust

```powershell
cd engine
cargo build --release
# الناتج: engine\target\release\clippify_engine.exe
```

### 2. بناء تطبيق Flutter

```powershell
cd flutter_client
flutter pub get
flutter build windows --release
# الناتج: build\windows\x64\runner\Release\flutter_client.exe
```

### 3. تجميع الحزمة (Bundling)

التطبيق يبحث عن المكونات بهذا الترتيب (انظر `lib/core/native/rust_engine.dart`):

1. بجانب الـ exe نفسه → `clippify_engine.exe`
2. مسار التطوير → `engine\target\release\clippify_engine.exe`

خطوات التجميع الكاملة:

```powershell
# أ) انسخ محرك Rust بجانب الـ exe
Copy-Item "engine\target\release\clippify_engine.exe" `
  "flutter_client\build\windows\x64\runner\Release\" -Force

# ب) ادمج ffmpeg.exe (سكربت جاهز يسحب ثنائي imageio-ffmpeg)
cd flutter_client
powershell scripts\prepare_desktop.ps1 -Configuration Release

# ج) (اختياري) ضع whisper-cli + نموذج ggml في نفس المجلد للتفريغ offline
```

النتيجة النهائية — مجلد `Release\` يحتوي:

```
Release\
├── flutter_client.exe      # التطبيق
├── clippify_engine.exe     # محرك Rust (باك-إند محلي :8000)
├── ffmpeg.exe              # وسائط standalone
├── *.dll                   # مكتبات Flutter/plugins
└── data\                   # assets
```

### 4. التوزيع (Distribution)

| القناة | الخطوات |
|--------|---------|
| **ZIP مباشر** | اضغط مجلد `Release\` كاملاً → رفع على GitHub Releases. المستخدم يفك الضغط ويشغّل — بلا تثبيت. |
| **MSIX** | `flutter pub run msix:create` (أضف حزمة `msix`) → توقيع بشهادة code-signing → توزيع/متجر Microsoft. |
| **Inno Setup** | سكربت installer يلف مجلد `Release\` → إعداد كلاسيكي مع اختصارات وقائمة ابدأ. |

> **ملاحظة توقيع:** بدون شهادة code-signing سيرفع Windows SmartScreen تحذيراً. للإنتاج: اشترِ شهادة OV/EV ووقّع بـ `signtool sign`.

### 5. فحص ما بعد البناء

```powershell
# شغّل الـ exe — يجب أن يقلع BackendController المحرك تلقائياً
& "flutter_client\build\windows\x64\runner\Release\flutter_client.exe"
curl http://localhost:8000/health   # {"status":"ok"}
```

---

## Mobile Deployment (Android / iOS)

> على الموبايل يعمل التطبيق في **وضع Cloud** تلقائياً (انظر [Standalone vs Backend Mode](./ARCHITECTURE.md#standalone-vs-backend-mode)) — يحتاج سيرفر سحابي منشور.

### Android

#### 1. تهيئة التوقيع

```powershell
keytool -genkey -v -keystore %USERPROFILE%\clippify-release.jks `
  -keyalg RSA -keysize 2048 -validity 10000 -alias clippify
```

أنشئ/عدّل `android\key.properties`:

```properties
storePassword=<كلمة مرور الـ keystore>
keyPassword=<كلمة مرور المفتاح>
keyAlias=clippify
storeFile=C:\\Users\\<user>\\clippify-release.jks
```

> احتفظ بالـ keystore في مكان آمن — فقدانه = فقدان قدرة تحديث التطبيق.

#### 2. البناء

```powershell
cd flutter_client
flutter build appbundle --release     # لمتجر Play (.aab)
flutter build apk --release           # توزيع مباشر (.apk)
# النتائج:
#   build\app\outputs\bundle\release\app-release.aab
#   build\app\outputs\flutter-apk\app-release.apk
```

الأيقونة وشاشة البداية مضبوطة أصلاً عبر `flutter_launcher_icons` + `flutter_native_splash` في `pubspec.yaml` — بعد تغيير `assets/icon/icon.png` شغّل:

```powershell
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

#### 3. نشر Google Play

1. [Play Console](https://play.google.com/console) → إنشاء تطبيق.
2. املأ: الوصف، اللقطات، تصنيف المحتوى، سياسة الخصوصية (انظر `PRIVACY.md`).
3. Production → Create release → ارفع `app-release.aab`.
4. مراجعة Google (أيام قليلة لأول مرة).
5. **اختبارات داخلية أولًا:** Internal testing track قبل الإنتاج.

### iOS

> يتطلب macOS + Xcode + حساب Apple Developer ($99/سنة).

```bash
cd flutter_client
flutter build ipa --release
# الناتج: build/ios/ipa/clippify.ipa
```

ثم عبر Xcode أو Transporter:

1. افتح `ios\Runner.xcworkspace` → اضبط Team + Signing & Capabilities.
2. Product → Archive → Distribute App → App Store Connect.
3. في [App Store Connect](https://appstoreconnect.apple.com): أكمل Metadata + Screenshots → Submit for Review.

> **ملاحظات:** `remove_alpha_ios: true` مضبوط للأيقونة (متطلب Apple). أضف `NSPhotoLibraryUsageDescription` و`NSMicrophoneUsageDescription` في Info.plist إن استخدمت capture/الحفظ للمعرض.

---

## Cloud Deployment (Server)

### Docker Compose

الـ stack الكامل (api + worker + redis + postgres، MinIO اختياري):

```bash
cp .env.example .env        # عدّل القيم أولاً — خاصة JWT_SECRET وAPP_SECRET
docker compose up --build -d
```

| الخدمة | المنفذ | الدور |
|--------|--------|-------|
| `api` | 8000 | FastAPI — REST + docs على `/docs` |
| `worker` | — | عامل طابور RQ (`python -m jobs`) للمعالجة الثقيلة |
| `redis` | داخلي | طابور المهام |
| `postgres` | داخلي | قاعدة البيانات (volume `pgdata`) |
| `minio` (اختياري) | 9000/9001 | S3 محلي للتجربة — فعّل بالتعليق في `docker-compose.yml` |

فحص سريع:

```bash
curl http://localhost:8000/api/health
docker compose logs -f api worker
```

### Oracle Cloud Free Tier

Oracle Always Free مناسب جداً لتشغيل الـ stack (خصوصاً A1 Flex ARM حتى 4 OCPU / 24GB RAM مجاناً).

#### 1. إنشاء المثيل

1. سجّل في [Oracle Cloud](https://cloud.oracle.com) → Compute → Create Instance.
2. اختر **Ampere A1** (ARM): shape `VM.Standard.A1.Flex` — 2–4 OCPU + 8–24 GB RAM (حد Always Free).
3. نظام التشغيل: Ubuntu 22.04+ (أو Oracle Linux). حمّل مفتاح SSH.
4. Boot volume: 50–100 GB (الحد المجاني 200 GB إجمالاً).

#### 2. تجهيز السيرفر

```bash
ssh ubuntu@<PUBLIC_IP>

# تحديث + أساسيات
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-plugin git ufw
sudo usermod -aG docker $USER && newgrp docker

# جدار ناري (افتح 80/443 و22 فقط)
sudo ufw allow OpenSSH && sudo ufw allow 80 && sudo ufw allow 443
sudo ufw enable

# ملاحظة ARM: صور Dockerfile الأساسية يجب أن تكون multi-arch
# (python:*-slim و redis:7-alpine و postgres:16-alpine كلها تدعم arm64)
```

> ⚠️ **مهم لـ ARM:** أي صورة مبنية من ثنائيات مُجمَّعة مسبقاً (ffmpeg static x86 مثلاً) لن تعمل — استخدم الحزم من apt أو ابنِ من المصدر داخل الـ Dockerfile.

#### 3. تشغيل Clippify

```bash
git clone <REPO_URL> clippify && cd clippify
cp .env.example .env && nano .env    # JWT_SECRET, APP_SECRET, POSTGRES_PASSWORD...
docker compose up --build -d
```

#### 4. DNS + HTTPS

```bash
# وجّه نطاقك (A record) إلى PUBLIC_IP ثم:
sudo apt install -y certbot python3-certbot-nginx
# أو استخدم Caddy/Traefik أمام الـ API — الأسهل والأسرع
```

اضبط `PUBLIC_BASE_URL=https://api.yourdomain.com` في `.env` ليصبح روابط الملفات `/files/...` مطلقة.

#### 5. مراقبة وتحديث

```bash
docker compose ps                     # حالة الخدمات
docker compose logs -f --tail=100     # سجلات حية
git pull && docker compose up --build -d   # تحديث
docker system prune -af               # تنظيف دوري للصور القديمة
```

> **ترقية مستقبلية للـ GPU:** عمال RunPod/Vast يتصلون بنفس Redis (`REDIS_URL=redis://<host>:6379/0 python -m jobs`) — الطابور موحد باسم `clippify`.

---

## Environment Variables Reference

> انسخ `.env.example` إلى `.env`. **لا تُ-commit مطلقاً** (git-ignored).

### مفاتيح الذكاء الاصطناعي

| المتغير | إلزامي؟ | الوصف |
|---------|---------|-------|
| `GEMMA_API_KEY` | موصى به | Google Gemma/Gemini — Copilot والتوليد ([aistudio.google.com/apikey](https://aistudio.google.com/apikey)) |
| `GROQ_API_KEY` | اختياري | Groq free tier — hop ثاني في الشلال ([console.groq.com/keys](https://console.groq.com/keys)) |
| `OLLAMA_URL` | لا | نقطة Ollama المحلية (افتراضي `http://localhost:11434`) — آخر حلقة مجانية |
| `PROVIDER_CAPS` | لا | JSON لحصص يومية لكل مزود، مثل `{"gemini_free":1500,"groq_free":200}` |
| `CLIPPIFY_PROVIDERS_DB` | لا | مسار SQLite لمفاتيح BYOK وledger الاستخدام |
| `HF_TOKEN` | للدياريزشن | HuggingFace token لنماذج pyannote (gated) |

### مخزون الفيديو والصوت والترجمة

| المتغير | إلزامي؟ | الوصف |
|---------|---------|-------|
| `PEXELS_API_KEY` | لـ B-roll | [pexels.com/api](https://www.pexels.com/api/) |
| `PIXABAY_API_KEY` | احتياطي | fallback لـ B-roll |
| `FREESOUND_API_KEY` | اختياري | مؤثرات صوتية تلقائية |
| `DEEPL_API_KEY` / `GOOGLE_TRANSLATE_KEY` | اختياري | ترجمة الترجمات |

### الوسائط والمخرجات

| المتغير | إلزامي؟ | الوصف |
|---------|---------|-------|
| `WHISPER_MODEL` | لا | `tiny` \| `base` \| `small` \| `medium` \| `large` (افتراضي tiny) |
| `OUTPUT_DIR` | لا | مجلد التصدير الافتراضي (افتراضي `./output`) |

### المصادقة والفوترة (Cloud)

| المتغير | إلزامي؟ | الوصف |
|---------|---------|-------|
| `JWT_SECRET` | **نعم (إنتاج)** | سر توقيع JWT — **غيّره فوراً** |
| `APP_SECRET` | **نعم (إنتاج)** | تشفير Fernet لمفاتيح BYOK في providers.db |
| `REQUIRE_AUTH` | لا | `true` = فرض Bearer auth على `/api/*` (استثناء: `/api/auth/*`, `/api/health`) |
| `STRIPE_SECRET_KEY` / `STRIPE_PRICE_PRO` / `STRIPE_PRICE_STUDIO` | للفوترة | Stripe؛ فارغة = checkout URLs وهمية في dev |
| `PUBLIC_BASE_URL` | نعم (cloud) | مثل `https://api.clippify.app` — لروابط الملفات وredirects |

### البنية السحابية (Cloud Infra)

| المتغير | إلزامي؟ | الوصف |
|---------|---------|-------|
| `DATABASE_URL` | نعم | `postgres://clippify:PASS@postgres:5432/clippify` أو `sqlite:///./data/clippify.db` للتطوير |
| `POSTGRES_PASSWORD` | نعم (compose) | كلمة مرور Postgres في docker-compose |
| `REDIS_URL` | للإنتاج | `redis://redis:6379/0` — بدونه ThreadPool fallback داخل العملية |
| `S3_BUCKET` / `S3_ENDPOINT` / `S3_ACCESS_KEY` / `S3_SECRET_KEY` | لا | عند تعريفها يتفعل تخزين S3/R2؛ وإلا `./storage` محلي |
| `MAX_WORKERS` | لا | عدد خيوط الـ fallback (افتراضي 2) |

### عميل Flutter (`assets/.env`)

| المتغير | الوصف |
|---------|-------|
| `LOCAL_MODE` | `local` (افتراضي على Windows) أو `cloud` — يفرض وضع الباك-إند |
| `API_BASE_URL` | عنوان الباك-إند المحلي (افتراضي `http://localhost:8000`) |
| `CLOUD_API_URL` | عنوان السحابة (افتراضي `https://api.clippify.app`) |

---

## Post-Deploy Checklist

- [ ] `GET /api/health` يعيد `{"status":"ok"}`
- [ ] `JWT_SECRET` و`APP_SECRET` و`POSTGRES_PASSWORD` كلها قيم عشوائية طويلة (ليست الافتراضي)
- [ ] `REQUIRE_AUTH=true` في البيئة العامة
- [ ] HTTPS مفعل خلف Nginx/Caddy + شهادة صالحة
- [ ] نسخ احتياطي مجدول لقاعدة البيانات و`storage/`
- [ ] `PUBLIC_BASE_URL` مضبوط للنطاق الحقيقي
- [ ] مفاتيح LLM/BYOK مُدخلة ومختبنة (وليست في الصورة نفسها)

## Backups

| ماذا | أين | كيف |
|------|-----|-----|
| قاعدة البيانات | volume `pgdata` | `docker compose exec postgres pg_dump -U clippify clippify > backup_$(date +%F).sql` |
| الاستعادة | — | `cat backup.sql | docker compose exec -T postgres psql -U clippify clippify` |
| الملفات | `./storage/` أو bucket | `rclone sync ./storage remote:bucket` (+ versioning على الـ bucket) |
| الأسرار | `.env` | password manager / secrets vault — لا يدخل git أبداً |

---

*آخر تحديث: 2026-08 · مالك الملف: Squad-W5D [DocsDeploy]*
