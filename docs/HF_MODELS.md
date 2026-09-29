# 🤗 Hugging Face — خريطة الموديلات المعتمدة لـ Clippify
> نتيجة بحث 2026 · كلها مجانية · مرتبة حسب أولوية التكامل · تتوافق مع نظام الـ Tiers (S/A+/A/B/C)

## 🏆 الاختيارات المعتمدة (Approved Picks)

### 1. فهم الفيديو (Vision-Language)
| الموديل | الحجم/VRAM | Tier | لماذا |
|---------|-----------|------|-------|
| **`qwen3-vl:4b`** (Ollama) | ~5GB Q4 | A+/S | يغلب GPT-4o-mini · grounding بـ timestamps hmsf · OCR 32 لغة · فيديو ساعات |
| **`SmolVLM2-500M-Video-Instruct`** | **يعمل على CPU!** | B/A | فيديو كامل بأقل من ربع مليار باراميتر — له demo جاهز "Video Highlight Generator" بنفس فكرتنا |
| `qwen2.5vl:7b` | 5GB Q4 | S | الجيل السابق — احتياطي |

➡️ **مُوصَّل فعلاً** في `llm_router.py` (`OLLAMA_VISION_PREFS`).

### 2. تفريغ عربي (ASR)
| الموديل | ملاحظة |
|---------|--------|
| **`MadLook/whisper-small-arabic-multidialect`** | متعدد اللهجات — المرشح الأول للتبديل عند whisper-small العام |
| `ayoubkirouane/whisper-small-ar` (Apache-2.0) | Common Voice 11 بديل مستقر |
| **WhisperX** (كود لا موديل) | محاذاة word-level + دمج diarization — أساس CaptionsV3 |

⚠️ القاعدة: نستخدم feature-extractor/tokenizer من large-v3 مع أوزان small (نفس المفردات).

### 3. فصل المتحدثين (Diarization)
| الموديل | الترخيص | ملاحظة حرجة |
|---------|---------|--------------|
| **`pyannote/speaker-diarization-community-1`** | MIT ✓ تجاري | **أحدث وأدق من 3.1** (benchmark 2025-09 أفضل) — اعتمده مباشرة |
| pyannote/speaker-diarization-3.1 | MIT ✓ | legacy |

🔑 **Gated**: يتطلب توكن HF مجاني + Accept للشروط مرة واحدة → `.env`: `HF_TOKEN=`.

### 4. موسيقى خلفية توليدية (بدون حقوق!)
| الموديل | VRAM | الحكم |
|---------|------|-------|
| **ACE-Step 1.5** | **<4GB** ✓ جهازك | الأقوى مفتوح المصدر (SongEval 8.09) — رخصة مجانية للأعمال <$1M إيراد |
| `facebook/musicgen-small` (300M) | CPU فقط (~3.3GB RAM، بطيء 14د/30ث) | للـTier B كخيار صبور، أو GPU أسرع |

### 5. مؤثرات صوتية توليدية
- **`OpenMOSS-Team/MOSS-SoundEffect`** — موديل مخصص لfoley/ambient (منافس لمولّدنا الرياضي؛ نجربه كـTier S enhancement).

### 6. تعليق صوتي (TTS للمستقبل)
| الموديل | الحجم | لماذا |
|---------|-------|-------|
| **`hexgrad/Kokoro-82M`** | يعمل CPU ×96 realtime! | #1 في HF TTS Arena · Apache-2.0 (إنجليزي أساساً) |
| Fish Speech | أكبر | استنساخ صوتي من 10 ثوانٍ + متعدد اللغات |

### 7. إزالة الخلفية / ماتينج *(مرحلة لاحقة)*
RVM (Robust Video Matting) وBiRefNet — متى نفعّل ميزة bg-replace الحقيقية بدل الستاب.

---

## 🔌 نقاط الدمج الحالية vs القادمة
| ✅ موصول اليوم | 🔜 Wave قادمة |
|----------------|----------------|
| Ollama vision/text prefs → llm_router | pyannote community-1 → Understanding W1 |
| HF_TOKEN placeholder في .env | SmolVLM2-500M → Tier-B vision fallback |
| | ACE-Step → MusicCraft (W3) |
| | Kokoro/Fish → Dubbing (post-W5) |

## ⚙️ خطوات تشغيل المستخدم للمحلي الكامل
```powershell
# 1) العقل المحلي (اختياري — بدونه يشتغل بالسحابة المجانية)
winget install Ollama.Ollama
ollama pull qwen3-vl:4b      # رؤية (~3GB تحميل)
ollama pull qwen3:4b         # نص

# 2) Diarization (توكن مجاني من hf.co/settings/tokens + Accept للموديل)
#    ضع التوكن في .env → HF_TOKEN=
```
