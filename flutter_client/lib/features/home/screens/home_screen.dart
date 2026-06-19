import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../library/widgets/media_library_widget.dart';
import '../../player/widgets/video_player_widget.dart';
import '../../timeline/widgets/timeline_widget.dart';
import '../../inspector/widgets/inspector_widget.dart';
import '../../timeline/providers/timeline_provider.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/plugins/plugin_system.dart';
import '../../cloud/collaboration.dart';
import '../../layout/widgets/header.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/widgets/resizable_panel.dart';
import '../../../shared/widgets/keyboard_shortcuts.dart';
import '../../layout/widgets/export_modal.dart';
import '../../layout/widgets/settings_modal.dart';
import '../../../shared/providers/theme_provider.dart';
import 'package:flutter/services.dart';
import '../../../shared/providers/playback_provider.dart';
import '../../text/widgets/text_editor_dialog.dart';
import '../../ui/edge_ui.dart';
import '../../../shared/widgets/ui_polish.dart';
import '../../export/data/export_presets.dart';
import '../../../core/services/services.dart';
import '../../capture/capture_suite.dart';
import '../../ui/professional_ui.dart';



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
  final List<String> _recordedFiles = [];

  double _leftFraction = 0.2;
  double _rightFraction = 0.25;
  double _bottomFraction = 0.45;

  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';

  Timer? _autosaveTimer;

  CollaborationManager? _collabManager;
  bool _collaborationConnected = false;

  bool _backendLoading = true;
  final WorkspaceManager _workspaceManager = WorkspaceManager();
  bool _secondScreenEnabled = false;

  bool _snapEnabled = true;

  @override
  void initState() {
    super.initState();
    PluginManager();
    ServiceLocator()
      ..register<AutosaveService>(AutosaveService())
      ..register<ExportService>(ExportService());
    _loadAutosave();
    _startAutosaveTimer();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _backendLoading = false);
    });
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
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

  Future<void> _handleSave() async {
    final timelineState = ref.read(timelineProvider).timeline;
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Project', fileName: '${timelineState.projectName}.clipai',
      type: FileType.custom, allowedExtensions: ['clipai'],
    );
    if (outputFile == null) return;
    if (!outputFile.endsWith('.clipai')) outputFile += '.clipai';
    final res = await ApiClient().saveProject(timelineState.toJson(), outputPath: outputFile);
    if (res != null && res['status'] == 'success') {
      ref.read(toastProvider.notifier).success('Project saved!');
    } else {
      ref.read(toastProvider.notifier).error('Failed to save project.');
    }
  }

  Future<void> _handleLoad() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Open Project', type: FileType.custom, allowedExtensions: ['clipai'],
    );
    if (result == null || result.files.single.path == null) return;
    final String path = result.files.single.path!;
    final data = await ApiClient().loadProject(path);
    if (data != null && data['status'] == 'success' && data['timeline'] != null) {
      final newProject = TimelineState.fromJson(data['timeline'] as Map<String, dynamic>);
      ref.read(timelineProvider.notifier).loadProject(newProject);
      ref.read(toastProvider.notifier).success('Project loaded!');
      final videoClips = newProject.tracks.video.isNotEmpty ? newProject.tracks.video[0].clips : [];
      if (videoClips.isNotEmpty && videoClips[0].sourcePath.isNotEmpty) {
        _onSelectVideo(videoClips[0].sourcePath);
      }
    } else {
      ref.read(toastProvider.notifier).error('Failed to load project.');
    }
  }

  void _handleReset() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Reset Timeline?', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
        content: const Text('All clips will be deleted.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              ref.read(timelineProvider.notifier).loadProject(TimelineState.empty());
              _onSelectClip(null, 'video');
              Navigator.pop(context);
              ref.read(toastProvider.notifier).success('Timeline reset!');
            },
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _handleNewProject() async {
    final template = await showDialog<ProjectTemplate>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New Project', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
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
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
                    child: Row(
                      children: [
                        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
        ],
      ),
    );
    if (template != null) {
      final data = template.generateTimeline();
      final newProject = TimelineState.fromJson(data);
      ref.read(timelineProvider.notifier).loadProject(newProject);
      _onSelectClip(null, 'video');
      ref.read(toastProvider.notifier).success('Project ${template.aspectRatio} created');
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
      ref.read(toastProvider.notifier).success('Text added!');
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

  void _onFileAdded(MediaFile file) { setState(() { _importedFiles.add(file); }); }
  void _onFileRemoved(int index) { setState(() { _importedFiles.removeAt(index); }); }
  void _onSelectVideo(String path) {}

  void _onSelectClip(String? clipId, String clipType) {
    setState(() { _selectedClipId = clipId; _selectedClipType = clipType; });
  }

  Future<void> _handleAutoCut() async {
    if (_currentPreviewVideo == null) return;
    setState(() { _isExporting = true; _exportProgress = 0.1; _exportStatus = 'Running AutoCut...'; });
    final apiClient = ApiClient();
    final response = await apiClient.transcribe(_currentPreviewVideo!);
    if (response != null && response['status'] == 'success') {
      final cutResponse = await apiClient.detectSilence(_currentPreviewVideo!);
      if (cutResponse != null && cutResponse['status'] == 'success') {
        final silences = cutResponse['silences'] as List<dynamic>? ?? [];
        final List<VideoClip> newClips = [];
        double lastStart = 0.0;
        int index = 0;
        for (var sil in silences) {
          final startSilence = (sil['start'] as num).toDouble();
          final endSilence = (sil['end'] as num).toDouble();
          if (startSilence > lastStart) {
            newClips.add(VideoClip(id: 'clip_autocut_$index', sourcePath: _currentPreviewVideo!,
              startTimeInTimeline: lastStart, endTimeInTimeline: startSilence,
              sourceTrimStart: lastStart, sourceTrimEnd: startSilence,
              transform: TransformState.defaultState(), colorGrading: ColorGradingState(),
              filters: [], aiFeatures: AIFeatures()));
            index++;
          }
          lastStart = endSilence;
        }
        ref.read(timelineProvider.notifier).setClips(newClips);
        setState(() { _isExporting = false; _exportStatus = ''; });
        ref.read(toastProvider.notifier).success('${newClips.length} clips created!');
      }
    } else {
      setState(() { _isExporting = false; _exportStatus = ''; });
      ref.read(toastProvider.notifier).error('AutoCut failed.');
    }
  }

  Future<void> _handleExport() async {
    final timelineState = ref.read(timelineProvider).timeline;
    final clips = timelineState.tracks.video.isNotEmpty ? timelineState.tracks.video[0].clips : [];
    if (clips.isEmpty) { ref.read(toastProvider.notifier).error('No clips on timeline.'); return; }

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
      if (res != null && res['status'] == 'success') {
        showDialog(context: context, builder: (context) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('XML Exported!', style: TextStyle(color: Colors.white, fontFamily: 'Outfit')),
          content: SelectableText('XML saved in:\n${res['output_path']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ));
        ref.read(toastProvider.notifier).success('XML exported!');
      } else { ref.read(toastProvider.notifier).error('XML export failed.'); }
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
        ref.read(toastProvider.notifier).success('Export complete!');
        setState(() { _isExporting = false; _exportStatus = ''; });
      }
      return;
    }
    final apiClient = ApiClient();
    final sessionId = await apiClient.renderPlan(
      videoPath: _currentPreviewVideo ?? clips[0].sourcePath, clips: clipJsonList,
      exportQuality: settings.exportQuality, exportMode: 'ffmpeg',
      presetName: settings.presetName, codec: settings.codec, pixelFormat: settings.pixelFormat,
    );
    if (sessionId == null) {
      setState(() { _isExporting = false; _exportStatus = 'Export failed.'; });
      ref.read(toastProvider.notifier).error('Failed to start export.');
      return;
    }
    _pollExportStatus(sessionId);
  }

  void _pollExportStatus(String sessionId) async {
    final apiClient = ApiClient();
    int failedAttempts = 0;
    while (_isExporting) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      final statusData = await apiClient.getSessionStatus(sessionId);
      if (statusData != null) {
        failedAttempts = 0;
        final progress = (statusData['progress'] as num?)?.toDouble() ?? 0.0;
        final status = statusData['status'] as String? ?? '';
        final results = statusData['results'] as List<dynamic>? ?? [];
        final errors = statusData['errors'] as List<dynamic>? ?? [];
        setState(() { _exportProgress = progress; _exportStatus = status; });
        if (status.toLowerCase().startsWith('done') && results.isNotEmpty) {
          setState(() { _isExporting = false; _exportStatus = ''; });
          if (!mounted) return;
          showDialog(context: context, builder: (context) => AlertDialog(
            title: const Text('Export Complete!', style: TextStyle(fontFamily: 'Outfit')),
            content: SelectableText('Video saved in:\n${results.first}'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ));
          break;
        }
        if (status.toLowerCase() == 'failed' || errors.isNotEmpty) {
          setState(() { _isExporting = false; _exportStatus = ''; });
          if (!mounted) return;
          showDialog(context: context, builder: (context) => AlertDialog(
            title: const Text('Export Error', style: TextStyle(fontFamily: 'Outfit')),
            content: Text(errors.isNotEmpty ? errors.join('\n') : 'FFmpeg processing error.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ));
          break;
        }
      } else {
        failedAttempts++;
        if (failedAttempts > 10) { setState(() { _isExporting = false; _exportStatus = ''; }); break; }
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
    final fractions = _workspaceManager.fractions;
    setState(() { _leftFraction = fractions['left'] ?? 0.2; _rightFraction = fractions['right'] ?? 0.25; _bottomFraction = fractions['bottom'] ?? 0.45; });
    ref.read(toastProvider.notifier).info('Workspace: ${_workspaceManager.current.name}');
  }

  void _handleThemePreset(String name) {
    if (!mounted) return;
    ref.read(appPrefsProvider.notifier).setThemePreset(name);
    ref.read(toastProvider.notifier).info('Theme: $name');
  }

  void _handleSecondScreen() {
    setState(() { _secondScreenEnabled = !_secondScreenEnabled; });
    if (_secondScreenEnabled && _currentPreviewVideo != null) {
      SecondScreenManager.openPreview(_currentPreviewVideo!);
    }
    ref.read(toastProvider.notifier).info(_secondScreenEnabled ? 'Second display on' : 'Second display off');
  }

  Future<void> _showPluginMarketplace() async {
    await showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(children: [
        const Icon(Icons.extension_rounded, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        const Text('Plugin Marketplace', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16)),
      ]),
      content: SizedBox(width: 400, height: 500,
        child: ListView.builder(
          itemCount: PluginMarketplace.availablePlugins.length,
          itemBuilder: (context, index) {
            final p = PluginMarketplace.availablePlugins[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.divider)),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] as String, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(p['description'] as String? ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(p['author'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 12),
                    const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                    Text(' ${p['rating']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 12),
                    Text('${p['downloads']} downloads', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                  child: Text(p['price'] as String, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ]),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)))],
    ));
  }

  void _toggleCollaboration() {
    final state = ref.read(timelineProvider.notifier);
    final current = ref.read(timelineProvider).timeline;
    if (!current.collaborationEnabled) {
      _collabManager = CollaborationManager(userId: 'user_${DateTime.now().millisecondsSinceEpoch}', userName: 'User');
      _collabManager!.connect('ws://localhost:8000/ws');
      setState(() => _collaborationConnected = true);
      state.updateTimelineState(current.copyWith(collaborationEnabled: true));
      ref.read(toastProvider.notifier).success('Collaboration enabled');
    } else {
      _collabManager?.dispose();
      _collabManager = null;
      setState(() => _collaborationConnected = false);
      state.updateTimelineState(current.copyWith(collaborationEnabled: false));
      ref.read(toastProvider.notifier).info('Collaboration disabled');
    }
  }

  void _showCollaborationPanel() {
    final enabled = ref.read(timelineProvider).timeline.collaborationEnabled;
    showDialog(context: context, builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(children: [
        Icon(Icons.groups_rounded, size: 20, color: enabled ? const Color(0xFF22C55E) : AppColors.textSecondary),
        const SizedBox(width: 8),
        const Text('Collaboration', style: TextStyle(color: Colors.white, fontFamily: 'Outfit', fontSize: 16)),
      ]),
      content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: _collaborationConnected ? const Color(0xFF22C55E) : AppColors.textMuted)),
          const SizedBox(width: 8),
          Text(_collaborationConnected ? 'Connected' : 'Disconnected', style: TextStyle(color: _collaborationConnected ? const Color(0xFF22C55E) : AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Switch(value: enabled, onChanged: (_) { Navigator.pop(context); _toggleCollaboration(); }, activeColor: AppColors.primary),
        ]),
        const SizedBox(height: 16),
        const Text('Connected Users', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (!enabled)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Enable collaboration to join session', style: TextStyle(color: AppColors.textMuted, fontSize: 11)))
        else
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              CircleAvatar(radius: 14, backgroundColor: AppColors.primary.withValues(alpha: 0.3), child: const Icon(Icons.person, size: 14, color: AppColors.primary)),
              const SizedBox(width: 8), const Text('You', style: TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(), const Icon(Icons.circle, size: 8, color: Color(0xFF22C55E)),
            ])),
        const SizedBox(height: 16),
        const Text('Recent Changes', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.edit_note, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            const Expanded(child: Text('No changes yet', style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
          ])),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)))],
    ));
  }

  void _handleCapture() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: CapturePanel(
          onCaptureComplete: _onCaptureComplete,
        ),
      ),
    );
  }

  void _onCaptureComplete(String filePath) {
    setState(() { _recordedFiles.add(filePath); });
    final name = filePath.split('\\').last.split('/').last;
    final media = MediaFile(path: filePath, name: name);
    _onFileAdded(media);
    ref.read(toastProvider.notifier).success('Imported: $name');
  }

  IconData _getThemeIcon(AppThemeMode mode) {
    switch (mode) { case AppThemeMode.light: return Icons.light_mode_rounded; case AppThemeMode.highContrast: return Icons.contrast_rounded; case AppThemeMode.dark: return Icons.dark_mode_rounded; }
  }

  @override
  Widget build(BuildContext context) {
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
                // Professional Menu Bar
                HeaderWidget(
                  onExport: _isExporting ? null : _handleExport,
                  onSettings: _handleSettings,
                  onThemeToggle: () { ref.read(appPrefsProvider.notifier).toggleTheme(); },
                  onSave: _handleSave,
                  onLoad: _handleLoad,
                  onReset: _handleReset,
                  onNewProject: _handleNewProject,
                  onAddText: _handleAddText,
                  onShowShortcuts: () => showDialog(context: context, builder: (_) => const ShortcutsDialog()),
                  onShowPlugins: _showPluginMarketplace,
                  onShowCollaboration: _showCollaborationPanel,
                  onCapture: _handleCapture,
                  themeIcon: _getThemeIcon(ref.watch(appPrefsProvider).themeMode),
                  isExporting: _isExporting,
                  collaborationEnabled: ref.watch(timelineProvider).timeline.collaborationEnabled,
                  onWorkspacePreset: _handleWorkspacePreset,
                  onThemePresetSelected: _handleThemePreset,
                  onSecondScreen: _handleSecondScreen,
                  currentWorkspaceId: _workspaceManager.currentId,
                  secondScreenEnabled: _secondScreenEnabled,
                  onUndo: () => ref.read(timelineProvider.notifier).undo(),
                  onRedo: () => ref.read(timelineProvider.notifier).redo(),
                  onSplit: () { final ph = ref.read(timelineProvider).timeline.playheadSec; ref.read(timelineProvider.notifier).splitClipAtPlayhead(ph); },
                  onZoomIn: () { final z = ref.read(timelineProvider).timeline.zoomLevel; ref.read(timelineProvider.notifier).setZoom((z * 1.3).clamp(1.0, 500.0)); },
                  onZoomOut: () { final z = ref.read(timelineProvider).timeline.zoomLevel; ref.read(timelineProvider.notifier).setZoom((z / 1.3).clamp(1.0, 500.0)); },
                  onSnap: () { setState(() => _snapEnabled = !_snapEnabled); },
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
                      final timelineData = ref.watch(timelineProvider);
                      final playhead = timelineData.timeline.playheadSec;
                      String? activeVideoPath;
                      for (final track in timelineData.timeline.tracks.video) {
                        for (final clip in track.clips) {
                          if (playhead >= clip.startTimeInTimeline && playhead < clip.endTimeInTimeline) {
                            activeVideoPath = clip.sourcePath; break;
                          }
                        }
                        if (activeVideoPath != null) break;
                      }

                      final double totalWidth = constraints.maxWidth;
                      final double totalHeight = constraints.maxHeight;
                      double leftW = totalWidth * _leftFraction;
                      double rightW = totalWidth * _rightFraction;
                      double bottomH = totalHeight * _bottomFraction;
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

                      return Container(
                        color: EdgeTheme.canvas,
                        child: Column(
                          children: [
                            // [Media Browser | Viewer + Timeline | Inspector]
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left panel: Media Browser
                                  Container(
                                    width: leftW,
                                    margin: const EdgeInsets.fromLTRB(4, 4, 2, 0),
                                    decoration: EdgeTheme.panelDecoration(),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 28,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: const BoxDecoration(
                                            color: EdgeTheme.toolbar,
                                            border: Border(bottom: BorderSide(color: EdgeTheme.divider)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.folder_rounded, size: 12, color: EdgeTheme.textSecondary),
                                              const SizedBox(width: 6),
                                              Text('Media Browser', style: EdgeTypography.titleSmall),
                                              const Spacer(),
                                              Icon(Icons.search_rounded, size: 12, color: EdgeTheme.textSecondary),
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          child: MediaLibraryWidget(
                                            importedFiles: _importedFiles,
                                            onFileAdded: _onFileAdded,
                                            onFileRemoved: _onFileRemoved,
                                            onSelectVideo: _onSelectVideo,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Center: Viewer + Timeline
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                                      child: Container(
                                        decoration: EdgeTheme.panelDecoration(),
                                        child: Column(
                                          children: [
                                            // Viewer
                                            Expanded(
                                              flex: 5,
                                              child: ClipRRect(
                                                borderRadius: const BorderRadius.vertical(top: Radius.circular(EdgeTheme.radiusSm)),
                                                child: Container(
                                                  color: Colors.black,
                                                  child: Stack(
                                                    children: [
                                                      VideoPlayerWidget(videoPath: activeVideoPath),
                                                      // Transport controls overlay
                                                      Positioned(
                                                        bottom: 0, left: 0, right: 0,
                                                        child: Container(
                                                          height: 36,
                                                          decoration: BoxDecoration(
                                                            gradient: LinearGradient(
                                                              begin: Alignment.bottomCenter,
                                                              end: Alignment.topCenter,
                                                              colors: [Colors.black87, Colors.transparent],
                                                            ),
                                                          ),
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
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),

                                            // Divider
                                            Container(height: 1, color: EdgeTheme.divider),

                                            // Timeline
                                            Expanded(
                                              flex: 5,
                                              child: TimelineWidget(
                                                selectedClipId: _selectedClipId,
                                                onSelectClip: _onSelectClip,
                                                onSelectVideo: _onSelectVideo,
                                                onAutoCut: _handleAutoCut,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Right panel: Inspector
                                  Container(
                                    width: rightW,
                                    margin: const EdgeInsets.fromLTRB(2, 4, 4, 0),
                                    decoration: EdgeTheme.panelDecoration(),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 28,
                                          padding: const EdgeInsets.symmetric(horizontal: 8),
                                          decoration: const BoxDecoration(
                                            color: EdgeTheme.toolbar,
                                            border: Border(bottom: BorderSide(color: EdgeTheme.divider)),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.info_outline_rounded, size: 12, color: EdgeTheme.textSecondary),
                                              const SizedBox(width: 6),
                                              Text('Inspector', style: EdgeTypography.titleSmall),
                                              const Spacer(),
                                              Icon(Icons.more_horiz_rounded, size: 12, color: EdgeTheme.textSecondary),
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
                    isBackendConnected: !_backendLoading,
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
          const LoadingOverlay(message: 'Starting backend...'),
      ],
    );
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
        icon: Icon(icon, size: size, color: Colors.white70),
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          minimumSize: const Size(28, 28),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
