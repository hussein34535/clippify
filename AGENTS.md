# ClipAI — Project Summary

## Goal
تحويل تطبيق ClipAI إلى Flutter Desktop بأعلى معايير NLE الاحترافية (CapCut/Premiere Pro level)

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
- AI Tool Palette (219 tool)
- Subtitle Editor
- Export Modal
- Settings Modal
- Macros (تسجيل/تشغيل)
- Dark/Light Theme toggle
- Undo/Redo (Command Pattern)
- Project save/load
- Autosave (محلي، بدون API، كل 5 دقائق)

### Autosave
- حفظ محلي عبر `LocalStorage().saveAutosave()` — `%APPDATA%/ClipAI/clipai_autosave.json`
- يعمل في `_startAutosaveTimer()` كل 5 دقائق
- يُحمّل تلقائياً عند بدء التطبيق في `_loadAutosave()` داخل `initState`
- مستقل تماماً عن الباك إند — لا يحتاج API

### Backend Controller
- `_verifyIsOurBackend()` — `GET /docs` ويتأكد من `swagger`/`FastAPI` في الرد
- لو البورت 8000 مشغول بعملية أخرى: يقتلها (`Process.killPid`) ويعيد التشغيل
- يبحث عن `api.py` في جذر المشروع (وضع التطوير) أو `clipai-backend` sidecar (الإنتاج)

---

## File Map

| File | Description |
|------|-------------|
| `flutter_client/.../timeline_widget.dart` | ~1430 سطر — الهيكل الرئيسي للتايملاين مع السايدبار الخارجي |
| `flutter_client/.../timeline_painters.dart` | **جديد** — `TrackConfig`, `RecordingIndicator`, `PlayheadTriangle` |
| `flutter_client/.../clip_item_widget.dart` | ~500 سطر — عرض الكليبات بالتدرجات + المقابض |
| `flutter_client/.../timeline_provider.dart` | ~1020 سطر — حالة التايملاين + Command Pattern + undo/redo |
| `flutter_client/.../video_player_widget.dart` | ~270 سطر — مشغل الفيديو مع الربط الثنائي |
| `flutter_client/.../backend_controller.dart` | ~180 سطر — إدارة الباك إند مع التحقق من الصحة |
| `flutter_client/.../app_theme.dart` | الثيم (داكن/فاتح) + `AppColors` |
| `flutter_client/.../timeline_models.dart` | `VideoClip`, `AudioClip`, `OverlayClip`, `SubtitleClip`, `TimelineState`, `TextClip`, `TextTrack`, `SpeedPoint`, `SpeedRamp`, `Transition` |
| `flutter_client/.../api_client.dart` | HTTP client للباك إند (Dio) |
| `flutter_client/.../local_storage.dart` | حفظ/تحميل autosave محلياً |
| `flutter_client/.../home_screen.dart` | الشاشة الرئيسية مع LayoutBuilder + resizable panels + KeyboardShortcutsWidget |
| `flutter_client/.../inspector_widget.dart` | تبويبات Inspector مع tab لكير كروم + speed ramp + keyframes |
| `flutter_client/.../inspector_shared.dart` | **جديد** — `InspectorSectionHeader`, `InspectorPropertySlider`, `InspectorNumberInput`, `InspectorPlaceholder` |
| `flutter_client/.../color_grading_panel.dart` | **جديد** — `ColorWheel`, `ColorPresets` مع 8 إعدادات جاهزة |
| `flutter_client/.../timeline_painters.dart` | **جديد** — `TrackConfig`, `RecordingIndicator`, `PlayheadTriangle` |
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
| `flutter analyze` | 0 errors, 0 warnings, 198 infos |
| `flutter test` | 55/55 passed |
| `flutter build windows --release` | نجح (58s) |
| New tests added | 18 (constants, api_result, timeline_provider) |
| GitHub Actions CI | Added `.github/workflows/flutter_ci.yml` |
| Constants refactored | `timeline_constants.dart` with 18 named constants |

### Completed
| # | Task |
|---|------|
| ✅ | README.md rewritten for Flutter Desktop + FastAPI |
| ✅ | `timeline_constants.dart` created with track heights, zoom, snap, grid, playhead constants |
| ✅ | Magic numbers replaced in `timeline_widget.dart` (track configs, zoom, sidebar, grid, snap, borders) |
| ✅ | Magic numbers replaced in `clip_item_widget.dart` (thumbnail, borders) |
| ✅ | Magic numbers replaced in `timeline_provider.dart` (zoom clamp) |
| ✅ | `ApiClient` singleton test + `ApiResult<T>` sealed class pattern matching tests |
| ✅ | `TimelineConstants` unit test (all values verified) |
| ✅ | `TimelineNotifier` unit test (setPlayhead, setZoom, clamps, undo) |
| ✅ | `TimelineStateData` copyWith unit test |
| ✅ | GitHub Actions CI workflow (analyze + test + build Windows) |
| ✅ | `pubspec.yaml` description updated |

### Remaining (Phase 2.5+)
| # | Task | Priority |
|---|------|----------|
| 1 | توحيد اسم المشروع (flutter_client → clipai) عبر الـ package | Low |
| 2 | إضافة المزيد من Widget Tests (ClipItemWidget, VideoPlayer, HomeScreen) | Medium |
| 3 | تحسينات الأداء (استخراج الـ 4 resize handlers المكررة في _buildTrackLane) | Medium |
| 4 | إضافة الترجمة (i18n) مع دعم العربية والإنجليزية | Low |
