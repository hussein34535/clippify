"""One-off cleanup: remove unused _resolveFfmpeg from onboarding overlay."""
import pathlib
import re

f = pathlib.Path("lib/features/onboarding/onboarding_overlay.dart")
t = f.read_text(encoding="utf-8")

changed = False
if "_resolveFfmpeg" in t and t.count("_resolveFfmpeg") == 1:
    t = re.sub(
        r"/// Resolves the backend.*?\n\nFuture<String\?> _resolveFfmpeg\(\) async \{.*?\n\}\n\n",
        "",
        t,
        flags=re.S,
    )
    t = t.replace("import 'package:dio/dio.dart';\n", "")
    t = t.replace("import '../../core/api/api_client.dart';\n", "")
    if "FfmpegService" not in t:
        t = t.replace(
            "import '../../core/theme/app_theme.dart';",
            "import '../../core/native/ffmpeg_service.dart';\nimport '../../core/theme/app_theme.dart';",
        )
    changed = True

if changed:
    f.write_text(t, encoding="utf-8")
    print("cleaned")
else:
    print("skip - nothing to clean")
