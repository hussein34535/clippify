# Clippify v2 — دليل النشر / Deployment Guide

> مالك الملف: AGENT-4 (backend-infra). المرجع: `docs/CONTRACTS.md`

## 1) التشغيل المحلي بـ Docker — Run locally

```bash
cp .env.example .env          # عدّل القيم أولاً / edit values first
docker compose up --build
```

- API: `http://localhost:8000` (docs على `/docs`)
- Worker: يعمل تلقائياً على طابور RQ `clippify`
- Redis + Postgres: خدمات داخلية جاهزة

## 2) متغيرات البيئة المطلوبة — Required env vars

| المتغير | إلزامي؟ | الوصف |
|---|---|---|
| `DATABASE_URL` | نعم | `postgres://clippify:PASSWORD@postgres:5432/clippify` (أو `sqlite:///./data/clippify.db` للتطوير) |
| `REDIS_URL` | للإنتاج | `redis://redis:6379/0` — بدونه يعمل ThreadPool fallback داخل العملية |
| `POSTGRES_PASSWORD` | نعم | كلمة مرور postgres (تُستخدم في compose) |
| `S3_BUCKET` | اختياري | عند تعريفه يتفعل backend التخزين S3 |
| `S3_ENDPOINT` | اختياري | R2/MinIO endpoint مثل `https://<account>.r2.cloudflarestorage.com` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | مع S3 | مفاتيح الوصول |
| `PUBLIC_BASE_URL` | محلي | مثل `https://api.clippify.app` ليصبح رابط `/files/...` مطلقاً |
| `MAX_WORKERS` | لا | عدد خيوط الـ fallback (افتراضي 2) |
| `REQUIRE_AUTH`, `API_BASE_URL`, مفاتيح Gemini... | راجع `.env.example` | حسب CONTRACTS.md |

## 3) وضع التخزين المحلي — Local storage mode

عند عدم وجود `S3_BUCKET` تُحفظ الملفات في `./storage/`. يجب أن يضيف مالك `api.py`:

```python
from fastapi.staticfiles import StaticFiles
app.mount("/files", StaticFiles(directory="storage"), name="files")
```

وعندها يرجّع `storage.public_url(key)` روابط بصيغة `{PUBLIC_BASE_URL}/files/<key>`.

## 4) عمال GPU لاحقاً — GPU workers (RunPod/Vast)

- `Dockerfile.worker` حالياً CPU. لاحقاً: غيّر الـ base إلى `nvidia/cuda:12.x-runtime-ubuntu22.04` (placeholder في التعليق أعلى الملف) — الـ CMD نفسه (`python -m jobs`).
- العامل يتصل بأي Redis عام: `REDIS_URL=redis://<host>:6379/0 python -m jobs`
- على RunPod/Vast: شغّل الحاوية بنفس الصورة + `--gpus all`، وتأكد من `S3_*` حتى يستطيع العامل تنزيل الفيديو ورفع النتيجة.
- الطابور موحّد: `clippify` — لا فرق بين عامل CPU وعامل GPU من وجهة نظر API.

## 5) مسار الهجرة SQLite → Postgres — Migration path

1. اليوم: api.py يستخدم sqlite مباشرة (`sessions.db`)؛ طبقة `db.py` الجديدة تقرأ `DATABASE_URL`.
2. انقل الاستدعاءات تدريجياً: `sqlite3.connect(...)` → `from db import execute, query` (نفس الدلالات، rows تصير dicts).
3. جدول v2 التجريبي موجود بالفعل: `sessions_v2`. انسخ السجلات القديمة:
   ```bash
   python -c "import db; db.init_db()"     # ينشئ الجداول
   # ثم نسخ صفوف sessions -> sessions_v2 عبر سكربت لمرة واحدة
   ```
4. بدّل `DATABASE_URL` إلى postgres URL (بعد `pip install psycopg2-binary`) — نفس الكود يعمل لأن db.py يترجم `?` → `%s`.
5. النسخ الاحتياطي: sqlite = انسخ ملف `data/clippify.db`؛ postgres:
   ```bash
   docker compose exec postgres pg_dump -U clippify clippify > backup_$(date +%F).sql
   # استعادة:
   cat backup_2026-01-01.sql | docker compose exec -T postgres psql -U clippify clippify
   ```

## 6) نسخ احتياطي — Backups

| ماذا | أين | كيف |
|---|---|---|
| قاعدة البيانات | volume `pgdata` أو `./data/*.db` | pg_dump أعلاه / نسخ الملف بعد إيقاف الكتابة |
| الملفات المخزنة | `./storage/` أو bucket S3/R2 | `rclone sync ./storage remote:bucket` (وضع S3: enable versioning on the bucket) |
| الإعدادات | `.env` (سرّي!) | خزّنه في password manager / secrets vault |

## 7) فحص سريع — Sanity checks

```bash
python -m py_compile db.py storage.py jobs/queue.py jobs/__init__.py
python -m pytest tests/test_infra_units.py -v
docker compose config --quiet    # لو docker مثبّت
```
