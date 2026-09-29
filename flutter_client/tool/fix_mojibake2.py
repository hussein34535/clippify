"""Hybrid mojibake repair: chars <=0xFF via latin-1, cp1252 specials via map."""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

CP1252_EXTRAS = {
    "€": 0x80, "‚": 0x82, "ƒ": 0x83, "„": 0x84, "…": 0x85, "†": 0x86,
    "‡": 0x87, "ˆ": 0x88, "‰": 0x89, "Š": 0x8A, "‹": 0x8B, "Œ": 0x8C,
    "Ž": 0x8E, "'": 0x91, "'": 0x92, """: 0x93, """: 0x94, "•": 0x95,
    "–": 0x96, "—": 0x97, "˜": 0x98, "™": 0x99, "š": 0x9A, "›": 0x9B,
    "œ": 0x9C, "ž": 0x9E, "Ÿ": 0x9F,
}


def hybrid_encode(s: str) -> bytes:
    out = bytearray()
    for ch in s:
        o = ord(ch)
        if o < 0x100:
            out.append(o)
        elif ch in CP1252_EXTRAS:
            out.append(CP1252_EXTRAS[ch])
        else:
            raise ValueError(f"non-mojibake char {ch!r}")
    return bytes(out)


f = pathlib.Path("lib/features/onboarding/onboarding_overlay.dart")
raw = f.read_bytes()
if raw.startswith(b"\xef\xbb\xbf"):
    raw = raw[3:]
t = raw.decode("utf-8", errors="ignore")

rep_bytes = hybrid_encode(t)
repaired = rep_bytes.decode("utf-8")
f.write_text(repaired, encoding="utf-8")

print("REPAIRED onboarding_overlay.dart")
for pat in ("أول فيديو", "استورد", "تعذ", "🎬"):
    print(f"  contains {pat!r}:", pat in repaired)
