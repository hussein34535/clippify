"""Repair mojibake (UTF-8 read as cp1252 then re-encoded) in .dart files."""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")

MARKERS = ("Ã˜", "Ã¢â", "ØªØ¹Ø°Ø±", "Ø£ÙˆÙ„", "Ø§Ù„Ù…Ø´Ø±ÙˆØ¹")

fixed = []
skipped = []
for folder in ("lib", "test"):
    for f in pathlib.Path(folder).rglob("*.dart"):
        raw = f.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            raw = raw[3:]
        t = raw.decode("utf-8", errors="ignore")
        if any(m in t for m in MARKERS):
            try:
                repaired = t.encode("cp1252").decode("utf-8")
                f.write_text(repaired, encoding="utf-8")
                fixed.append(str(f))
            except Exception as e:
                skipped.append((str(f), repr(e)[:70]))

print("REPAIRED:", len(fixed))
for x in fixed:
    print(" ok", x)
for s in skipped:
    print(" SKIP", s)
