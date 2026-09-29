# Clippify — سياسة الخصوصية / Privacy Policy
_آخر تحديث: 2026-08-24_

## بالعربية

### ما نجمعه
| البيانات | الغرض | التخزين |
|----------|-------|---------|
| البريد الإلكتروني + الاسم | إنشاء الحساب وإدارة الاشتراك | قاعدة بيانات السحابة |
| الفيديوهات التي ترفعها | المعالجة والمونتاج فقط | تُحذف تلقائياً بعد 24 ساعة من اكتمال المعالجة |
| النصوص المستخرجة (transcripts) | فهم الفيديو وتوليد الكابشن | مع ملفات الفيديو — 24 ساعة |
| سجل الاستخدام (عدد العمليات) | حساب حصة باقتك | طوال مدة الاشتراك |
| مفاتيح الدفع | لا نراها إطلاقاً — تُدار بالكامل داخل Stripe | Stripe |

### الوضع المحلي (Windows)
عند تشغيل وضع "محلي": فيديوهاتك **لا تغادر جهازك** أبداً. كل المعالجة (Whisper/Gemma/FFmpeg) تحدث محلياً، والاتصال الخارجي الوحيد هو استدعاءات Gemini API لفهم المحتوى (تُرسل نصوص فقط، لا ملفات).

### أطراف ثالثة
- **Google Gemini API** — فهم محتوى الفيديو (نصوص + إطارات مختارة)
- **Pexels / Pixabay** — بحث B-roll (استعلامات كلمات فقط)
- **Stripe** — المدفوعات
- **yt-dlp** — تنزيل روابط يوتيوب التي تطلبها أنت

### حقوقك (GDPR/CCPA)
حذف الحساب وجميع البيانات خلال 30 يوماً عبر `privacy@clippify.app`. تصدير بياناتك عند الطلب. لا نبيع بياناتك لأي طرف.

---

## English

### What we collect
Account email/name, uploaded videos (**auto-deleted within 24h of processing completion**), extracted transcripts, usage counters. Payment data never touches our servers (Stripe-hosted).

### Local mode (Windows)
In local mode your videos **never leave your machine**; only text snippets and sampled frames go to Gemini for content understanding.

### Third parties
Google Gemini API, Pexels/Pixabay (keyword queries only), Stripe, yt-dlp (only for links you provide).

### Your rights
Account deletion + full data purge within 30 days via privacy@clippify.app. Data export on request. We never sell data.
