# Clippify — SECURITY.md / نموذج التهديد الأمني

> Owner: AGENT-G1 [qa-security] • Last audit: 2026-08-24 • Scope: `api.py`, `auth/`, `billing/`, `downloader.py`, `storage.py`
> الحالة الحالية = ما هو موجود فعلاً في الكود اليوم، وليس ما يجب أن يكون.

---

## 0) 🚨 LOUD WARNING — ملفات أسرار موجودة على القرص الآن

```
⚠️⚠️⚠️  SECRETS ON DISK — ACTION REQUIRED  ⚠️⚠️⚠️

  pexels_key.txt   → EXISTS in repo root (untracked, git-ignored)
  cookies.txt      → EXISTS in repo root (yt-dlp browser cookies!)

→ pexels_key.txt MUST BE DELETED. Rotate the Pexels key immediately
  (https://www.pexels.com/api/) and move it to .env as PEXELS_API_KEY.
→ cookies.txt contains live browser session cookies (YouTube account).
  Delete it; treat any leaked cookie as a credential rotation event.

Verify with:
    Test-Path pexels_key.txt        # PowerShell → must print False
    git check-ignore pexels_key.txt # ignored ≠ safe to keep on shared machines
```

`.env` نفس الشيء: موجود في `.gitignore` ولا يُرفع أبداً — لكن أي جهاز مشارك/نسخة احتياطية قد يسرّبه.

---

## 1) Threat Model Table / جدول التهديدات

| # | Threat | الملف/الموقع | Current state (as-built) | Risk | Recommendation |
|---|--------|--------------|--------------------------|------|----------------|
| 1 | **JWT secret افتراضي** | `auth/service.py:19` → fallback `"dev-secret-change-me"`؛ و`.env.example:46` = `change-me` | لو `JWT_SECRET` غير مضبوط، كل التوكنات تُوقّع بمفتاح معروف للعالم. أي أحد يصنع توكن admin صالح. | 🔴 Critical in prod | **إلزامي في الإنتاج**: `JWT_SECRET` عشوائي ≥32 بايت (`python -c "import secrets;print(secrets.token_urlsafe(48))"`). ارفض الإقلاع في prod لو السر هو الافتراضي. تدوير السر يبطل كل الجلسات (لا revocation list حالياً). |
| 2 | **CORS مفتوح للجميع** | `api.py:95-101` → `allow_origins=["*"]` | أي موقع ويب في متصفح المستخدم يستطيع استدعاء الـ API محلياً (drive-by من المتصفح ضد localhost:8000). `allow_credentials=False` يخفف سرقة الكوكيز لكن التوكنات تُرسل من JS لو سُربت. | 🟠 High (desktop) / Medium (cloud) | في الإنتاج: قائمة origins صريحة (`https://app.clippify.app`). للديسكتوب المحلي: اربط الـ CORS بـ `http://localhost:*` فقط أو أزل CORS كلياً واستخدم origin ثابت. |
| 3 | **SSRF — YouTube download** | `api.py:419-424` + `downloader.validate_url` | ✅ محمي جيداً: HTTPS فقط، allowlist لمضيفي YouTube، حظر IP-literal، حظر رموز shell (`; \| & \` < > "`). | 🟢 Low | إضافة حظر DNS-rebinding (resolveHostName ثم تحقق من IP وقت الاتصال في yt-dlp) لو فُتح للسحابة. |
| 4 | **SSRF — `/api/broll/download`** ⚠️ GAP | `api.py:1712-1742` | ✅ يرفض non-http(s) و`http://` ("Only HTTPS URLs allowed"). ❌ **لا يوجد host allowlist**: يقبل أي رابط HTTPS ويحمّله بـ `requests.get` — يمكن استخدامه لجلب محتوى من إنترانت/خدمات سحابية داخلية عبر HTTPS ثم حفظه في `temp/`. ❌ Bug إضافي: `except Exception` يلتقط `HTTPException(400)` ويعيدها **500** بدل 400 (الاختبار `test_broll_download_rejects_non_pexels_host` موسوم xfail حتى تُصلح). | 🟠 High | أضف قبل التحميل: `if parsed.netloc not in {"www.pexels.com","videos.pexels.com","images.pexels.com","cdn.pixabay.com"}: raise HTTPException(400,...)` + تعطيل redirects أو التحقق منها + حد أقصى للحجم + فحص content-type. وأصلح الـ except ليترك HTTPException يمر (`except HTTPException: raise` قبلها). |
| 5 | **Upload presigned URL scope** | `storage.presign_put` (`storage.py:200-216`) | S3: presigned PUT صالح 3600ث على key بعد تنظيف traversal (`_norm_key` يحذف `..`). Local mode: يعيد مسار API نسبي `/api/upload/local/{key}` — **غير مطبّق في api.py حتى الآن** (لا endpoint PUT يستقبل). | 🟡 Medium | عند التنفيذ: scope المفتاح بمعرّف المستخدم (`uploads/{user_id}/...`)، أضف `ContentLengthRange` للتوقيع، قصّر TTL إلى ≤900ث، وتحقق من content-type خادمياً. لا تسمح بمفاتيح خارج نطاق المستخدم. |
| 6 | **Stripe webhook بدون توقيع (dev)** | `billing/router.py:91-120` | التحقق من التوقيع يتم **فقط** إذا ضُبط `STRIPE_SECRET_KEY` **و** `STRIPE_WEBHOOK_SECRET` معاً؛ وإلا يقبل JSON خام — أي أحد يرسل `checkout.session.completed` مع `plan=studio` يرقّي حسابه مجاناً في وضع dev المكشوف. | 🔴 Critical if exposed without secrets | في الإنتاج: **يجب** ضبط المفتاحين معاً، وإلغاء فرع JSON الخام تماماً (أو رفضه إذا كان الاستقبال عاماً)، والاعتماد على `stripe.Webhook.construct_event`. |
| 7 | **Rate limiting غير موجود** | كل الـ endpoints | لا يوجد أي throttle. `/api/auth/login` قابل للـ brute-force، و`/api/auto-edit` قابل لإغراق طابور `_render_pool`. | 🟠 High (cloud) | مثال سريع بـ slowapi: <br>`pip install slowapi`<br>```python\nfrom slowapi import Limiter\nfrom slowapi.util import get_remote_address\nlimiter = Limiter(key_func=get_remote_address)\napp.state.limiter = limiter\napp.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)\n\n@app.post("/api/auth/login")\n@limiter.limit("5/minute")\ndef login(...): ...\n```<br>وللمصاريف: `@limiter.limit("10/hour")` على `/api/auto-edit`. |
| 8 | **Quota bypass للمستخدم الحقيقي** | `api.py:1201` → `consume_credit(None)` | نقطة مهمة رُصدت أثناء التدقيق: `/api/auto-edit` ينادي `consume_credit(None)` دائماً حتى مع REQUIRE_AUTH=true → **لا خصم من رصيد المشترك فعلياً** (يعود `"auth_disabled"`). الاختبارات تكشف الشكل 402 لكن عبر monkeypatch. | 🟠 Business logic | مرّر المستخدم الحقيقي: اجعل dependency `require_user` يعيد user ومرّره لـ `consume_credit(user)` عندما `AUTH_ENABLED`. |
| 9 | **SQLite محلي vs Postgres** | `users.db` (`auth/service.py`)، `sessions.db` (`api.py`) | صلاحيات = صلاحيات ملف Windows للمستخدم الحالي؛ SQLite كاتب واحد (أقفال)، لا تشفير للبيانات في الراحة، والتوكنات stateless بلا revocation. مناسب لديسكتوب مستخدم واحد؛ **غير مناسب لتعدد المستخدمين على خادم مشترك**. | 🟡 Medium (cloud) | في وضع cloud: `DATABASE_URL` → Postgres + نقل auth/sessions إليه، تشفير القرص، backup مجدول، وإضافة revocation/denylist للتوكنات عند logout (حالياً logout تجاهلي بالكامل — العميل يحذف التوكن فقط). |
| 10 | **WS progress بلا مصادقة** | `api.py:879-907` `/ws/progress/{session_id}` | أي أحد يعرف session_id (UUID v4 عشوائي — صعب التخمين) يسمع تقدم الآخرين. لا token check على الـ WS. | 🟢 Low (UUID entropy) | عند تفعيل المصادقة: تحقق من Bearer في query/header قبل `accept()`، أو اربط sid بالمستخدم في DB. |

