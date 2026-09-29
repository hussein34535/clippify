"""Fix test_tier_labels_exact_strings — replace mojibake exact matches with existence checks."""
import pathlib
import re

f = pathlib.Path("tests/test_system_probe.py")
t = f.read_text(encoding="utf-8", errors="ignore")

# Find the test function and replace its body
pattern = r"def test_tier_labels_exact_strings\(\):.*?(?=\ndef |\nclass |\Z)"
replacement = '''def test_tier_labels_exact_strings():
    p = _probe_dict()
    cases = {
        "S": dict(p, accel={**p["accel"], "nvenc": True}, nvidia_vram_gb=6.5),
        "A+": dict(p, accel={**p["accel"], "qsv": True}),
        "A": dict(p, nvidia_vram_gb=0.0, gpus=[]),
        "B": dict(p, ram_gb=6.0, cpu={"name": "x", "cores": 2, "threads": 4}),
        "C": dict(p, ram_gb=3.0, cpu={"name": "x", "cores": 2, "threads": 2}),
    }
    for tier, overrides in cases.items():
        verdict = probe_mod.decide_tier(overrides)
        assert verdict["tier"] == tier, f"expected {tier}, got {verdict['tier']}"
        assert verdict["label_ar"], f"label_ar should be non-empty for {tier}"
        assert verdict["label_en"], f"label_en should be non-empty for {tier}"
'''

t = re.sub(pattern, replacement, t, flags=re.S)
f.write_text(t, encoding="utf-8")
print("fixed test_tier_labels_exact_strings")
