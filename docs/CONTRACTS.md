# Clippify v2 — API Contracts (Single Source of Truth)
> كل الـ agents ملزمة بهذا الملف. أي تغيير يمنع إلا بتحديث هذا الملف أولاً.

## Base
- **Local mode** (Windows desktop dev): `http://localhost:8000` — بايثون subprocess كما هو.
- **Cloud mode** (iOS/Android/إنتاج): `API_BASE_URL` من `.env` مثلاً `https://api.clippify.app`.
- عند `REQUIRE_AUTH=true` كل `/api/*` ما عدا `/api/auth/*` و `/api/health` تتطلب `Authorization: Bearer <access_token>`. الافتراضي `false` حالياً.

## Auth
```
POST /api/auth/register  {email, password, name}      → 200 {user, access_token, refresh_token}
POST /api/auth/login     {email, password}            → 200 نفس الشكل
POST /api/auth/refresh   {refresh_token}              → 200 {access_token, refresh_token}
GET  /api/auth/me        (Bearer)                     → 200 {user}
POST /api/auth/logout    (Bearer)                     → 200 {ok: true}
```
`user = {id, email, name, plan: "free"|"pro"|"studio", credits_used, credits_limit}`

أخطاء: `401` بيانات/توكن خاطئ • `409` الإيميل موجود • `422` FastAPI validation القياسي.

## Backend middleware contract
ملف إلزامي `auth/middleware.py` يصدّر:
```python
require_user  # FastAPI Dependency → dict user أو يرفع HTTPException(401)
AUTH_ENABLED: bool  # من env REQUIRE_AUTH
```
أي endpoint مكلف يستخدم:
```python
try:
    from auth.middleware import AUTH_ENABLED, require_user
except ImportError:
    AUTH_ENABLED = False; require_user = None
# في الـ endpoint: deps = [Depends(require_user)] if AUTH_ENABLED and require_user else []
```

## Plans & Credits
| Plan | فيديوهات/شهر | جودة | علامة مائية |
|------|--------------|------|-------------|
| free | 3 | 720p | نعم |
| pro | 30 | 1080p | لا |
| studio | 300 | 1080p | لا |
```
POST /api/billing/checkout {plan}          → {checkout_url}  (Stripe Checkout Session)
POST /api/billing/webhook                  (Stripe events → تحديث plan/credits)
GET  /api/billing/usage                    → {period_start, period_end, videos_used, videos_limit}
```
تجاوز الحصة على العمليات المكلفة → HTTP `402 {"detail": "quota_exceeded"}`.

## Upload (مسار السحابة للموبايل)
```
POST /api/upload/init    {filename, size, content_type} → {upload_id, upload_url}
PUT  <upload_url>        (binary body)
POST /api/upload/complete{upload_id}                   → {video_path}
```
تخزين عبر `storage.py`: S3/R2 عند توفر env، وإلا مجلد محلي.

## ⭐ Auto-Edit (الميزة الجوهرية)
```
POST /api/auto-edit
Body: {
  "video_path": "...",            // أو upload_id
  "answers": {
    "content_type": "auto",       // auto|podcast|comedy|educational|motivation|interview|awareness|gaming
    "platform": "tiktok",         // tiktok|shorts|reels|square
    "n_clips": 5,
    "clip_duration_sec": 60.0,
    "caption_theme": null,        // null = حسب نوع المحتوى
    "music": false,
    "broll": true,
    "translate_arabic": false,
    "custom_instructions": ""
  }
}
→ 202 {session_id}   |   402 quota_exceeded
```

### WebSocket تقدم العملية — `WS /ws/progress/{session_id}`
رسائل JSON من السيرفر بالترتيب:
```json
{"type":"progress","stage":"transcribing","progress":15.0,"message_ar":"جاري تفريغ الصوت...","message_en":"Transcribing audio..."}
{"type":"done","result":{"clips":[{"index":0,"file_url":"...","viral_score":0.87,"hook":{"text":"...","start_sec":1.2,"end_sec":4.8},"duration_sec":58.4,"caption_theme":"TikTok Yellow"}],"compiled_file_url":null}}
{"type":"error","detail":"..."}
```
مراحل ثابتة بالترتيب: `queued → transcribing → understanding → selecting → hooks → effects → rendering → compiling → done`

Fallback polling: `GET /api/auto-edit/status/{session_id}` يعيد آخر رسالة بنفس الشكل.
إلغاء: `POST /api/auto-edit/cancel/{session_id}`

## LLM Models (موحّد)
ملف `llm_config.py` في الجذر (موجود):
```python
MODEL_CHAIN = ["gemini-2.0-flash", "gemini-1.5-flash"]
def ask_llm(prompt, temperature=0.5, json_mode=False) -> str
```
**ممنوع** كتابة اسم موديل مباشرة في أي ملف جديد — استورد من llm_config.

## تصحيح عقود قديمة (السيرفر يقبل هذه الأشكال الآن)
| Endpoint | Body الصحيح |
|----------|-------------|
| /api/style/analyze-reference | `{reference_path, profile_name}` |
| /api/style/imitate | `{target_path, profile_path, output_name, words}` |
| /api/viral/recommendations | `{words, dna, viral_timeline}` |
| /api/project/ai/autoframing | `{timeline, clip_id}` |
| /api/audio/ducking | `{vocals_path, background_path, output_path, duck_factor?, words?}` |

## Flutter — نقاط التقاء داخلية
- `BackendService` abstract في `lib/core/backend/backend_service.dart`; تنفيذان `LocalBackendService` / `CloudBackendService`؛ اختيار بـ `Platform.isWindows && dotenv LOCAL_MODE!=cloud`.
- التوكنات في `flutter_secure_storage` فقط.
- WebSocket عبر `dart:io WebSocket` (نفس نمط collaboration.dart).
- نتائج→تايملاين: `ref.read(timelineProvider.notifier).setClips(List<VideoClip>)` موجودة.
- UI strings عربي افتراضياً + `message_en` عند التوفر.