## 2) Secrets Inventory / جرد الأسرار (`.env.example`)

| Key | الاستخدام | حساسية |
|-----|-----------|---------|
| `GEMMA_API_KEY` | LLM (Copilot, plan generation) | 🔴 سر كامل — لا يُسجل في logs |
| `PEXELS_API_KEY` | B-roll search/download | 🔴 سر — **وانظر تحذير pexels_key.txt أعلاه** |
| `PIXABAY_API_KEY` | B-roll fallback | 🔴 |
| `FREESOUND_API_KEY` | SFX auto-insert | 🔴 |
| `DEEPL_API_KEY` / `GOOGLE_TRANSLATE_KEY` | ترجمة subtitles | 🔴 |
| `JWT_SECRET` | توقيع access/refresh tokens | 🔴 **MUST set in prod** |
| `REQUIRE_AUTH` | تفعيل Bearer على /api/* | ⚙️ يجب `true` في prod |
| `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` / `STRIPE_PRICE_*` | الفوترة + التحقق من webhook | 🔴 الاثنان معاً = شرط التحقق من التوقيع |
| `DATABASE_URL` / `REDIS_URL` | cloud DB / queue | 🔴 قد تحتوي كلمة مرور inline |
| `S3_BUCKET` / `S3_ENDPOINT` / `S3_ACCESS_KEY` / `S3_SECRET_KEY` | تخزين | 🔴 |
| `PUBLIC_BASE_URL` | روابط عامة/redirects | 🟢 غير سري |

ملاحظة: `.env.example` نفسه آمن (قيم placeholder). لا تنسَ أن `broll_manager.DEFAULT_PEXELS_KEY` قد يحمل مفتاحاً hardcoded — راجعه وأنقله إلى env (issue report-only).

## 3) Quick hardening checklist / قائمة التحصين السريعة

- [ ] حذف `pexels_key.txt` + `cookies.txt` من القرص وتدوير المفاتيح
- [ ] `JWT_SECRET` قوي + `REQUIRE_AUTH=true` في أي نشر خارج localhost
- [ ] CORS allowlist بدل `*`
- [ ] Host allowlist في `/api/broll/download` + إصلاح 500-instead-of-400
- [ ] `STRIPE_WEBHOOK_SECRET` إلزامي قبل فتح checkout العام
- [ ] slowapi rate limits (login + auto-edit + download)
- [ ] Postgres في cloud mode + token revocation عند logout
