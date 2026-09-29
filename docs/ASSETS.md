# 🎛️ Assets — الحزم الصوتية والخطوط

## SFX Pack (`assets/sfx/`)
12 مؤثراً توليدياً مُصنّعاً محلياً بـ Python خالص (`scripts/gen_sfx.py`).
- **الترخيص:** من إنتاج التطبيق نفسه — مخصص CC0.
- **إعادة التوليد:** `python scripts/gen_sfx.py [--seed 42]`
- الملفات WAV 44.1kHz mono 16-bit، مطبيع -3dB، بحواف anti-click.

| الملف | المدة | الاستخدام النموذجي |
|-------|------|---------------------|
| whoosh_up/down | 0.6s | انتقالات |
| riser | 1.4s | بناء قبل الهوك |
| impact | 0.35s | تأكيد على كلمة |
| pop / click / tick | ≤50ms | واجهات وكابشن |
| ding | 1.0s | نجاح |
| sub_drop | 0.7s | Punchline |
| sparkle | 0.5s | Reveal |
| transition_up/down | 0.5s | تغيير مشهد |

## Fonts (`assets/fonts/`)
Cairo + Rubik (Variable) — رخص SIL OFL من مستودع Google Fonts الرسمي.
إعادة الجلب: `scripts/fetch_fonts.ps1`

## حزم اختيارية يدوية (لا تُجلب آلياً)
- Kenney UI Audio (CC0): https://kenney.nl/assets/ui-audio
- Freesound (CC0 filter): https://freesound.org/search/?q=&f=license:%22Creative+Commons+0%22
ضع أي إضافات في `assets/sfx/extra/` وأضفها للـ manifest يدوياً.
