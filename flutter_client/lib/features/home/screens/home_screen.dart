import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/native/ffmpeg_service.dart';
import '../../library/widgets/media_library_widget.dart';
import '../../wizard/auto_edit_wizard_dialog.dart' show showAutoEditWizardDialog;
import '../../player/widgets/video_player_widget.dart';
import '../../timeline/widgets/timeline_widget.dart';
import '../../inspector/widgets/inspector_widget.dart';
import '../../timeline/providers/timeline_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/plugins/plugin_system.dart';
import '../../layout/widgets/header.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/keyboard_shortcuts.dart';
import '../../../shared/widgets/ios_kit.dart';
import '../../../shared/widgets/ui_polish.dart';
import '../../layout/widgets/export_modal.dart';
import '../../layout/widgets/settings_modal.dart';
import 'package:flutter/services.dart';
import '../../../shared/providers/playback_provider.dart';
import '../../text/widgets/text_editor_dialog.dart';
import '../../ui/edge_ui.dart';
import '../../export/data/export_presets.dart';
import '../../../core/services/services.dart';
import '../../../shared/providers/layout_prefs_provider.dart';
import '../../ui/professional_ui.dart';
import '../../onboarding/onboarding_overlay.dart';
import '../widgets/welcome_hero.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedClipId;
  String _selectedClipType = 'video';
  String? _currentPreviewVideo;
  final List<MediaFile> _importedFiles = [];

  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';

  Timer? _autosaveTimer;

  bool _backendLoading = true;
  bool? _backendConnected;
  List<RecentProject> _recentProjects = const [];

  final WorkspaceManager _workspaceManager = WorkspaceManager();

  @override
  void initState() {
    super.initState();
    PluginManager();
    ServiceLocator()
      ..register<AutosaveService>(AutosaveService())
      ..register<ExportService>(ExportService());
    _loadAutosave();
    _startAutosaveTimer();
    Future.delayed(const Duration(milliseconds: 1500), _checkBackendHealth);
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  Future<void> _checkBackendHealth() async {
    if (!mounted) return;
    setState(() => _backendLoading = false);
    final result = await ApiClient().getSettings();
    if (!mounted) return;
    setState(() {
      _backendConnected = result is Success;
    });
    if (result is Success) _loadRecentProjects();
  }

  Future<void> _loadRecentProjects() async {
    final result = await ApiClient().getRecentProjects();
    if (!mounted) return;
    switch (result) {
      case Success(data: final entries):
        final projects = <RecentProject>[];
        for (final entry in entries) {
          if (entry is Map<String, dynamic>) {
            final path = entry['path'] as String?;
            if (path == null || path.isEmpty) continue;
            final name = (entry['project_name'] ?? entry['name'] ?? path.split(Platform.pathSeparator).last) as String;
            projects.add(RecentProject(name: name, path: path));
          }
        }
        setState(() => _recentProjects = projects);
      case Failure():
        break;
    }
  }

  Future<void> _loadAutosave() async {
    try {
      final data = await LocalStorage().loadAutosave();
      if (data != null && mounted) {
        final timelineData = data['timeline'] as Map<String, dynamic>?;
        if (timelineData != null) {
          final loaded = TimelineState.fromJson(timelineData);
          ref.read(timelineProvider.notifier).loadProject(loaded);
        }
        final mediaList = data['mediaFiles'] as List<dynamic>?;
        if (mediaList != null && mediaList.isNotEmpty) {
          setState(() {
            _importedFiles.clear();
            for (final m in mediaList) {
              if (m is Map<String, dynamic>) {
                _importedFiles.add(MediaFile.fromJson(m));
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Load autosave error: $e');
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _autosaveTimer?.cancel();
    if (ServiceLocator().has<AutosaveService>()) {
      ServiceLocator().get<AutosaveService>().stop();
    }
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final focusNode = FocusManager.instance.primaryFocus;
    final bool isEditing = focusNode != null &&
        (focusNode.context?.findAncestorWidgetOfExactType<EditableText>() != null ||
         focusNode.context?.widget is EditableText);
    if (isEditing) return false;

    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final key = event.logicalKey;
    final timelineNotifier = ref.read(timelineProvider.notifier);
    final timelineState = ref.read(timelineProvider).timeline;
    final playhead = timelineState.playheadSec;

    if (key == LogicalKeyboardKey.space) {
      final isPlaying = ref.read(isPlayingProvider);
      ref.read(isPlayingProvider.notifier).state = !isPlaying;
      return true;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      if (isShift) { if (timelineNotifier.canRedo) { timelineNotifier.redo(); ref.read(toastProvider.notifier).success('Redo'); } }
      else { if (timelineNotifier.canUndo) { timelineNotifier.undo(); ref.read(toastProvider.notifier).success('Undo'); } }
      return true;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyY) {
      if (timelineNotifier.canRedo) { timelineNotifier.redo(); ref.read(toastProvider.notifier).success('Redo'); }
      return true;
    }
    if (key == LogicalKeyboardKey.delete || key == LogicalKeyboardKey.backspace) {
      if (_selectedClipId != null) {
        timelineNotifier.removeClip(_selectedClipId!, _selectedClipType);
        _onSelectClip(null, 'video');
        ref.read(toastProvider.notifier).success('Clip deleted');
        return true;
      }
    }
    if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.keyC) {
      timelineNotifier.splitClipAtPlayhead(playhead);
      ref.read(toastProvider.notifier).success('Split at playhead');
      return true;
    }
    if (isCtrl && (key == LogicalKeyboardKey.equal || key == LogicalKeyboardKey.numpadAdd)) {
      timelineNotifier.setZoom(timelineState.zoomLevel + 5.0);
      return true;
    }
    if (isCtrl && (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract)) {
      timelineNotifier.setZoom(timelineState.zoomLevel - 5.0);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      timelineNotifier.setPlayhead(playhead - (isShift ? 1.0 : 0.1));
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      timelineNotifier.setPlayhead(playhead + (isShift ? 1.0 : 0.1));
      return true;
    }
    if (key == LogicalKeyboardKey.home) { timelineNotifier.setPlayhead(0.0); return true; }
    if (key == LogicalKeyboardKey.end) { timelineNotifier.setPlayhead(timelineNotifier.totalDuration); return true; }
    return false;
  }

  void _startAutosaveTimer() {
    if (!ServiceLocator().has<AutosaveService>()) return;
    final autosave = ServiceLocator().get<AutosaveService>();
    autosave.start(() => ref.read(timelineProvider).timeline, interval: const Duration(minutes: 5));
    _autosaveTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      final timelineState = ref.read(timelineProvider).timeline;
      if (timelineState.projectId.isNotEmpty && timelineState.projectId != 'project_new') {
        await autosave.saveNow(timelineState, mediaFiles: _importedFiles.map((f) => f.toJson()).toList());
      }
    });
  }

  /// The backend only accepts project saves inside the project
  /// folders — start the save dialog in Documents/Clippify/projects.
  Future<String?> _defaultSaveDir() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'Clippify', 'projects'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleSave() async {
    final timelineState = ref.read(timelineProvider).timeline;
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Project',
      fileName: '${timelineState.projectName}.clippify',
      initialDirectory: await _defaultSaveDir(),
      type: FileType.custom,
      allowedExtensions: ['clippify'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.clippify')) outputFile += '.clippify';
    final res = await ApiClient().saveProject(timelineState.toJson(), outputPath: outputFile);
    switch (res) {
      case Success(data: final data):
        if (data['status'] == 'success') {
          ref.read(toastProvider.notifier).success('تم حفظ المشروع!');
        } else {
          ref.read(toastProvider.notifier).error('فشل حفظ المشروع.');
        }
      case Failure(:final statusCode):
        if (statusCode == 403) {
          ref.read(toastProvider.notifier).error('الحفظ مسموح فقط داخل مجلد المشروع');
        } else {
          ref.read(toastProvider.notifier).error('فشل حفظ المشروع.');
        }
    }
  }

  Future<void> _handleLoad() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Project', type: FileType.custom, allowedExtensions: ['clippify'],
    );
    if (result == null || result.files.single.path == null) return;
    await _loadProjectFrom(result.files.single.path!);
  }

  Future<void> _loadProjectFrom(String path) async {
    final loadResult = await ApiClient().loadProject(path);
    switch (loadResult) {
      case Success(data: final data):
        if (data['status'] == 'success' && data['timeline'] != null) {
          final newProject = TimelineState.fromJson(data['timeline'] as Map<String, dynamic>);
          ref.read(timelineProvider.notifier).loadProject(newProject);
          ref.read(toastProvider.notifier).success('تم تحميل المشروع!');
          final videoClips = newProject.tracks.video.isNotEmpty ? newProject.tracks.video[0].clips : [];
          if (videoClips.isNotEmpty && videoClips[0].sourcePath.isNotEmpty) {
            _onSelectVideo(videoClips[0].sourcePath);
          }
        } else {
          ref.read(toastProvider.notifier).error('فشل تحميل المشروع.');
        }
      case Failure():
        ref.read(toastProvider.notifier).error('فشل تحميل المشروع.');
    }
  }

  Future<void> _importVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final name = result.files.single.name;

      double duration = 0.0;
      String? thumbPath;
      final mediaInfo = await ApiClient().getMediaInfo(path);
      switch (mediaInfo) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
            thumbPath = data['thumbnail_path'] as String?;
          }
        case Failure():
          break;
      }
      _onFileAdded(MediaFile(path: path, name: name, thumbnailPath: thumbPath, duration: duration));
      _onSelectVideo(path);
    } catch (e) {
      debugPrint('[HomeScreen] Import error: $e');
    }
  }

  Future<void> _handleNewProject() async {
    final template = await showDialog<ProjectTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('مشروع جديد', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: ProjectTemplate.all.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(ctx, t),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppColors.border, width: 0.5)),
                    child: Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(AppRadius.sm)),
                          child: Icon(t.aspectRatio == '9:16' ? Icons.phone_android_rounded : t.aspectRatio == '1:1' ? Icons.crop_square_rounded : Icons.tv_rounded, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(t.description, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                              Text('${t.width}x${t.height} \u2022 ${t.fps}fps', style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
    if (template != null) {
      final data = template.generateTimeline();
      final newProject = TimelineState.fromJson(data);
      ref.read(timelineProvider.notifier).loadProject(newProject);
      _onSelectClip(null, 'video');
      ref.read(toastProvider.notifier).success('تم إنشاء مشروع ${template.aspectRatio}');
    }
  }

  Future<void> _handleAddText() async {
    final playhead = ref.read(timelineProvider).timeline.playheadSec;
    final result = await showDialog<TextClip>(context: context, builder: (context) => const TextEditorDialog());
    if (result != null) {
      final textClip = TextClip(
        id: 'txt_${DateTime.now().millisecondsSinceEpoch}',
        text: result.text, startTime: playhead, endTime: playhead + 5.0,
        fontFamily: result.fontFamily, fontSize: result.fontSize,
        colorValue: result.colorValue, backgroundColorValue: result.backgroundColorValue,
        strokeColorValue: result.strokeColorValue, strokeWidth: result.strokeWidth,
        alignment: result.alignment, isBold: result.isBold, isItalic: result.isItalic,
        shadowBlur: result.shadowBlur, shadowColorValue: result.shadowColorValue,
        shadowOffsetX: result.shadowOffsetX, shadowOffsetY: result.shadowOffsetY,
        animationType: result.animationType, animationDuration: result.animationDuration,
      );
      ref.read(timelineProvider.notifier).addTextClip(textClip);
      ref.read(toastProvider.notifier).success('تمت إضافة النص!');
    }
  }

  void _handlePlayPause() {
    final isPlaying = ref.read(isPlayingProvider);
    ref.read(isPlayingProvider.notifier).state = !isPlaying;
  }

  void _handlePlayheadDelta(double deltaSec) {
    final current = ref.read(timelineProvider).timeline.playheadSec;
    final target = (current + deltaSec).clamp(0.0, ref.read(timelineProvider.notifier).totalDuration);
    ref.read(timelineProvider.notifier).setPlayhead(target);
  }

  void _onFileAdded(MediaFile file) {
    setState(() {
      _importedFiles.add(file);
      _currentPreviewVideo = file.path;
    });
  }
  void _onFileRemoved(int index) { setState(() { _importedFiles.removeAt(index); }); }
  void _onSelectVideo(String path) {
    setState(() => _currentPreviewVideo = path);
    final state = ref.read(timelineProvider);
    final tracks = state.timeline.tracks;
    for (final track in tracks.video) {
      if (track.clips.isNotEmpty) {
        _onSelectClip(track.clips.first.id, 'video');
        return;
      }
    }
    for (final track in tracks.audio) {
      if (track.clips.isNotEmpty) {
        _onSelectClip(track.clips.first.id, 'audio');
        return;
      }
    }
  }

  void _onSelectClip(String? clipId, String clipType) {
    setState(() { _selectedClipId = clipId; _selectedClipType = clipType; });
  }

  /// Offline AutoCut via bundled ffmpeg silencedetect. Returns true when the
  /// cut was produced locally (success OR definitive failure with feedback).
  Future<bool> _autoCutLocal() async {
    try {
      final video = _currentPreviewVideo!;
      final duration = await FfmpegService.probeDuration(video) ?? 0.0;
      if (duration <= 0) return false; // fall back to backend
      final silences = await FfmpegService.detectSilences(video);
      if (silences.isEmpty && duration < 1.0) return false;
      final speech = FfmpegService.speechSegments(silences, duration);
      if (speech.isEmpty) {
        setState(() { _isExporting = false; _exportStatus = ''; });
        ref.read(toastProvider.notifier).error('لا يوجد كلام واضح في الفيديو.');
        return true;
      }
      final List<VideoClip> newClips = [];
      for (var i = 0; i < speech.length; i++) {
        final seg = speech[i];
        newClips.add(VideoClip(
          id: 'clip_autocut_$i',
          sourcePath: video,
          startTimeInTimeline: seg['start']!,
          endTimeInTimeline: seg['end']!,
          sourceTrimStart: seg['start']!,
          sourceTrimEnd: seg['end']!,
          transform: TransformState.defaultState(),
          colorGrading: ColorGradingState(),
          filters: [],
          aiFeatures: AIFeatures(),
        ));
      }
      ref.read(timelineProvider.notifier).setClips(newClips);
      setState(() { _isExporting = false; _exportStatus = ''; });
      ref.read(toastProvider.notifier).success('✂️ ${newClips.length} مقاطع (أوفلاين)!');
      return true;
    } catch (_) {
      return false; // any local failure → backend fallback
    }
  }

  Future<void> _handleAutoCut() async {
    if (_currentPreviewVideo == null) return;
    setState(() { _isExporting = true; _exportProgress = 0.1; _exportStatus = 'Running AutoCut...'; });

    // ── STANDALONE FIRST: ffmpeg silencedetect, fully offline ──
    final localCut = await _autoCutLocal();
    if (localCut) return;

    // ── Fallback: legacy backend path (transcribe + VAD) ──
    final apiClient = ApiClient();
    final response = await apiClient.transcribe(_currentPreviewVideo!);
    late bool transcribeOk;
    switch (response) {
      case Success(data: final data):
        transcribeOk = data['status'] == 'success';
      case Failure():
        transcribeOk = false;
    }
    if (transcribeOk) {
      final cutResponse = await apiClient.detectSilence(_currentPreviewVideo!);
      switch (cutResponse) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            final silences = data['silences'] as List<dynamic>? ?? [];
            final List<VideoClip> newClips = [];
            double lastStart = 0.0;
            int index = 0;
            for (var sil in silences) {
              try {
                final startSilence = ((sil['start'] as num?) ?? 0.0).toDouble();
                final endSilence = ((sil['end'] as num?) ?? 0.0).toDouble();
                if (startSilence > lastStart) {
                  newClips.add(VideoClip(id: 'clip_autocut_$index', sourcePath: _currentPreviewVideo!,
                    startTimeInTimeline: lastStart, endTimeInTimeline: startSilence,
                    sourceTrimStart: lastStart, sourceTrimEnd: startSilence,
                    transform: TransformState.defaultState(), colorGrading: ColorGradingState(),
                    filters: [], aiFeatures: AIFeatures()));
                  index++;
                }
                lastStart = endSilence;
              } catch (_) {}
            }
            ref.read(timelineProvider.notifier).setClips(newClips);
            setState(() { _isExporting = false; _exportStatus = ''; });
            ref.read(toastProvider.notifier).success('${newClips.length} clips created!');
          } else {
            setState(() { _isExporting = false; _exportStatus = ''; });
            ref.read(toastProvider.notifier).error('AutoCut failed.');
          }
        case Failure():
          setState(() { _isExporting = false; _exportStatus = ''; });
          ref.read(toastProvider.notifier).error('AutoCut failed.');
      }
    } else {
      setState(() { _isExporting = false; _exportStatus = ''; });
      ref.read(toastProvider.notifier).error('AutoCut failed.');
    }
  }

  Future<void> _handleExport() async {
    final timelineState = ref.read(timelineProvider).timeline;
    final clips = timelineState.tracks.video.isNotEmpty ? timelineState.tracks.video[0].clips : [];
    if (clips.isEmpty) { ref.read(toastProvider.notifier).error('لا توجد مقاطع على التايملاين.'); return; }

    final settings = await showDialog<ExportSettings>(context: context, builder: (context) => const ExportModal());
    if (settings == null) return;

    if (settings.type == 'xml') {
      setState(() { _isExporting = true; _exportProgress = 0.5; _exportStatus = 'Generating XML...'; });
      final Map<String, dynamic> timelineData = timelineState.toJson();
      if (!settings.includeSubtitles) timelineData['tracks']['subtitles'] = [];
      final apiClient = ApiClient();
      final res = await apiClient.exportXml(timelineData, outputPath: settings.xmlOutputPath, format: settings.xmlFormat);
      setState(() { _isExporting = false; _exportStatus = ''; });
      if (!mounted) return;
      switch (res) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            await showIOSDialog(
              context: context,
              title: 'تم تصدير XML!',
              contentWidget: SelectableText('تم الحفظ في:\n${data['output_path']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              actions: const [IOSDialogAction('حسناً', isDefault: true)],
            );
            ref.read(toastProvider.notifier).success('تم تصدير XML!');
          } else { ref.read(toastProvider.notifier).error('فشل تصدير XML.'); }
        case Failure():
          ref.read(toastProvider.notifier).error('فشل تصدير XML.');
      }
      return;
    }

    setState(() { _isExporting = true; _exportProgress = 0.0; _exportStatus = 'Starting export...'; });
    final List<Map<String, dynamic>> clipJsonList = [];
    for (var c in clips) {
      clipJsonList.add({
        'index': clips.indexOf(c), 'start_sec': c.startTimeInTimeline, 'end_sec': c.endTimeInTimeline,
        'hook': '', 'reason': '', 'caption_theme': 'TikTok', 'zoom_style': 'none',
        'color_grade': c.colorGrading.brightness != 0 ? 'custom' : 'original',
        'emphasis_words': [], 'sfx_queries': [], 'planned_brolls': [],
        'slow_motion_start': 0.0, 'slow_motion_end': 0.0, 'slow_motion_speed': 1.0,
      });
    }
    final exportService = ServiceLocator().has<ExportService>() ? ServiceLocator().get<ExportService>() : null;
    if (exportService != null) {
      final result = await exportService.exportVideo(
        videoPath: _currentPreviewVideo ?? clips[0].sourcePath, clips: clipJsonList,
        quality: settings.exportQuality, presetName: settings.presetName,
        codec: settings.codec, pixelFormat: settings.pixelFormat,
      );
      if (!result.success) {
        setState(() { _isExporting = false; _exportStatus = 'Export failed.'; });
        ref.read(toastProvider.notifier).error(result.error ?? 'Export failed.');
        return;
      }
      if (result.sessionId != null) { _pollExportStatus(result.sessionId!); }
      else {
        ref.read(toastProvider.notifier).success('اكتمل التصدير!');
        setState(() { _isExporting = false; _exportStatus = ''; });
      }
      return;
    }
    final apiClient = ApiClient();
    final sidResult = await apiClient.renderPlan(
      videoPath: _currentPreviewVideo ?? clips[0].sourcePath, clips: clipJsonList,
      exportQuality: settings.exportQuality, exportMode: 'ffmpeg',
      presetName: settings.presetName, codec: settings.codec, pixelFormat: settings.pixelFormat,
    );
    switch (sidResult) {
      case Success(data: final sessionId):
        _pollExportStatus(sessionId);
      case Failure():
        setState(() { _isExporting = false; _exportStatus = 'Export failed.'; });
        ref.read(toastProvider.notifier).error('فشل بدء التصدير.');
    }
  }

  void _pollExportStatus(String sessionId) async {
    final apiClient = ApiClient();
    int failedAttempts = 0;
    while (_isExporting) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final statusData = await apiClient.getSessionStatus(sessionId);
      switch (statusData) {
        case Success(data: final data):
          failedAttempts = 0;
          final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
          final status = data['status'] as String? ?? '';
          final results = data['results'] as List<dynamic>? ?? [];
          final errors = data['errors'] as List<dynamic>? ?? [];
          setState(() { _exportProgress = progress; _exportStatus = status; });
          if (status.toLowerCase().startsWith('done') && results.isNotEmpty) {
            setState(() { _isExporting = false; _exportStatus = ''; });
            if (!mounted) return;
            await showIOSDialog(
              context: context,
              title: 'اكتمل التصدير!',
              contentWidget: SelectableText('تم حفظ الفيديو في:\n${results.first}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              actions: const [IOSDialogAction('حسناً', isDefault: true)],
            );
            return;
          }
          if (status.toLowerCase() == 'failed' || errors.isNotEmpty) {
            setState(() { _isExporting = false; _exportStatus = ''; });
            if (!mounted) return;
            await showIOSDialog(
              context: context,
              title: 'خطأ في التصدير',
              content: errors.isNotEmpty ? errors.join('\n') : 'خطأ في معالجة FFmpeg.',
              actions: const [IOSDialogAction('حسناً', isDefault: true)],
            );
            return;
          }
        case Failure():
          failedAttempts++;
          if (failedAttempts > 10) { setState(() { _isExporting = false; _exportStatus = ''; }); return; }
      }
    }
  }

  void _handleSettings() async {
    final result = await showDialog<bool>(context: context, builder: (context) => const SettingsModal());
    if (result == true && ServiceLocator().has<AutosaveService>()) {
      final autosave = ServiceLocator().get<AutosaveService>();
      autosave.stop();
      _startAutosaveTimer();
    }
  }

  void _handleWorkspacePreset(String id) {
    if (!mounted) return;
    _workspaceManager.switchTo(id);
    ref.read(toastProvider.notifier).info('مساحة العمل: ${_workspaceManager.current.name}');
  }

  @override
  Widget build(BuildContext context) {
    final layoutPrefs = ref.watch(layoutPrefsProvider);
    return Stack(
      children: [
        KeyboardShortcutsWidget(
          onPlayPause: _handlePlayPause,
          onForward: () => _handlePlayheadDelta(5.0),
          onRewind: () => _handlePlayheadDelta(-5.0),
          onGoStart: () => ref.read(timelineProvider.notifier).setPlayhead(0),
          onGoEnd: () { final dur = ref.read(timelineProvider.notifier).totalDuration; ref.read(timelineProvider.notifier).setPlayhead(dur); },
          onUndo: () => ref.read(timelineProvider.notifier).undo(),
          onRedo: () => ref.read(timelineProvider.notifier).redo(),
          onDelete: () {
            final state = ref.read(timelineProvider);
            if (state.timeline.tracks.video.isNotEmpty && state.timeline.tracks.video[0].clips.isNotEmpty) {
              ref.read(timelineProvider.notifier).removeVideoClip(state.timeline.tracks.video[0].clips.last.id);
            }
          },
          onSplit: () { final playhead = ref.read(timelineProvider).timeline.playheadSec; ref.read(timelineProvider.notifier).splitClipAtPlayhead(playhead); },
          onAddText: _handleAddText,
          onZoomIn: () { final current = ref.read(timelineProvider).timeline.zoomLevel; ref.read(timelineProvider.notifier).setZoom((current * 1.3).clamp(1.0, 500.0)); },
          onZoomOut: () { final current = ref.read(timelineProvider).timeline.zoomLevel; ref.read(timelineProvider.notifier).setZoom((current / 1.3).clamp(1.0, 500.0)); },
          onZoomReset: () => ref.read(timelineProvider.notifier).setZoom(30.0),
          onFullscreen: () {},
          child: Scaffold(
            body: Column(
              children: [
                // iOS navigation bar
                HeaderWidget(
                  height: layoutPrefs.headerHeight,
                  onExport: _isExporting ? null : _handleExport,
                  onSettings: _handleSettings,
                  onSave: _handleSave,
                  onLoad: _handleLoad,
                  onNewProject: _handleNewProject,
                  isExporting: _isExporting,
                  onWorkspacePreset: _handleWorkspacePreset,
                  currentWorkspaceId: _workspaceManager.currentId,
                  onUndo: () => ref.read(timelineProvider.notifier).undo(),
                  onRedo: () => ref.read(timelineProvider.notifier).redo(),
                  onSplit: () { final ph = ref.read(timelineProvider).timeline.playheadSec; ref.read(timelineProvider.notifier).splitClipAtPlayhead(ph); },
                  onSaveAs: _handleSave,
                  onCut: () { ref.read(timelineProvider.notifier).cutSelectedClips(); },
                  onCopy: () { ref.read(timelineProvider.notifier).copySelectedClips(); },
                  onPaste: () { ref.read(timelineProvider.notifier).pasteClips(); },
                  onSelectAll: () { ref.read(timelineProvider.notifier).selectAllClips(); },
                  onFullScreen: () async {
                    await windowManager.setFullScreen(!await windowManager.isFullScreen());
                  },
                  statusBadge: _buildBackendBadge(),
                ),

                // Export progress bar
                if (_isExporting)
                  LinearProgressIndicator(
                    value: _exportProgress,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(EdgeTheme.accent),
                  ),

                // Main workspace with NLE layout
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final activeVideoPath = ref.watch(timelineProvider.select((data) {
                        final playhead = data.timeline.playheadSec;
                        for (final track in data.timeline.tracks.video) {
                          for (final clip in track.clips) {
                            if (playhead >= clip.startTimeInTimeline && playhead < clip.endTimeInTimeline) {
                              return clip.sourcePath;
                            }
                          }
                        }
                        return null;
                      }));

                      final double totalWidth = constraints.maxWidth;
                      final double totalHeight = constraints.maxHeight;
                      double leftW = totalWidth * layoutPrefs.leftPanelFraction;
                      double rightW = totalWidth * layoutPrefs.rightPanelFraction;
                      double bottomH = totalHeight * layoutPrefs.timelineFraction;
                      if (leftW < 200) leftW = 200;
                      if (rightW < 200) rightW = 200;
                      if (bottomH < 200) bottomH = 200;
                      if (leftW + rightW > totalWidth - 240) {
                        double available = totalWidth - 240;
                        if (available < 0) available = 0;
                        final totalReq = leftW + rightW;
                        if (totalReq > 0) { leftW = available * (leftW / totalReq); rightW = available * (rightW / totalReq); }
                      }
                      if (bottomH > totalHeight - 120) { bottomH = totalHeight - 120; if (bottomH < 0) bottomH = 0; }

                      final topFlex = ((1 - layoutPrefs.timelineFraction) * 10).round().clamp(1, 10);
                      final bottomFlex = (layoutPrefs.timelineFraction * 10).round().clamp(1, 10);

                      return Container(
                        color: EdgeTheme.canvas,
                        padding: EdgeInsets.all(layoutPrefs.workspacePadding),
                        child: Column(
                          children: [
                            // Top row: Media | Viewer | Inspector
                            Expanded(
                              flex: topFlex,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left panel: Media Browser
                                  Container(
                                    width: leftW,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: EdgeTheme.panelBg,
                                      borderRadius: BorderRadius.circular(layoutPrefs.panelRadius),
                                      border: Border.all(color: EdgeTheme.border, width: layoutPrefs.panelBorderWidth),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: const BoxDecoration(
                                            color: EdgeTheme.toolbar,
                                            border: Border(bottom: BorderSide(color: EdgeTheme.border, width: 0.5)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.folder_rounded, size: 14, color: EdgeTheme.textSecondary),
                                              const SizedBox(width: 8),
                                              Text('مكتبة الوسائط', style: EdgeTypography.titleSmall),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                           child: MediaLibraryWidget(
                                             importedFiles: _importedFiles,
                                             onFileAdded: _onFileAdded,
                                             onFileRemoved: _onFileRemoved,
                                             onSelectVideo: _onSelectVideo,
                                             onAutoEdit: (path) => showAutoEditWizardDialog(context, videoPath: path),
                                           ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: layoutPrefs.panelGap),

                                  // Center: Viewer (full height)
                                  Expanded(
                                    child: Container(
                                      clipBehavior: Clip.antiAlias,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(layoutPrefs.panelRadius),
                                        border: Border.all(color: EdgeTheme.border, width: layoutPrefs.panelBorderWidth),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(layoutPrefs.panelRadius),
                                        child: _importedFiles.isEmpty && activeVideoPath == null
                                            ? WelcomeHero(
                                                onImportVideo: _importVideo,
                                                onOpenProject: _handleLoad,
                                                recentProjects: _recentProjects,
                                                onOpenRecent: _loadProjectFrom,
                                              )
                                            : Stack(
                                                children: [
                                                  VideoPlayerWidget(videoPath: activeVideoPath),
                                                  Positioned(
                                                    bottom: 0, left: 0, right: 0,
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        _TransportBtn(icon: Icons.first_page_rounded, onTap: () => ref.read(timelineProvider.notifier).setPlayhead(0)),
                                                        _TransportBtn(icon: Icons.skip_previous_rounded, onTap: () => _handlePlayheadDelta(-5)),
                                                        _TransportBtn(icon: Icons.play_arrow_rounded, size: 22, onTap: _handlePlayPause),
                                                        _TransportBtn(icon: Icons.skip_next_rounded, onTap: () => _handlePlayheadDelta(5)),
                                                        _TransportBtn(icon: Icons.last_page_rounded, onTap: () { final dur = ref.read(timelineProvider.notifier).totalDuration; ref.read(timelineProvider.notifier).setPlayhead(dur); }),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: layoutPrefs.panelGap),

                                  // Right panel: Inspector
                                  Container(
                                    width: rightW,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: EdgeTheme.panelBg,
                                      borderRadius: BorderRadius.circular(layoutPrefs.panelRadius),
                                      border: Border.all(color: EdgeTheme.border, width: layoutPrefs.panelBorderWidth),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          decoration: const BoxDecoration(
                                            color: EdgeTheme.toolbar,
                                            border: Border(bottom: BorderSide(color: EdgeTheme.border, width: 0.5)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.info_outline_rounded, size: 14, color: EdgeTheme.textSecondary),
                                              const SizedBox(width: 8),
                                              Text('المفتش', style: EdgeTypography.titleSmall),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: InspectorWidget(
                                            selectedClipId: _selectedClipId,
                                            selectedClipType: _selectedClipType,
                                            onAutoCut: _handleAutoCut,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: layoutPrefs.panelGap),

                            // Bottom: Timeline (full width)
                            Expanded(
                              flex: bottomFlex,
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: EdgeTheme.panelBg,
                                  borderRadius: BorderRadius.circular(layoutPrefs.panelRadius),
                                  border: Border.all(color: EdgeTheme.border, width: layoutPrefs.panelBorderWidth),
                                ),
                                child: TimelineWidget(
                                  selectedClipId: _selectedClipId,
                                  onSelectClip: _onSelectClip,
                                  onSelectVideo: _onSelectVideo,
                                  onAutoCut: _handleAutoCut,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Professional Status Bar
                Consumer(builder: (context, ref, _) {
                  final timelineData = ref.watch(timelineProvider);
                  return EdgeStatusBar(
                    currentTimecode: timelineData.timeline.playheadSec,
                    zoomLevel: timelineData.timeline.zoomLevel,
                    fps: 30,
                    isBackendConnected: _backendConnected == true,
                    isExporting: _isExporting,
                    exportProgress: _exportProgress,
                    exportStatus: _exportStatus,
                    unsavedChanges: true,
                  );
                }),
              ],
            ),
          ),
        ),
        if (_backendLoading)
          const LoadingOverlay(message: 'جاري تشغيل الباك إند...'),
        // ONBOARDING-GATE — self-gated via FirstRunGate + replay provider
        const OnboardingOverlay(),
      ],
    );
  }

  Widget _buildBackendBadge() {
    if (_backendLoading) {
      return const IOSBadge(label: 'جاري التشغيل', color: AppColors.warning);
    }
    return _backendConnected == true
        ? const IOSBadge(label: 'متصل', color: AppColors.secondary)
        : const IOSBadge(label: 'غير متصل', color: AppColors.destructive);
  }
}

class _TransportBtn extends StatelessWidget {
  final IconData icon; final double size; final VoidCallback onTap;
  const _TransportBtn({required this.icon, this.size = 16, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: IconButton(
        icon: Icon(icon, size: size, color: Colors.white),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          minimumSize: const Size(30, 30),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
