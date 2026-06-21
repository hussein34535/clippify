# clippify — Project Summary

## Goal
تحويل تطبيق Clippify إلى Flutter Desktop بأعلى معايير NLE الاحترافية (CapCut/Premiere Pro level)

## Constraints & Preferences
- الأولوية: Zero compilation errors في `flutter analyze`
- الباك إند: Python (subprocess) — لن يتم تحويله إلى Dart
- FFmpeg/FFprobe متوفران على النظام
- الباك إند الصحيح: `api.py` في جذر المشروع (FastAPI, port 8000)
- BackendController يتحقق من صحة الباك إند عبر `GET /docs` (يتأكد من وجود `swagger`/`FastAPI`) قبل اعتباره جاهزاً — أي خادم آخر على 8000 يُقتل تلقائياً

---

## Architecture

### Flutter App (`flutter_client/`)
- `lib/main.dart` — نقطة الدخول، تشغيل الباك إند
- `lib/app.dart` — الـ MaterialApp
- `lib/launch/backend_controller.dart` — إدارة دورة حياة الباك إند
- `lib/core/` — موديلات (`TimelineState`), ثيم (`AppTheme`), API client
- `lib/features/` — الميزات الأساسية (timeline, player, library, inspector, home, layout)
- `lib/shared/` — مكونات مشتركة (macros, keyboard shortcuts)

### Backend (`api.py`)
- FastAPI على port 8000
- ميزات: media-info, transcription, silence detection, AI tools, copilot, project save/load, render/export, YouTube download, settings

---

## Completed Features

### P0 Widgets (7/7)
- Toast system
- Header with app controls
- Footer with status
- Resizable panels (LayoutBuilder-based)
- Keyboard shortcuts system
- ClipItemWidget (gradients, resize handles, waveform)
- Drag & Drop from media library

### Timeline
- **Sidebar خارج السكرول** — `Row` مع `_buildSidebarColumn()` ثابت + `Expanded` مع `SingleChildScrollView` أفقي للتايملاين
- Track heights: 78/58/48/38 مع فراغ 4px
- Track sidebar buttons: mute (audio), visibility (video/overlay/subtitle), lock (all)
- Grid lines (كل 5 ثوان), Time ruler مع timecode
- Playhead (أبيض) + Snap line (برتقالي)
- Zoom (Ctrl+scroll / pinch / slider, 1x–500x)
- Clip resize (يمين/يسار) + drag-to-move
- Snap-to-playhead + snap-to-clips
- Vertical scroll للت tracks
- Auto-scroll playhead عند الخروج منviewport

### Playhead Scrubbing Performance
- `_playheadScrubNotifier` (`ValueNotifier<double>`) — تحديث بصري مباشر بدون أي rebuild
- `scrubPlayheadProvider` (`StateProvider<double>`) — يربط السكوب مع مشغل الفيديو
- `_commitScrub()` — ينادي `setPlayhead` مرة واحدة عند رفع الإصبع
- Video player يستمع إلى `scrubPlayheadProvider` ويسعى الفيديو أثناء السحب
- Auto-scroll معطل أثناء السحب
- Zero Riverpod rebuilds أثناء السحب

### Video Player (`media_kit`)
- `ClipRect` + `BoxFit.contain` + `alignment: Alignment.center` — منع قص الفيديو
- ربط ثنائي: position stream → playhead / playhead change → seek
- `_safeSeek` مع debounce (يمنع التزاحم)
- Cache settings (500MB)
- زر play/pause, mute, volume, timecode, seek slider

### Media Library
- `Draggable` بدون delay
- بطاقات: صورة مصغرة + اسم + زر حذف
- YouTube import عبر Dialog
- Thumbnails عبر ffmpeg (Process)

### Inspector Dashboard
- AI header + suggestion chips `Wrap`
- Copilot chat (عند عدم وجود كليب)
- Comment system مع tap-to-seek

### Other Features
- AI Tool Palette (219 tools)
- Subtitle Editor
- Export Modal
- Settings Modal
- Macros (تسجيل/تشغيل)
- Dark/Light Theme toggle
- Undo/Redo (Command Pattern)
- Project save/load
- Autosave (محلي، بدون API، كل 5 دقائق)

### Autosave
- حفظ محلي عبر `LocalStorage().saveAutosave()` — `%APPDATA%/Clippify/clippify_autosave.json`
- يعمل في `_startAutosaveTimer()` كل 5 دقائق
- يُحمّل تلقائياً عند بدء التطبيق في `_loadAutosave()` داخل `initState`
- مستقل تماماً عن الباك إند — لا يحتاج API

### Backend Controller
- `_verifyIsOurBackend()` — `GET /docs` ويتأكد من `swagger`/`FastAPI` في الرد
- لو البورت 8000 مشغول بعملية أخرى: يقتلها (`Process.killPid`) ويعيد التشغيل
- يبحث عن `api.py` في جذر المشروع (وضع التطوير) أو `clippify-backend` sidecar (الإنتاج)

---

## File Map

