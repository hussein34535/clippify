"""Fix mojibake in youtube_service.dart."""
import pathlib

f = pathlib.Path("lib/core/native/youtube_service.dart")
raw = f.read_bytes()
if raw.startswith(b"\xef\xbb\xbf"):
    raw = raw[3:]
t = raw.decode("utf-8", errors="ignore")

fixes = [
    ("\u00d8\u00a8\u00d8\u00af\u00d8\u00a1 \u00d8\u00a7\u00d9\u201e\u00d8\u00aa\u00d8\u00ad\u00d9\u2026\u00d9\u008a\u00d9\u0084...", "بدء التحميل..."),
    ("\u00d8\u00ac\u00d8\u00a7\u00d8\u00b1\u00d9\u008a \u00d8\u00a7\u00d9\u201e\u00d8\u00aa\u00d8\u00ad\u00d9\u2026\u00d9\u008a\u00d9\u0084 \u00d9\u2026\u00d9\u2020 \u00d9\u008a\u00d9\u02c6\u00d8\u00aa\u00d9\u008a\u00d9\u02c6\u00d8\u00a8...", "جاري التحميل من يوتيوب..."),
    ("\u00d8\u00aa\u00d9\u2026 \u00d8\u00a7\u00d9\u201e\u00d8\u00aa\u00d8\u00ad\u00d9\u2026\u00d9\u008a\u00d9\u0084!", "تم التحميل!"),
]

for old, new in fixes:
    if old in t:
        t = t.replace(old, new)

# Fix error message prefixes using regex
import re
t = re.sub(r"'ÙØ´Ù„ Ø§Ù„ØªØ­Ù…ÙŠÙ„: ", "'فشل التحميل: ", t)
t = re.sub(r"'Ø®Ø·Ø£: ", "'خطأ: ", t)

# Fix mojibake comments
t = t.replace("\u00e2\u0080\u0094", "\u2014")
t = t.replace("\u00e2\u0080\u00a0\u00e2\u0086\u0092", "\u2192")

f.write_text(t, encoding="utf-8")
print("fixed")
