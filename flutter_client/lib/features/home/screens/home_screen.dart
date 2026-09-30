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
import '../../../core/services/project_file_service.dart';
import '../../../core/export/timeline_exporter.dart';
import '../../../core/export/fcp_xml_exporter.dart';
import '../../../core/plugins/plugin_system.dart';
import '../../layout/widgets/header.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/providers/comments_provider.dart';
import '../../../shared/widgets/keyboard_shortcuts.dart';
import '../../../shared/widgets/ios_kit.dart';
import '../../../shared/widgets/ui_polish.dart';
import '../../layout/widgets/export_modal.dart';
import '../../layout/widgets/settings_modal.dart';
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

  bool _backendLoading = true;
  bool? _backendConnected;
  List<RecentProject> _recentProjects = const [];

  final WorkspaceManager _workspaceManager = WorkspaceManager();

  @override
  void initState() {
    super.initState();
    PluginManager();
    ServiceLocator().register<AutosaveService>(AutosaveService());
    _loadAutosave();
    _startAutosaveTimer();
    Future.delayed(const Duration(milliseconds: 1500), _checkBackendHealth);
  }

  Future<void> _checkBackendHealth() async {
    if (!mounted) return;
    setState(() => _backendLoading = false);
    final result = await ApiClient().getSettings();
    if (!mounted) return;
    setState(() {
      _backendConnected = result is Success;
    });
    // آخر المشاريع محلية (ProjectFileService) — لا تنتظر صحة الباك إند.
    _loadRecentProjects();
  }

  Future<void> _loadRecentProjects() async {
    final projects = await ProjectFileService().recentProjects();
    if (!mounted) return;
    setState(() => _recentProjects = projects);
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
        final commentList = data['comments'] as List<dynamic>?;
        if (commentList != null) {
          ref.read(commentsProvider.notifier).replaceAll(commentList
              .whereType<Map<String, dynamic>>()
              .map(TimelineComment.fromJson)
              .toList());
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Load autosave error: $e');
    }
  }

  @override
  void dispose() {
    if (ServiceLocator().has<AutosaveService>()) {
      ServiceLocator().get<AutosaveService>().stop();
    }
    super.dispose();
  }

  void _startAutosaveTimer() {
    if (!ServiceLocator().has<AutosaveService>()) return;
    // كاتب وحيد: خدمة autosave الدورية. (كان هناك مؤقت Timer.periodic ثانٍ
    // في هذه الصفحة يكرر الكتابة كل 5 دقائق، ويتسرّب عند إعادة التشغيل بعد
    // فتح الإعدادات لأن الحقل يُستبدل بدون cancel للمؤقت القديم.)
    ServiceLocator().get<AutosaveService>().start(
          () => ref.read(timelineProvider).timeline,
          getMediaFiles: () => _importedFiles.map((f) => f.toJson()).toList(),
          getComments: () =>
              ref.read(commentsProvider).map((c) => c.toJson()).toList(),
          interval: const Duration(minutes: 5),
        );
  }

  /// حفظ فوري لقائمة المكتبة والتعليقات عند الإضافة/الإزالة.
  void _persistMediaFiles() {
    if (!ServiceLocator().has<AutosaveService>()) return;
    ServiceLocator().get<AutosaveService>().saveNow(
          ref.read(timelineProvider).timeline,
          mediaFiles: _importedFiles.map((f) => f.toJson()).toList(),
          comments: ref.read(commentsProvider).map((c) => c.toJson()).toList(),
        );
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
    try {
      final comments =
          ref.read(commentsProvider).map((c) => c.toJson()).toList();
      await ProjectFileService()
          .saveProject(timelineState, outputFile, comments: comments);
      ref.read(timelineProvider.notifier).markSaved();
      ref.read(toastProvider.notifier).success('تم حفظ المشروع!');
      _loadRecentProjects();
    } catch (e) {
      ref.read(toastProvider.notifier).error('فشل حفظ المشروع: $e');
    }
  }

  Future<void> _handleLoad() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Project', type: FileType.custom, allowedExtensions: ['clippify'],
    );
    if (result == null || result.files.single.path == null) return;
    await _loadProjectFrom(result.files.single.path!);
  }

  Future<void> _loadProjectFrom(String path) async {
    try {
      final newProject = await ProjectFileService().loadProject(path);
      ref.read(timelineProvider.notifier).loadProject(newProject);
      final savedComments =
          await ProjectFileService().loadProjectComments(path);
      ref.read(commentsProvider.notifier).replaceAll(
          savedComments.map(TimelineComment.fromJson).toList());
      ref.read(toastProvider.notifier).success('تم تحميل المشروع!');
      final videoClips = newProject.tracks.video.isNotEmpty ? newProject.tracks.video[0].clips : [];
      if (videoClips.isNotEmpty && videoClips[0].sourcePath.isNotEmpty) {
        _onSelectVideo(videoClips[0].sourcePath);
      }
    } catch (e) {
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
      ref.read(commentsProvider.notifier).clearComments();
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
    _persistMediaFiles();
  }

  void _onFileRemoved(int index) {
    setState(() {
      _importedFiles.removeAt(index);
    });
    _persistMediaFiles();
  }
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
  ///
  /// عتبة متكيفة + دمج الضعيف: الملفات القصيرة تُكشَف بعتبة أنعم، والشذرات
  /// المشكوك فيها تذوب في جيرانها بدل أن تصبح مقاطع مبتورة.
  Future<bool> _autoCutLocal() async {
    try {
      final video = _currentPreviewVideo!;
      final duration = await FfmpegService.probeDuration(video) ?? 0.0;
      if (duration <= 0) return false; // fall back to backend
      final silences = await FfmpegService.detectSilences(video,
          minSilenceDur: FfmpegService.silenceThresholdFor(duration));
      if (silences.isEmpty && duration < 0.5) return false;
      final speech = FfmpegService.mergeWeakSpeechSegments(
          FfmpegService.speechSegments(silences, duration));
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
            // Real file length caps right-edge extension; 0 keeps it unbounded.
            double srcDur = 0.0;
            try {
              srcDur = await FfmpegService.probeDuration(_currentPreviewVideo!) ?? 0.0;
            } catch (_) {}
            final List<VideoClip> newClips = [];
            final rawSegs = <Map<String, double>>[];
            double lastStart = 0.0;
            for (var sil in silences) {
              try {
                final startSilence = ((sil['start'] as num?) ?? 0.0).toDouble();
                final endSilence = ((sil['end'] as num?) ?? 0.0).toDouble();
                if (startSilence > lastStart) {
                  rawSegs.add({'start': lastStart, 'end': startSilence});
                }
                lastStart = endSilence;
              } catch (_) {}
            }
            // الذيل بعد آخر صمت كان يُسقَط بصمت — يُحفَظ الآن مع دمج الضعيف.
            if (srcDur > 0 && lastStart < srcDur - 0.15) {
              rawSegs.add({'start': lastStart, 'end': srcDur});
            }
            final segs =
                FfmpegService.mergeWeakSpeechSegments(rawSegs);
            int index = 0;
            for (final seg in segs) {
              newClips.add(VideoClip(id: 'clip_autocut_$index', sourcePath: _currentPreviewVideo!,
                startTimeInTimeline: seg['start']!, endTimeInTimeline: seg['end']!,
                sourceTrimStart: seg['start']!, sourceTrimEnd: seg['end']!,
                sourceDuration: srcDur,
                transform: TransformState.defaultState(), colorGrading: ColorGradingState(),
                filters: [], aiFeatures: AIFeatures()));
              index++;
            }
            ref.read(timelineProvider.notifier).setClips(newClips);
            setState(() { _isExporting = false; _exportStatus = ''; });
            if (newClips.isEmpty) {
              // ملف بلا كلام واضح — لا نمسح التايملاين بنجاح وهمي.
              ref.read(toastProvider.notifier).error('لا يوجد كلام واضح في الفيديو.');
            } else {
              ref.read(toastProvider.notifier).success('${newClips.length} clips created!');
            }
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

    final settings = await showDialog<ExportSettings>(context: context, builder: (context) =>
        ExportModal(timelineSource: () => ref.read(timelineProvider).timeline));
    if (settings == null) return;

    if (settings.type == 'xml') {
      setState(() { _isExporting = true; _exportProgress = 0.3; _exportStatus = 'Generating XML...'; });
      final outPath = await _resolveExportPath(settings.xmlOutputPath, '.xml');
      final result = await writeFcpXml(
        timeline: timelineState,
        outputPath: outPath,
        includeMarkers: settings.includeSubtitles,
      );
      setState(() { _isExporting = false; _exportStatus = ''; });
      if (!mounted) return;
      if (result.success) {
        await showIOSDialog(
          context: context,
          title: 'تم تصدير XML!',
          contentWidget: SelectableText('تم الحفظ في:\n${result.outputPath}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          actions: const [IOSDialogAction('حسناً', isDefault: true)],
        );
        ref.read(toastProvider.notifier).success('تم تصدير XML!');
      } else {
        ref.read(toastProvider.notifier).error(result.error ?? 'فشل تصدير XML.');
      }
      return;
    }

    setState(() { _isExporting = true; _exportProgress = 0.0; _exportStatus = 'Starting export...'; });
    final ext = settings.presetPro?.container.extension ?? '.mp4';
    final outPath = await _resolveExportPath(settings.outputFilename, ext);
    if (outPath.isEmpty) {
      setState(() { _isExporting = false; _exportStatus = ''; });
      ref.read(toastProvider.notifier).error('اسم ملف الإخراج فارغ.');
      return;
    }
    final result = await const TimelineExporter().render(
      timeline: timelineState,
      settings: settings,
      outputPath: outPath,
      onProgress: (progress, status) {
        if (!mounted) return;
        setState(() { _exportProgress = progress; _exportStatus = status; });
      },
      isCancelled: () => !mounted || !_isExporting,
    );
    if (!mounted) return;
    setState(() { _isExporting = false; _exportStatus = ''; });
    if (result.success) {
      if (result.notes.isNotEmpty) {
        ref.read(toastProvider.notifier).info(result.notes.join('\n'));
      }
      await showIOSDialog(
        context: context,
        title: 'اكتمل التصدير!',
        contentWidget: SelectableText('تم حفظ الفيديو في:\n${result.outputPath}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        actions: const [IOSDialogAction('حسناً', isDefault: true)],
      );
      ref.read(toastProvider.notifier).success('اكتمل التصدير!');
    } else {
      await showIOSDialog(
        context: context,
        title: 'خطأ في التصدير',
        contentWidget: SelectableText(result.error ?? 'خطأ في معالجة FFmpeg.', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        actions: const [IOSDialogAction('حسناً', isDefault: true)],
      );
    }
  }

  /// اسم ملف عادي → مسار مطلق داخل Documents/Clippify/exports.
  Future<String> _resolveExportPath(String filename, String extension) async {
    final name = filename.trim();
    if (name.isEmpty) return '';
    String path;
    if (p.isAbsolute(name)) {
      path = name;
    } else {
      final docs = await getApplicationDocumentsDirectory();
      path = p.join(docs.path, 'Clippify', 'exports', p.basename(name));
    }
    if (p.extension(path).isEmpty) path = '$path$extension';
    return path;
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
    // Rebuild header/export affordances only when clip presence changes.
    final hasVideoClips = ref.watch(timelineProvider.select(
      (d) => d.timeline.tracks.video.any((t) => t.clips.isNotEmpty),
    ));
    final canUndo = ref.watch(timelineProvider.select((d) => d.undoStack.isNotEmpty));
    final canRedo = ref.watch(timelineProvider.select((d) => d.redoStack.isNotEmpty));
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
            if (_selectedClipId != null) {
              ref.read(timelineProvider.notifier).removeClip(_selectedClipId!, _selectedClipType);
              _onSelectClip(null, 'video');
              ref.read(toastProvider.notifier).success('Clip deleted');
            }
          },
          onSplit: () {
            final playhead = ref.read(timelineProvider).timeline.playheadSec;
            if (ref.read(timelineProvider.notifier).splitClipAtPlayhead(playhead)) {
              ref.read(toastProvider.notifier).success('Split at playhead');
            } else {
              ref.read(toastProvider.notifier).info('لا يوجد مقطع تحت المؤشر');
            }
          },
          onSave: _handleSave,
          onSaveAs: _handleSave,
          onSettings: _handleSettings,
          onOpen: _handleLoad,
          onNew: _handleNewProject,
          onExport: (_isExporting || !hasVideoClips) ? null : _handleExport,
          onCopy: () {
            final id = _selectedClipId;
            if (id == null) {
              ref.read(toastProvider.notifier).info('اختر مقطعًا أولاً');
              return;
            }
            ref.read(timelineProvider.notifier).copySelectedClips(selectedIds: {id});
            ref.read(toastProvider.notifier).success('تم النسخ');
          },
          onCut: () {
            final id = _selectedClipId;
            if (id == null) {
              ref.read(toastProvider.notifier).info('اختر مقطعًا أولاً');
              return;
            }
            ref.read(timelineProvider.notifier).cutSelectedClips(selectedIds: {id});
            _onSelectClip(null, 'video');
            ref.read(toastProvider.notifier).success('تم القص');
          },
          onPaste: () {
            final notifier = ref.read(timelineProvider.notifier);
            if (!notifier.hasClipboard) {
              ref.read(toastProvider.notifier).info('لا يوجد شيء للصق');
              return;
            }
            notifier.pasteClips();
            ref.read(toastProvider.notifier).success('تم اللصق');
          },
          onSelectAll: () => ref.read(timelineProvider.notifier).selectAllClips(),
          onShowShortcuts: () => showDialog(
              context: context,
              builder: (_) => const ShortcutsDialog()),
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
                  onExport: (_isExporting || !hasVideoClips) ? null : _handleExport,
                  onSettings: _handleSettings,
                  onSave: _handleSave,
                  onLoad: _handleLoad,
                  onNewProject: _handleNewProject,
                  isExporting: _isExporting,
                  onWorkspacePreset: _handleWorkspacePreset,
                  currentWorkspaceId: _workspaceManager.currentId,
                  onUndo: canUndo ? () => ref.read(timelineProvider.notifier).undo() : null,
                  onRedo: canRedo ? () => ref.read(timelineProvider.notifier).redo() : null,
                  onSaveAs: _handleSave,
                  onCut: () { ref.read(timelineProvider.notifier).cutSelectedClips(); },
                  onCopy: () { ref.read(timelineProvider.notifier).copySelectedClips(); },
                  onPaste: () { ref.read(timelineProvider.notifier).pasteClips(); },
                  onSelectAll: () { ref.read(timelineProvider.notifier).selectAllClips(); },
                  onFullScreen: () async {
                    await windowManager.setFullScreen(!await windowManager.isFullScreen());
                  },
                  onShowShortcuts: () => showDialog(
                      context: context,
                      builder: (_) => const ShortcutsDialog()),
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
                                        child: _buildViewer(activeVideoPath, hasVideoClips),
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
                    unsavedChanges: timelineData.isDirty,
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

  /// Viewer body with contextual empty states:
  /// - truly empty project → WelcomeHero
  /// - clip under playhead with an empty/missing source → "media offline" hint
  /// - clips exist but playhead sits in a gap → "move playhead" hint
  Widget _buildViewer(String? activeVideoPath, bool hasVideoClips) {
    final showWelcome = _importedFiles.isEmpty &&
        activeVideoPath == null &&
        !hasVideoClips;
    if (showWelcome) {
      return WelcomeHero(
        onImportVideo: _importVideo,
        onOpenProject: _handleLoad,
        recentProjects: _recentProjects,
        onOpenRecent: _loadProjectFrom,
      );
    }
    String? emptyLabel;
    if (activeVideoPath != null && activeVideoPath.isEmpty) {
      emptyLabel = 'ملف المقطع مفقود — أعد استيراده من المكتبة';
    } else if (hasVideoClips) {
      emptyLabel = 'حرّك المؤشر فوق مقطع للمعاينة';
    }
    return VideoPlayerWidget(
      videoPath: activeVideoPath,
      emptyLabel: emptyLabel,
      onImportPressed: _importVideo,
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