| File | Description |
|------|-------------|
| `flutter_client/.../timeline_widget.dart` | ~1752 سطر — الهيكل الرئيسي للتايملاين مع السايدبار الخارجي |
| `flutter_client/.../timeline_painters.dart` | `TrackConfig`, `RecordingIndicator`, `PlayheadTriangle` |
| `flutter_client/.../clip_item_widget.dart` | ~463 سطر — عرض الكليبات بالتدرجات + المقابض |
| `flutter_client/.../timeline_provider.dart` | ~1566 سطر — حالة التايملاين + Command Pattern + undo/redo + clipboard/selection helpers |
| `flutter_client/.../video_player_widget.dart` | ~882 سطر — مشغل الفيديو مع الربط الثنائي |
| `flutter_client/.../backend_controller.dart` | ~202 سطر — إدارة الباك إند مع التحقق من الصحة |
| `flutter_client/.../app_theme.dart` | الثيم (داكن/فاتح) + `AppColors` |
| `flutter_client/.../timeline_models.dart` | `VideoClip`, `AudioClip`, `OverlayClip`, `SubtitleClip`, `TimelineState`, `TextClip`, `TextTrack`, `SpeedPoint`, `SpeedRamp`, `Transition` |
| `flutter_client/.../api_client.dart` | HTTP client للباك إند (Dio) — مع `ApiResult<T>` sealed class |
| `flutter_client/.../local_storage.dart` | حفظ/تحميل autosave محلياً |
| `flutter_client/.../home_screen.dart` | الشاشة الرئيسية مع LayoutBuilder + resizable panels + KeyboardShortcutsWidget |
| `flutter_client/.../inspector_widget.dart` | تبويبات Inspector مع tab لكير كروم + speed ramp + keyframes |
| `flutter_client/.../inspector_shared.dart` | `InspectorSectionHeader`, `InspectorPropertySlider`, `InspectorNumberInput`, `InspectorPlaceholder` |
| `flutter_client/.../color_grading_panel.dart` | `ColorWheel`, `ColorPresets` مع 8 إعدادات جاهزة |
| `flutter_client/.../timeline_painters.dart` | `TrackConfig`, `RecordingIndicator`, `PlayheadTriangle` |
| `flutter_client/.../core/cache/cache_manager.dart` | **جديد** — `CacheManager` singleton (thumbnails/proxy cache) |
| `flutter_client/.../core/constants/timeline_constants.dart` | **جديد** — ثوابت التايملاين (track heights, zoom, snap, ...) |
| `flutter_client/.../core/models/timeline_templates.dart` | **جديد** — BUILTIN_TEMPLATES (intro/outro/podcast) منقول من web |
| `flutter_client/.../core/services/analytics_service.dart` | **جديد** — analytics tracking منقول من web |
| `flutter_client/.../core/services/midi_service.dart` | **جديد** — MIDI mapping (stub — يحتاج flutter_midi_command) |
| `api.py` | FastAPI backend (port 8000) |

---

## Key Patterns

### Sidebar خارج السكرول
```
Row(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    _buildSidebarColumn(),  // 110px, ثابت
    Expanded(               // التايملاين, يمرر أفقياً
      child: LayoutBuilder > Listener > GestureDetector > SingleChildScrollView(H) > ...
    ),
  ],
)
```

### Scrub Flow
```
User drag → _handleScrubbing()
  ├─ _playheadScrubNotifier.value = x  (بصري, صفر rebuild)
  └─ scrubPlayheadProvider.state = x   (فيديو seek)
User releases → _commitScrub()
  └─ setPlayhead(x) → Riverpod (مرة واحدة)
```

### Offsets Removed
كل `± 110.0` أزيلت من: `_getSecondsFromX`, zoom anchors, grid lines, ruler, playhead, snap line, track lane clips, startSec/endSec calculations.

### Autosave Flow
```
edit → _scheduleAutosave() → Timer (2s debounce) → LocalStorage().saveAutosave()
startup → _loadAutosave() → LocalStorage().loadAutosave() → ref.read(timelineProvider.notifier).loadProject()
```

### Recovery Note
إذا حدث حذف غير مقصود لـ `home_screen.dart`، يمكن استرجاعه من kernel snapshot في:
`.dart_tool/flutter_build/<hash>/app.dill` — ابحث عن `class HomeScreen` باستخدام `Select-String`.

---

## Running
```bash
# تأكد ما في process غلط على port 8000
netstat -ano | findstr :8000
taskkill /PID <wrong_pid> /F

# شغّل الباك إند (يدوياً أو من Flutter)
python api.py

# شغّل التطبيق
cd flutter_client
flutter run -d windows
```

---

## Phase 2 — Feature Expansion & Polish (قيد التنفيذ)

### Status
| Metric | Value |
|--------|-------|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test` | 55/55 passed |
| `flutter build windows --release` | نجح |
| GitHub Actions CI | `flutter_ci.yml` (multi-OS) + `python_ci.yml` |
| Python tests | URL validation + tool registry counts |

### Completed
| # | Task |
|---|------|
| ✅ | Phase 1: Remove React/Tauri layer, port 3 files to Dart |
| ✅ | Phase 2: Fix 6 critical blockers (cache_manager, dotenv, debugPrint, downloader, backslash, riverpod) |
| ✅ | Phase 3: Refactor code smells (TimelineNotifier, menu callbacks, tool counts, copilot) |
| ✅ | Phase 4: Add Python tests + CI/CD |
| ✅ | Phase 5: Reconcile docs |

### Remaining (Phase 2.5+)
| # | Task | Priority |
|---|------|----------|
| 1 | توحيد اسم المشروع (flutter_client → clippify) عبر الـ package | Low |
| 2 | إضافة المزيد من Widget Tests (ClipItemWidget, VideoPlayer, HomeScreen) | Medium |
| 3 | تحسينات الأداء (استخراج الـ 4 resize handlers المكررة في _buildTrackLane) | Medium |
| 4 | إضافة الترجمة (i18n) مع دعم العربية والإنجليزية | Low |
