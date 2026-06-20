import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/timeline_provider.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/timeline_constants.dart';
import 'clip_item_widget.dart';
import 'text_clip_item_widget.dart';
import 'transition_picker.dart';
import 'timeline_painters.dart';
import '../../text/widgets/text_editor_dialog.dart';
import '../../../shared/providers/macro_provider.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../core/api/api_client.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../../shared/widgets/advanced_gestures.dart';


class TimelineWidget extends ConsumerStatefulWidget {
  final String? selectedClipId;
  final Function(String?, String) onSelectClip;
  final Function(String)? onSelectVideo;
  final VoidCallback? onAutoCut;
  final VoidCallback? onAutoFrame;
  final bool isLoading;

  const TimelineWidget({
    super.key,
    required this.selectedClipId,
    required this.onSelectClip,
    this.onSelectVideo,
    this.onAutoCut,
    this.onAutoFrame,
    this.isLoading = false,
  });

  @override
  ConsumerState<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends ConsumerState<TimelineWidget> {
  final ScrollController _scrollController = ScrollController();
  double _scaleStartZoom = TimelineConstants.defaultZoom;

  final Set<String> _mutedTracks = {};
  final Set<String> _lockedTracks = {};
  final Set<String> _hiddenTracks = {};
  final Set<String> _selectedClipIds = {};
  double? _snapLinePositionSec;
  bool _isDraggingClip = false;
  bool _isRippleEnabled = false;

  bool _isZooming = false;
  bool _isCtrlPressed = false;

  double? _zoomAnchorSec;
  double? _zoomAnchorViewportX;

  List<Widget> _buildAllSidebarTracks(Tracks tracks, {List<NestedSequence> nestedSequences = const []}) {
    final widgets = <Widget>[];
    final configs = _getTrackConfigs(tracks, nestedSequences: nestedSequences);
    for (int i = 0; i < configs.length; i++) {
      final cfg = configs[i];
      widgets.add(_buildTrackSidebar(
        title: cfg.name,
        icon: cfg.icon,
        trackType: cfg.type,
        height: cfg.height,
      ));
      if (i < configs.length - 1) {
        widgets.add(const SizedBox(height: TimelineConstants.trackGap));
      }
    }
    return widgets;
  }

  List<Widget> _buildAllTrackLanes(Tracks tracks, double zoomLevel, {List<NestedSequence> nestedSequences = const []}) {
    final lanes = <Widget>[];
    final configs = _getTrackConfigs(tracks, nestedSequences: nestedSequences);
    for (final cfg in configs) {
      if (lanes.isNotEmpty) lanes.add(const SizedBox(height: TimelineConstants.trackGap));
      lanes.add(_buildTrackLane(
        title: cfg.name,
        color: cfg.color,
        icon: cfg.icon,
        clips: cfg.clips,
        zoomLevel: zoomLevel,
        trackType: cfg.type,
        height: cfg.height,
      ));
    }
    lanes.add(const SizedBox(height: TimelineConstants.tracksBottomPadding));
    return lanes;
  }

  List<TrackConfig> _getTrackConfigs(Tracks tracks, {List<NestedSequence> nestedSequences = const []}) {
    final configs = <TrackConfig>[];
    for (final track in tracks.video) {
      configs.add(TrackConfig(
        name: track.name,
        icon: Icons.videocam_outlined,
        color: TimelineConstants.videoTrackColor.withValues(alpha: 0.06),
        clips: track.clips, type: 'video',
        height: TimelineConstants.videoTrackHeight,
      ));
    }
    for (final track in tracks.audio) {
      configs.add(TrackConfig(
        name: track.name,
        icon: Icons.mic_outlined,
        color: TimelineConstants.audioTrackColor.withValues(alpha: 0.06),
        clips: track.clips, type: 'audio',
        height: TimelineConstants.audioTrackHeight,
      ));
    }
    for (final track in tracks.overlays) {
      configs.add(TrackConfig(
        name: 'Overlay ${tracks.overlays.indexOf(track)}',
        icon: Icons.layers_outlined,
        color: TimelineConstants.overlayTrackColor.withValues(alpha: 0.06),
        clips: track.clips, type: 'overlay',
        height: TimelineConstants.overlayTrackHeight,
      ));
    }
    for (final track in tracks.subtitles) {
      configs.add(TrackConfig(
        name: 'Subtitle ${tracks.subtitles.indexOf(track)}',
        icon: Icons.subtitles_outlined,
        color: TimelineConstants.subtitleTrackColor.withValues(alpha: 0.06),
        clips: track.clips, type: 'subtitle',
        height: TimelineConstants.subtitleTrackHeight,
      ));
    }
    for (final track in tracks.text) {
      configs.add(TrackConfig(
        name: 'Text ${tracks.text.indexOf(track)}',
        icon: Icons.text_fields,
        color: TimelineConstants.textTrackColor.withValues(alpha: 0.06),
        clips: track.clips, type: 'text',
        height: TimelineConstants.textTrackHeight,
      ));
    }
    for (final ns in nestedSequences) {
      configs.add(TrackConfig(
        name: ns.name,
        icon: Icons.subdirectory_arrow_right,
        color: TimelineConstants.nestedTrackColor.withValues(alpha: 0.06),
        clips: [ns],
        type: 'nested',
        height: TimelineConstants.nestedTrackHeight,
      ));
    }
    return configs;
  }

  final ValueNotifier<double> _playheadScrubNotifier = ValueNotifier(0.0);
  bool _isScrubbing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    final isCtrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (isCtrl != _isCtrlPressed) {
      if (mounted) {
        setState(() {
          _isCtrlPressed = isCtrl;
        });
      }
    }
    if (event is KeyDownEvent && isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
      _handleSelectAll();
      return true;
    }
    return false;
  }

  void _handleSelectAll() {
    final state = ref.read(timelineProvider).timeline;
    setState(() {
      _selectedClipIds.clear();
      for (final track in state.tracks.video) {
        for (final c in track.clips) {
          _selectedClipIds.add(c.id);
        }
      }
      for (final track in state.tracks.audio) {
        for (final c in track.clips) {
          _selectedClipIds.add(c.id);
        }
      }
      for (final track in state.tracks.overlays) {
        for (final c in track.clips) {
          _selectedClipIds.add(c.id);
        }
      }
      for (final track in state.tracks.subtitles) {
        for (final c in track.clips) {
          _selectedClipIds.add(c.id);
        }
      }
      for (final track in state.tracks.text) {
        for (final c in track.clips) {
          _selectedClipIds.add(c.id);
        }
      }
    });
  }

  ScrollPhysics get _scrollPhysics {
    if (_isZooming || _isCtrlPressed) {
      return const NeverScrollableScrollPhysics();
    }
    return const ClampingScrollPhysics();
  }

  String _formatTimecode(double totalSeconds) {
    final int minutes = (totalSeconds / 60).floor();
    final int seconds = (totalSeconds % 60).floor();
    final int frames = ((totalSeconds % 1) * 30).floor();
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  double _getSecondsFromX(double localX, double zoomLevel) {
    final double seconds = localX / zoomLevel;
    return seconds.clamp(0.0, double.infinity);
  }

  void _handleScrubbing(Offset localPosition, double zoomLevel, double maxDuration) {
    if (!_isScrubbing) {
      _playheadScrubNotifier.value = ref.read(timelineProvider).timeline.playheadSec;
    }
    _isScrubbing = true;
    final double seconds = _getSecondsFromX(localPosition.dx, zoomLevel);
    final double clamped = seconds.clamp(0.0, maxDuration);
    _playheadScrubNotifier.value = clamped;
    ref.read(scrubPlayheadProvider.notifier).state = clamped;
  }

  void _commitScrub() {
    if (!_isScrubbing) return;
    _isScrubbing = false;
    ref.read(timelineProvider.notifier).setPlayhead(_playheadScrubNotifier.value);
  }

  OverlayClip? _findOverlayClipById(String clipId) {
    final t = ref.read(timelineProvider).timeline;
    for (var track in t.tracks.overlays) {
      for (var c in track.clips) {
        if (c.id == clipId) return c;
      }
    }
    return null;
  }

  SubtitleClip? _findSubtitleClipById(String clipId) {
    final t = ref.read(timelineProvider).timeline;
    for (var track in t.tracks.subtitles) {
      for (var c in track.clips) {
        if (c.id == clipId) return c;
      }
    }
    return null;
  }

  TextClip? _findTextClipById(String clipId) {
    final t = ref.read(timelineProvider).timeline;
    for (var track in t.tracks.text) {
      for (var c in track.clips) {
        if (c.id == clipId) return c;
      }
    }
    return null;
  }

  void _handleClipMove(String clipId, double deltaSec, double zoomLevel, double playhead) {
    final notifier = ref.read(timelineProvider.notifier);
    dynamic cur;
    double start = 0, end = 0;
    void Function(String, double) moveFn = notifier.moveVideoClip;

    cur = _findClipById(clipId);
    if (cur != null) { start = cur.startTimeInTimeline; end = cur.endTimeInTimeline; moveFn = notifier.moveVideoClip; }
    if (cur == null) { cur = _findAudioClipById(clipId); if (cur != null) { start = cur.startTimeInTimeline; end = cur.endTimeInTimeline; moveFn = notifier.moveAudioClip; } }
    if (cur == null) { cur = _findOverlayClipById(clipId); if (cur != null) { start = cur.startTimeInTimeline; end = cur.endTimeInTimeline; moveFn = notifier.moveOverlayClip; } }
    if (cur == null) { cur = _findSubtitleClipById(clipId); if (cur != null) { start = cur.startTime; end = cur.endTime; moveFn = notifier.moveSubtitleClip; } }
    if (cur == null) return;

    final targetStart = start + deltaSec;
    final snapped = _getSnappedOffset(targetStart, end - start, clipId, zoomLevel, playhead);
    moveFn(clipId, snapped);
  }

  void _handleClipResizeLeft(String clipId, double deltaSec, double zoomLevel, double playhead) {
    final notifier = ref.read(timelineProvider.notifier);
    dynamic cur;
    double start = 0;
    void Function(String, double) resizeFn = notifier.resizeVideoClipLeft;

    cur = _findClipById(clipId);
    if (cur != null) { start = cur.startTimeInTimeline; resizeFn = notifier.resizeVideoClipLeft; }
    if (cur == null) { cur = _findAudioClipById(clipId); if (cur != null) { start = cur.startTimeInTimeline; resizeFn = notifier.resizeAudioClipLeft; } }
    if (cur == null) { cur = _findOverlayClipById(clipId); if (cur != null) { start = cur.startTimeInTimeline; resizeFn = notifier.resizeOverlayClipLeft; } }
    if (cur == null) { cur = _findSubtitleClipById(clipId); if (cur != null) { start = cur.startTime; resizeFn = notifier.resizeSubtitleClipLeft; } }
    if (cur == null) return;

    final targetStart = start + deltaSec;
    final toleranceSec = TimelineConstants.snapTolerancePixels / zoomLevel;
    final snapPoints = [0.0, playhead];
    double snappedStart = targetStart;
    double minDiff = toleranceSec;
    double? snapLine;
    for (final point in snapPoints) {
      final diff = (targetStart - point).abs();
      if (diff < minDiff) { minDiff = diff; snappedStart = point; snapLine = point; }
    }
    setState(() => _snapLinePositionSec = snapLine);
    resizeFn(clipId, snappedStart);
  }

  void _handleClipResizeRight(String clipId, double deltaSec, double zoomLevel, double playhead) {
    final notifier = ref.read(timelineProvider.notifier);
    dynamic cur;
    double end = 0;
    void Function(String, double) resizeFn = notifier.resizeVideoClip;

    cur = _findClipById(clipId);
    if (cur != null) { end = cur.endTimeInTimeline; resizeFn = notifier.resizeVideoClip; }
    if (cur == null) { cur = _findAudioClipById(clipId); if (cur != null) { end = cur.endTimeInTimeline; resizeFn = notifier.resizeAudioClip; } }
    if (cur == null) { cur = _findOverlayClipById(clipId); if (cur != null) { end = cur.endTimeInTimeline; resizeFn = notifier.resizeOverlayClip; } }
    if (cur == null) { cur = _findSubtitleClipById(clipId); if (cur != null) { end = cur.endTime; resizeFn = notifier.resizeSubtitleClip; } }
    if (cur == null) return;

    final targetEnd = end + deltaSec;
    final toleranceSec = TimelineConstants.snapTolerancePixels / zoomLevel;
    final snapPoints = [0.0, playhead];
    double snappedEnd = targetEnd;
    double minDiff = toleranceSec;
    double? snapLine;
    for (final point in snapPoints) {
      final diff = (targetEnd - point).abs();
      if (diff < minDiff) { minDiff = diff; snappedEnd = point; snapLine = point; }
    }
    setState(() => _snapLinePositionSec = snapLine);
    resizeFn(clipId, snappedEnd);
  }

  void _showClipContextMenu(BuildContext context, String clipId, String trackType, String clipType) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(0, 0, 0, 0),
      items: [
        PopupMenuItem(value: 'split_spacer', enabled: false, child: Text('قص', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))),
        const PopupMenuItem(value: 'split', child: ListTile(
          leading: Icon(Icons.content_cut, size: 18, color: AppColors.primary),
          title: Text('قص عند المؤشر (Ctrl+S)', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'nest_as_sequence', child: ListTile(
          leading: Icon(Icons.subdirectory_arrow_right, size: 18, color: AppColors.primary),
          title: Text('تجميع كتسلسل متداخل', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: ListTile(
          leading: Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
          title: Text('حذف (Delete)', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'speed', enabled: false, child: Text('سرعة', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))),
        if (clipType != 'subtitle')
        const PopupMenuItem(value: 'speed_200', child: ListTile(
          leading: Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
          title: Text('2x سرعة', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        if (clipType != 'subtitle')
        const PopupMenuItem(value: 'speed_100', child: ListTile(
          leading: Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
          title: Text('1x سرعة (عادي)', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        if (clipType != 'subtitle')
        const PopupMenuItem(value: 'speed_050', child: ListTile(
          leading: Icon(Icons.speed, size: 18, color: AppColors.textSecondary),
          title: Text('0.5x سرعة (بطيء)', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'properties', child: ListTile(
          leading: Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
          title: Text('خصائص', style: TextStyle(fontSize: 12)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        )),
      ],
    ).then((value) {
      if (value == null) return;
      final notifier = ref.read(timelineProvider.notifier);
      final playhead = ref.read(timelineProvider).timeline.playheadSec;

      switch (value) {
        case 'split':
          notifier.splitClipAtPlayhead(playhead);
          break;
        case 'nest_as_sequence':
          _nestSelectedClips();
          break;
        case 'delete':
          if (_selectedClipIds.isNotEmpty && _selectedClipIds.contains(clipId)) {
            for (final id in _selectedClipIds.toList()) {
              _deleteClipById(id);
            }
            _selectedClipIds.clear();
          } else {
            _deleteClipById(clipId);
          }
          widget.onSelectClip(null, 'video');
          break;
        case 'speed_200':
          if (trackType == 'video') notifier.updateVideoClip(clipId, (c) => c.copyWith(speed: 2.0));
          break;
        case 'speed_100':
          if (trackType == 'video') notifier.updateVideoClip(clipId, (c) => c.copyWith(speed: 1.0));
          break;
        case 'speed_050':
          if (trackType == 'video') notifier.updateVideoClip(clipId, (c) => c.copyWith(speed: 0.5));
          break;
      }
    });
  }

  void _nestSelectedClips() {
    final ids = _selectedClipIds.isNotEmpty ? _selectedClipIds.toSet() : <String>{};
    if (ids.isEmpty && widget.selectedClipId != null) {
      ids.add(widget.selectedClipId!);
    }
    if (ids.isEmpty) return;
    ref.read(timelineProvider.notifier).nestSelectedClips(ids);
    setState(() => _selectedClipIds.clear());
    widget.onSelectClip(null, 'video');
    ref.read(toastProvider.notifier).success('تم إنشاء تسلسل متداخل');
  }

  void _deleteClipById(String clipId) {
    final notifier = ref.read(timelineProvider.notifier);
    final state = ref.read(timelineProvider).timeline;
    double? clipStart;
    double? clipEnd;

    for (final track in state.tracks.video) {
      for (final c in track.clips) {
        if (c.id == clipId) { clipStart = c.startTimeInTimeline; clipEnd = c.endTimeInTimeline; notifier.removeVideoClip(clipId); break; }
      }
    }
    for (final track in state.tracks.audio) {
      for (final c in track.clips) {
        if (c.id == clipId) { clipStart = c.startTimeInTimeline; clipEnd = c.endTimeInTimeline; notifier.removeAudioClip(clipId); break; }
      }
    }
    for (final track in state.tracks.overlays) {
      for (final c in track.clips) {
        if (c.id == clipId) { clipStart = c.startTimeInTimeline; clipEnd = c.endTimeInTimeline; notifier.removeOverlayClip(clipId); break; }
      }
    }
    for (final track in state.tracks.subtitles) {
      for (final c in track.clips) {
        if (c.id == clipId) { clipStart = c.startTime; clipEnd = c.endTime; notifier.removeSubtitleClip(clipId); break; }
      }
    }
    for (final track in state.tracks.text) {
      for (final c in track.clips) {
        if (c.id == clipId) { clipStart = c.startTime; clipEnd = c.endTime; notifier.removeTextClip(clipId); break; }
      }
    }

    if (_isRippleEnabled && clipStart != null && clipEnd != null) {
      final duration = clipEnd - clipStart;
      _rippleShiftClips(clipStart, -duration);
    }
  }

  void _rippleShiftClips(double afterTime, double deltaSec) {
    final notifier = ref.read(timelineProvider.notifier);
    final state = ref.read(timelineProvider).timeline;

    for (final track in state.tracks.video) {
      for (final c in track.clips) {
        if (c.startTimeInTimeline >= afterTime) {
          notifier.moveVideoClip(c.id, c.startTimeInTimeline + deltaSec);
        }
      }
    }
    for (final track in state.tracks.audio) {
      for (final c in track.clips) {
        if (c.startTimeInTimeline >= afterTime) {
          notifier.moveAudioClip(c.id, c.startTimeInTimeline + deltaSec);
        }
      }
    }
    for (final track in state.tracks.overlays) {
      for (final c in track.clips) {
        if (c.startTimeInTimeline >= afterTime) {
          notifier.moveOverlayClip(c.id, c.startTimeInTimeline + deltaSec);
        }
      }
    }
    for (final track in state.tracks.subtitles) {
      for (final c in track.clips) {
        if (c.startTime >= afterTime) {
          notifier.moveSubtitleClip(c.id, c.startTime + deltaSec);
        }
      }
    }
    for (final track in state.tracks.text) {
      for (final c in track.clips) {
        if (c.startTime >= afterTime) {
          notifier.updateTextClip(c.id, (clip) => clip.copyWith(startTime: clip.startTime + deltaSec, endTime: clip.endTime + deltaSec));
        }
      }
    }
  }

  double _getSnappedOffset(double targetStart, double clipDuration, String excludeClipId, double zoomLevel, double playheadSec) {
    final double toleranceSec = TimelineConstants.snapTolerancePixels / zoomLevel;
    final List<double> snapPoints = [0.0, playheadSec];

    final timelineState = ref.read(timelineProvider).timeline;

    // Snap to grid lines
    for (double g = 0; g <= ref.read(timelineProvider.notifier).totalDuration; g += TimelineConstants.gridIntervalSec.toDouble()) {
      snapPoints.add(g);
    }

    // Snap to text clips
    for (var track in timelineState.tracks.text) {
      for (var c in track.clips) {
        if (c.id != excludeClipId) {
          snapPoints.add(c.startTime);
          snapPoints.add(c.endTime);
        }
      }
    }

    for (var track in timelineState.tracks.video) {
      for (var c in track.clips) {
        if (c.id != excludeClipId) {
          snapPoints.add(c.startTimeInTimeline);
          snapPoints.add(c.endTimeInTimeline);
        }
      }
    }
    for (var track in timelineState.tracks.audio) {
      for (var c in track.clips) {
        if (c.id != excludeClipId) {
          snapPoints.add(c.startTimeInTimeline);
          snapPoints.add(c.endTimeInTimeline);
        }
      }
    }
    for (var track in timelineState.tracks.overlays) {
      for (var c in track.clips) {
        if (c.id != excludeClipId) {
          snapPoints.add(c.startTimeInTimeline);
          snapPoints.add(c.endTimeInTimeline);
        }
      }
    }
    for (var track in timelineState.tracks.subtitles) {
      for (var c in track.clips) {
        if (c.id != excludeClipId) {
          snapPoints.add(c.startTime);
          snapPoints.add(c.endTime);
        }
      }
    }

    double bestSnappedStart = targetStart;
    double minDiff = toleranceSec;
    double? snappedPoint;

    for (final point in snapPoints) {
      final diff = (targetStart - point).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestSnappedStart = point;
        snappedPoint = point;
      }
    }

    final double targetEnd = targetStart + clipDuration;
    for (final point in snapPoints) {
      final diff = (targetEnd - point).abs();
      if (diff < minDiff) {
        minDiff = diff;
        bestSnappedStart = point - clipDuration;
        snappedPoint = point;
      }
    }

    setState(() {
      _snapLinePositionSec = snappedPoint;
    });

    return bestSnappedStart;
  }

  @override
  Widget build(BuildContext context) {
    final timelineData = ref.watch(timelineProvider);
    final timelineNotifier = ref.read(timelineProvider.notifier);

    final timelineState = timelineData.timeline;
    final double zoomLevel = timelineState.zoomLevel;
    final double maxDuration = timelineNotifier.totalDuration;

    if ((_playheadScrubNotifier.value - timelineState.playheadSec).abs() > 0.001) {
      _playheadScrubNotifier.value = timelineState.playheadSec;
    }

    ref.listen<double>(timelineProvider.select((value) => value.timeline.zoomLevel), (oldZoom, newZoom) {
      if (oldZoom != null && oldZoom != newZoom && _scrollController.hasClients) {
        double scrollOffset = 0.0;
        double viewportWidth = 1000.0;
        try {
          scrollOffset = _scrollController.offset;
          if (_scrollController.position.hasContentDimensions) {
            viewportWidth = _scrollController.position.viewportDimension;
          }
        } catch (_) {}

        double targetScroll = scrollOffset;

        if (_zoomAnchorSec != null && _zoomAnchorViewportX != null) {
          targetScroll = _zoomAnchorSec! * newZoom - _zoomAnchorViewportX!;
        } else {
          final double playheadX = ref.read(timelineProvider).timeline.playheadSec * oldZoom;
          final bool isPlayheadVisible = playheadX >= scrollOffset && playheadX <= (scrollOffset + viewportWidth);

          if (isPlayheadVisible) {
            targetScroll = scrollOffset + ref.read(timelineProvider).timeline.playheadSec * (newZoom - oldZoom);
          } else {
            final double centerSec = (scrollOffset + viewportWidth / 2) / oldZoom;
            targetScroll = centerSec * newZoom - viewportWidth / 2;
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final maxScroll = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(targetScroll.clamp(0.0, maxScroll));
            _zoomAnchorSec = null;
            _zoomAnchorViewportX = null;
          }
        });
      }
    });

    ref.listen<double>(timelineProvider.select((value) => value.timeline.playheadSec), (oldPlayhead, newPlayhead) {
      if (mounted && !_isScrubbing) {
        _playheadScrubNotifier.value = newPlayhead;
        ref.read(scrubPlayheadProvider.notifier).state = newPlayhead;
      }
      if (_isScrubbing) return;
      if (_scrollController.hasClients) {
        final double currentZoom = ref.read(timelineProvider).timeline.zoomLevel;
        final double playheadX = newPlayhead * currentZoom;
        double scrollOffset = 0.0;
        double viewportWidth = 1000.0;
        try {
          scrollOffset = _scrollController.offset;
          if (_scrollController.position.hasContentDimensions) {
            viewportWidth = _scrollController.position.viewportDimension;
          }
        } catch (_) {}

        if (playheadX > scrollOffset + viewportWidth - 60.0 || playheadX < scrollOffset + 120.0) {
          final double targetScroll = playheadX - (viewportWidth / 2);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              final maxScroll = _scrollController.position.maxScrollExtent;
              _scrollController.jumpTo(targetScroll.clamp(0.0, maxScroll));
            }
          });
        }
      }
    });

    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          _buildToolbar(timelineData, timelineNotifier),

          Expanded(
            child: DragSelectionHandler(
              enabled: false, // toggle via toolbar in future
              onSelectionEnd: (rect) {},
              child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSidebarColumn(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Listener(
                  onPointerPanZoomStart: (event) {
                    _scaleStartZoom = ref.read(timelineProvider).timeline.zoomLevel;
                    final double localX = event.localPosition.dx;
                    _zoomAnchorViewportX = localX;
                    double scrollOffset = 0.0;
                    if (_scrollController.hasClients) {
                      try {
                        scrollOffset = _scrollController.offset;
                      } catch (_) {}
                    }
                    _zoomAnchorSec = (localX + scrollOffset) / _scaleStartZoom;
                  },
                  onPointerPanZoomUpdate: (event) {
                    if (event.scale != 1.0) {
                      setState(() {
                        _isZooming = true;
                      });
                      final double localX = event.localPosition.dx;
                      _zoomAnchorViewportX = localX;
                      double scrollOffset = 0.0;
                      if (_scrollController.hasClients) {
                        try {
                          scrollOffset = _scrollController.offset;
                        } catch (_) {}
                      }
                      _zoomAnchorSec = (localX + scrollOffset) / ref.read(timelineProvider).timeline.zoomLevel;

                      final double newZoom = (_scaleStartZoom * event.scale).clamp(TimelineConstants.minZoom, TimelineConstants.maxZoom);
                      ref.read(timelineProvider.notifier).setZoom(newZoom);
                    } else {
                      if (_scrollController.hasClients) {
                        final double dx = event.panDelta.dx;
                        final double newOffset = _scrollController.offset - dx;
                        _scrollController.jumpTo(newOffset.clamp(0.0, _scrollController.position.maxScrollExtent));
                      }
                    }
                  },
                  onPointerPanZoomEnd: (event) {
                    setState(() {
                      _isZooming = false;
                    });
                  },
                  onPointerSignal: (pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      final bool isCtrlPressed = HardwareKeyboard.instance.isControlPressed ||
                          HardwareKeyboard.instance.isMetaPressed;
                      if (isCtrlPressed) {
                        final double currentZoom = ref.read(timelineProvider).timeline.zoomLevel;
                        final double dy = pointerSignal.scrollDelta.dy;
                        if (dy != 0) {
                          final double localX = pointerSignal.localPosition.dx;
                          _zoomAnchorViewportX = localX;
                          double scrollOffset = 0.0;
                          if (_scrollController.hasClients) {
                            try {
                              scrollOffset = _scrollController.offset;
                            } catch (_) {}
                          }
                          _zoomAnchorSec = (localX + scrollOffset) / currentZoom;

                          final double speedFactor = 1.0 + (dy.abs() * 0.0015).clamp(0.005, 0.15);
                          final double zoomChange = dy < 0 ? speedFactor : 1.0 / speedFactor;
                          final double newZoom = (currentZoom * zoomChange).clamp(TimelineConstants.minZoom, TimelineConstants.maxZoom);
                          ref.read(timelineProvider.notifier).setZoom(newZoom);
                        }
                      } else {
                        final double dy = pointerSignal.scrollDelta.dy;
                        final double dx = pointerSignal.scrollDelta.dx;
                        final double scrollDelta = dx != 0 ? dx : dy;
                        if (scrollDelta != 0 && _scrollController.hasClients) {
                          final double newOffset = (_scrollController.offset + scrollDelta).clamp(
                            0.0,
                            _scrollController.position.maxScrollExtent,
                          );
                          _scrollController.jumpTo(newOffset);
                        }
                      }
                    }
                  },
                  child: GestureDetector(
                    onScaleStart: (details) {
                      _scaleStartZoom = ref.read(timelineProvider).timeline.zoomLevel;
                      if (details.pointerCount > 1) {
                        setState(() {
                          _isZooming = true;
                        });
                        final double localX = details.localFocalPoint.dx;
                        _zoomAnchorViewportX = localX;
                        double scrollOffset = 0.0;
                        if (_scrollController.hasClients) {
                          try {
                            scrollOffset = _scrollController.offset;
                          } catch (_) {}
                        }
                        _zoomAnchorSec = (localX + scrollOffset) / _scaleStartZoom;
                      }
                    },
                    onScaleUpdate: (details) {
                      if (details.pointerCount > 1 || details.scale != 1.0) {
                        if (!_isZooming) {
                          setState(() {
                            _isZooming = true;
                          });
                        }
                        final double localX = details.localFocalPoint.dx;
                        _zoomAnchorViewportX = localX;
                        double scrollOffset = 0.0;
                        if (_scrollController.hasClients) {
                          try {
                            scrollOffset = _scrollController.offset;
                          } catch (_) {}
                        }
                        _zoomAnchorSec = (localX + scrollOffset) / ref.read(timelineProvider).timeline.zoomLevel;

                        final newZoom = (_scaleStartZoom * details.scale).clamp(TimelineConstants.minZoom, TimelineConstants.maxZoom);
                        ref.read(timelineProvider.notifier).setZoom(newZoom);
                      } else {
                        if (_isZooming) {
                          setState(() {
                            _isZooming = false;
                          });
                        }
                        if (_scrollController.hasClients) {
                          final double newOffset = (_scrollController.offset - details.focalPointDelta.dx).clamp(
                            0.0,
                            _scrollController.position.maxScrollExtent,
                          );
                          _scrollController.jumpTo(newOffset);
                        }
                      }
                    },
                    onScaleEnd: (details) {
                      setState(() {
                        _isZooming = false;
                      });
                    },
                    behavior: HitTestBehavior.translucent,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: _scrollPhysics,
                      child: AnimatedBuilder(
                        animation: _scrollController,
                        builder: (context, child) {
                          double scrollOffset = 0.0;
                          double viewportWidth = 1000.0;
                          if (_scrollController.hasClients) {
                            try {
                              scrollOffset = _scrollController.offset;
                              if (_scrollController.position.hasContentDimensions) {
                                viewportWidth = _scrollController.position.viewportDimension;
                              }
                            } catch (_) {}
                          }

                          final double computedTimelineWidth = maxDuration * zoomLevel + viewportWidth * 0.8;
                          final double actualTimelineWidth = computedTimelineWidth < constraints.maxWidth ? constraints.maxWidth : computedTimelineWidth;

                          final double startSec = (scrollOffset - 100.0) / zoomLevel;
                          final double endSec = (scrollOffset + viewportWidth + 100.0) / zoomLevel;

                          final g = TimelineConstants.gridIntervalSec;
                          int startGrid = ((startSec / g).floor() * g).clamp(0, (maxDuration + g).toInt());
                          int endGrid = ((endSec / g).ceil() * g).clamp(0, (maxDuration + g).toInt());

                          final int count = ((endGrid - startGrid) / g).floor() + 1;

                          return SizedBox(
                            width: actualTimelineWidth,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: RepaintBoundary(
                                      child: Stack(
                                        children: List.generate(count, (i) {
                                          final int index = startGrid + i * g;
                                          if (index > maxDuration + 5) return const SizedBox.shrink();
                                          final double leftPosition = index * zoomLevel;
                                          return Positioned(
                                            left: leftPosition,
                                            top: 24,
                                            bottom: 0,
                                            child: Container(
                                              width: TimelineConstants.borderWidth,
                                              color: Colors.white.withValues(alpha: 0.04),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  ),
                                ),

                                Positioned.fill(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      RepaintBoundary(
                                        child: _buildTimeRuler(zoomLevel, maxDuration, scrollOffset, viewportWidth),
                                      ),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          physics: _scrollPhysics,
                                          child: SizedBox(
                                            width: actualTimelineWidth,
                                            child: RepaintBoundary(
                                              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: [
                                                  ..._buildAllTrackLanes(timelineState.tracks, zoomLevel, nestedSequences: timelineState.nestedSequences),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                SnapGuide(
                                  position: _snapLinePositionSec != null ? _snapLinePositionSec! * zoomLevel : null,
                                  height: MediaQuery.of(context).size.height,
                                ),

                                ValueListenableBuilder<double>(
                                  valueListenable: _playheadScrubNotifier,
                                  builder: (context, playheadVal, child) {
                                    return Positioned(
                                      left: playheadVal * zoomLevel,
                                      top: 0,
                                      bottom: 0,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.topCenter,
                                        children: [
                                          Container(
                                            width: 1.5,
                                            color: const Color(0xFFF0F0F5),
                                          ),
                                            Positioned(
                                              top: 0,
                                              child: GestureDetector(
                                                onHorizontalDragUpdate: (details) {
                                                  final RenderBox renderBox = context.findRenderObject() as RenderBox;
                                                  final localPos = renderBox.globalToLocal(details.globalPosition);
                                                  final scrolledPos = Offset(localPos.dx + _scrollController.offset, localPos.dy);
                                                  _handleScrubbing(scrolledPos, zoomLevel, maxDuration);
                                                },
                                                onHorizontalDragEnd: (details) {
                                                  _commitScrub();
                                                },
                                                onHorizontalDragCancel: () {
                                                  _commitScrub();
                                                },
                                                child: ClipPath(
                                                  clipper: const PlayheadTriangle(),
                                                  child: Container(
                                                    width: 10,
                                                    height: 10,
                                                    color: const Color(0xFFF0F0F5),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  VideoClip? _findClipById(String clipId) {
    final t = ref.read(timelineProvider).timeline;
    for (var track in t.tracks.video) {
      for (var c in track.clips) {
        if (c.id == clipId) return c;
      }
    }
    return null;
  }

  AudioClip? _findAudioClipById(String clipId) {
    final t = ref.read(timelineProvider).timeline;
    for (var track in t.tracks.audio) {
      for (var c in track.clips) {
        if (c.id == clipId) return c;
      }
    }
    return null;
  }

  Widget _buildToolbar(TimelineStateData data, TimelineNotifier notifier) {
    final timelineState = data.timeline;
    final playhead = timelineState.playheadSec;
    final macroState = ref.watch(macroProvider);

    return Container(
              height: TimelineConstants.toolbarHeight,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  onPressed: notifier.canUndo ? notifier.undo : null,
                  tooltip: 'تراجع (Ctrl+Z)',
                ),
                IconButton(
                  icon: const Icon(Icons.redo_rounded, size: 18),
                  onPressed: notifier.canRedo ? notifier.redo : null,
                  tooltip: 'إعادة (Ctrl+Y)',
                ),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                IconButton(
                  icon: const Icon(Icons.content_cut_rounded, size: 18, color: Colors.redAccent),
                  onPressed: () {
                    notifier.splitClipAtPlayhead(playhead);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم قص الكليبات عند المؤشر الحالي')),
                    );
                  },
                  tooltip: 'قص الكليب (C)',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  onPressed: widget.selectedClipId != null
                      ? () {
                          notifier.removeVideoClip(widget.selectedClipId!);
                          widget.onSelectClip(null, 'video');
                        }
                      : null,
                  tooltip: 'حذف الكليب المحدد (Del)',
                ),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                if (widget.onAutoCut != null)
                  TextButton.icon(
                    onPressed: widget.selectedClipId != null ? widget.onAutoCut : null,
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('قص الصمت تلقائياً', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                if (widget.onAutoFrame != null)
                  TextButton.icon(
                    onPressed: widget.selectedClipId != null ? widget.onAutoFrame : null,
                    icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                    label: const Text('تتبع الوجه', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.tealAccent,
                    ),
                  ),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                Tooltip(
                  message: macroState.isRecording ? 'إيقاف تسجيل الماكرو' : 'بدء تسجيل ماكرو جديد',
                  child: InkWell(
                    onTap: () {
                      if (macroState.isRecording) {
                        ref.read(macroProvider.notifier).stopRecording();
                      } else {
                        ref.read(macroProvider.notifier).startRecording();
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (macroState.isRecording)
                            const RecordingIndicator()
                          else
                            Icon(Icons.mic_none_rounded, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            macroState.isRecording ? 'تسجيل...' : 'ماكرو',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  onPressed: () {
                    notifier.setZoom(timelineState.zoomLevel - 5.0);
                  },
                  tooltip: 'تصغير',
                ),
                SizedBox(
                  width: 120,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
              value: timelineState.zoomLevel.clamp(TimelineConstants.minZoom, TimelineConstants.maxZoom),
              min: TimelineConstants.minZoom,
              max: TimelineConstants.maxZoom,
                      onChanged: (v) => notifier.setZoom(v),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () {
                    notifier.setZoom(timelineState.zoomLevel + 5.0);
                  },
                  tooltip: 'تكبير',
                ),
                const SizedBox(width: 8),
                Text(
                  '${timelineState.zoomLevel.toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarColumn() {
    final timelineState = ref.read(timelineProvider).timeline;
    final nestedSequences = timelineState.nestedSequences;
    return SizedBox(
        width: TimelineConstants.sidebarWidth,
      child: Column(
        children: [
          Container(
            height: 24,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(right: BorderSide(color: AppColors.divider)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.timer_outlined, size: 16, color: AppColors.textSecondary),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._buildAllSidebarTracks(timelineState.tracks, nestedSequences: nestedSequences),
                    const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _isRippleEnabled = !_isRippleEnabled),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isRippleEnabled ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_calls_rounded,
                            size: 14,
                            color: _isRippleEnabled ? AppColors.primary : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Ripple',
                            style: TextStyle(
                              fontSize: 10,
                              color: _isRippleEnabled ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: _isRippleEnabled ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackSidebar({
    required String title,
    required IconData icon,
    required String trackType,
    required double height,
  }) {
    final bool isLocked = _lockedTracks.contains(trackType);
    final bool isHidden = _hiddenTracks.contains(trackType);
    final bool isMuted = _mutedTracks.contains(trackType);

    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Color(0xFF131317),
        border: Border(
          right: BorderSide(color: AppColors.divider),
            bottom: BorderSide(color: AppColors.divider, width: TimelineConstants.borderWidth),
          ),
        ),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 13, color: Colors.white54),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trackType == 'audio')
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: Icon(
                    isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 13,
                    color: isMuted ? const Color(0xFFF59E0B) : Colors.white30,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isMuted) {
                        _mutedTracks.remove(trackType);
                      } else {
                        _mutedTracks.add(trackType);
                      }
                    });
                  },
                  tooltip: isMuted ? 'إلغاء كتم الصوت' : 'كتم الصوت',
                )
              else
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  icon: Icon(
                    isHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 13,
                    color: isHidden ? Colors.white30 : Colors.white54,
                  ),
                  onPressed: () {
                    setState(() {
                      if (isHidden) {
                        _hiddenTracks.remove(trackType);
                      } else {
                        _hiddenTracks.add(trackType);
                      }
                    });
                  },
                  tooltip: isHidden ? 'إظهار المسار' : 'إخفاء المسار',
                ),
              const SizedBox(width: 2),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                icon: Icon(
                  isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 13,
                  color: isLocked ? const Color(0xFFEF4444) : Colors.white30,
                ),
                onPressed: () {
                  setState(() {
                    if (isLocked) {
                      _lockedTracks.remove(trackType);
                    } else {
                      _lockedTracks.add(trackType);
                    }
                  });
                },
                tooltip: isLocked ? 'إلغاء قفل المسار' : 'قفل المسار',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRuler(double zoomLevel, double maxDuration, double scrollOffset, double viewportWidth) {
    final double startSec = (scrollOffset - 100.0) / zoomLevel;
    final double endSec = (scrollOffset + viewportWidth + 100.0) / zoomLevel;
    final int startTick = startSec.floor().clamp(0, (maxDuration + 5).toInt());
    final int endTick = endSec.ceil().clamp(0, (maxDuration + 5).toInt());

    return GestureDetector(
      onTapDown: (details) {
        _handleScrubbing(details.localPosition, zoomLevel, maxDuration);
        _commitScrub();
      },
      onHorizontalDragUpdate: (details) {
        _handleScrubbing(details.localPosition, zoomLevel, maxDuration);
      },
      onHorizontalDragEnd: (details) {
        _commitScrub();
      },
      onHorizontalDragCancel: () {
        _commitScrub();
      },
      child: Container(
        height: 24,
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D11),
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ...List.generate(endTick - startTick + 1, (i) {
              final int index = startTick + i;
              if (index > maxDuration + 5) return const SizedBox.shrink();
              final double leftPosition = index * zoomLevel;
              return Positioned(
                left: leftPosition,
                bottom: 0,
                child: Container(
                  height: 12,
                  width: 1,
                  color: AppColors.border,
                      child: index % TimelineConstants.rulerMajorTickInterval == 0
                      ? OverflowBox(
                          maxWidth: 60,
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              _formatTimecode(index.toDouble()).substring(3),
                              style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace'),
                            ),
                          ),
                        )
                      : null,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackLane({
    required String title,
    required Color color,
    required IconData icon,
    required List<dynamic> clips,
    required double zoomLevel,
    required String trackType,
    required double height,
  }) {
    final bool isLocked = _lockedTracks.contains(trackType);
    final bool isHidden = _hiddenTracks.contains(trackType);
    final bool isMuted = _mutedTracks.contains(trackType);

    return DragTarget<String>(
      onAcceptWithDetails: (details) async {
        if (isLocked) return;
        final filePath = details.data;
        final playhead = ref.read(timelineProvider).timeline.playheadSec;

        double mediaDuration = 10.0;
        final infoResult = await ApiClient().getMediaInfo(filePath);
        if (!mounted) return;
        switch (infoResult) {
          case Success(data: final info):
            if (info['status'] == 'success' && info['duration'] != null) {
              final double actDur = (info['duration'] as num).toDouble();
              if (actDur > 0) {
                mediaDuration = actDur;
              }
            }
          case Failure():
            break;
        }

        final double dur = mediaDuration < 10.0 ? mediaDuration : 10.0;

        if (trackType == 'video') {
          final newClip = VideoClip(
            id: 'clip_v_${DateTime.now().millisecondsSinceEpoch}',
            sourcePath: filePath,
            startTimeInTimeline: playhead,
            endTimeInTimeline: playhead + dur,
            sourceTrimStart: 0.0,
            sourceTrimEnd: dur,
            sourceDuration: mediaDuration,
            transform: TransformState.defaultState(),
            colorGrading: ColorGradingState(),
            filters: [],
            aiFeatures: AIFeatures(),
          );
          ref.read(timelineProvider.notifier).addVideoClip(newClip);
          if (widget.onSelectVideo != null) {
            widget.onSelectVideo!(filePath);
          }
          widget.onSelectClip(newClip.id, 'video');
        } else if (trackType == 'audio') {
          final newClip = AudioClip(
            id: 'clip_a_${DateTime.now().millisecondsSinceEpoch}',
            sourcePath: filePath,
            startTimeInTimeline: playhead,
            endTimeInTimeline: playhead + dur,
            sourceTrimStart: 0.0,
            sourceTrimEnd: dur,
            sourceDuration: mediaDuration,
            effects: [],
          );
          ref.read(timelineProvider.notifier).addAudioClip(newClip);
        } else if (trackType == 'overlay') {
          final newClip = OverlayClip(
            id: 'clip_o_${DateTime.now().millisecondsSinceEpoch}',
            type: 'image',
            sourcePath: filePath,
            startTimeInTimeline: playhead,
            endTimeInTimeline: playhead + dur,
            sourceTrimStart: 0.0,
            sourceTrimEnd: dur,
            sourceDuration: mediaDuration,
            transform: TransformState.defaultState(),
          );
          ref.read(timelineProvider.notifier).addOverlayClip(newClip);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty && !isLocked;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: height,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider, width: TimelineConstants.borderWidth)),
            color: isHovering ? color : null,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                left: 0,
                child: Stack(
                  children: [
                    ...clips.map((clip) {
                      double start = 0.0;
                      double end = 0.0;
                      String clipId = '';
                      String clipName = '';

                      if (clip is VideoClip) {
                        start = clip.startTimeInTimeline;
                        end = clip.endTimeInTimeline;
                        clipId = clip.id;
                      } else if (clip is AudioClip) {
                        start = clip.startTimeInTimeline;
                        end = clip.endTimeInTimeline;
                        clipId = clip.id;
                      } else if (clip is SubtitleClip) {
                        start = clip.startTime;
                        end = clip.endTime;
                        clipId = clip.id;
                      } else if (clip is OverlayClip) {
                        start = clip.startTimeInTimeline;
                        end = clip.endTimeInTimeline;
                        clipId = clip.id;
                      } else if (clip is TextClip) {
                        start = clip.startTime;
                        end = clip.endTime;
                        clipId = clip.id;
                      } else if (clip is NestedSequence) {
                        start = clip.startTimeInTimeline;
                        end = clip.startTimeInTimeline + clip.duration;
                        clipId = clip.id;
                        clipName = clip.name;
                      }

                      final double width = (end - start) * zoomLevel;
                      final bool isSelected = clipId == widget.selectedClipId || _selectedClipIds.contains(clipId);
                      final notifier = ref.read(timelineProvider.notifier);
                      final playhead = ref.read(timelineProvider).timeline.playheadSec;

                      return Positioned(
                        left: start * zoomLevel,
                        top: 4,
                        bottom: 4,
                        width: width,
                        child: clip is NestedSequence
                            ? GestureDetector(
                                onTap: () => widget.onSelectClip(clipId, trackType),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                                    border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                        alignment: Alignment.center,
                                        child: const Icon(Icons.subdirectory_arrow_right, size: 12, color: Colors.white70),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          clipName,
                                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Text(
                                          '${clip.duration.toStringAsFixed(1)}s',
                                          style: const TextStyle(color: Colors.white38, fontSize: 9),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : clip is TextClip
                            ? TextClipItemWidget(
                                clip: clip,
                                isSelected: isSelected,
                                zoomLevel: zoomLevel,
                                 onSelect: () {
                                   final isShift = HardwareKeyboard.instance.isShiftPressed;
                                   if (isShift) {
                                     setState(() {
                                       if (_selectedClipIds.contains(clipId)) {
                                         _selectedClipIds.remove(clipId);
                                       } else {
                                         _selectedClipIds.add(clipId);
                                       }
                                     });
                                   } else {
                                     setState(() => _selectedClipIds.clear());
                                   }
                                   widget.onSelectClip(clipId, trackType);
                                 },
                                onEdit: () async {
                                  final result = await showDialog<TextClip>(
                                    context: context,
                                    builder: (context) => TextEditorDialog(existingClip: clip),
                                  );
                                  if (result != null) {
                                    notifier.updateTextClip(clipId, (_) => result);
                                  }
                                },
                                onMove: (deltaSec) {
                                  final cur = _findTextClipById(clipId);
                                  if (cur != null) {
                                    final double targetStart = cur.startTime + deltaSec;
                                    final double snappedStart = _getSnappedOffset(
                                      targetStart,
                                      cur.endTime - cur.startTime,
                                      clipId,
                                      zoomLevel,
                                      playhead,
                                    );
                                    notifier.updateTextClip(clipId, (c) => c.copyWith(startTime: snappedStart, endTime: snappedStart + (cur.endTime - cur.startTime)));
                                  }
                                },
                                onResizeLeft: (deltaSec) {
                                  final cur = _findTextClipById(clipId);
                                  if (cur != null) {
                                    final double targetStart = cur.startTime + deltaSec;
                                    final double toleranceSec = TimelineConstants.snapTolerancePixels / zoomLevel;
                                    final List<double> snapPoints = [0.0, playhead];
                                    for (final track in ref.read(timelineProvider).timeline.tracks.text) {
                                      for (final c in track.clips) {
                                        if (c.id != clipId) {
                                          snapPoints.add(c.startTime);
                                          snapPoints.add(c.endTime);
                                        }
                                      }
                                    }
                                    double bestSnappedStart = targetStart;
                                    for (final point in snapPoints) {
                                      if ((targetStart - point).abs() < toleranceSec) {
                                        bestSnappedStart = point;
                                        break;
                                      }
                                    }
                                    if (bestSnappedStart < cur.endTime - 0.1) {
                                      notifier.updateTextClip(clipId, (c) => c.copyWith(startTime: bestSnappedStart));
                                    }
                                  }
                                },
                                onResizeRight: (deltaSec) {
                                  final cur = _findTextClipById(clipId);
                                  if (cur != null) {
                                    final double targetEnd = cur.endTime + deltaSec;
                                    final double toleranceSec = TimelineConstants.snapTolerancePixels / zoomLevel;
                                    final List<double> snapPoints = [0.0, playhead];
                                    for (final track in ref.read(timelineProvider).timeline.tracks.text) {
                                      for (final c in track.clips) {
                                        if (c.id != clipId) {
                                          snapPoints.add(c.startTime);
                                          snapPoints.add(c.endTime);
                                        }
                                      }
                                    }
                                    double bestSnappedEnd = targetEnd;
                                    for (final point in snapPoints) {
                                      if ((targetEnd - point).abs() < toleranceSec) {
                                        bestSnappedEnd = point;
                                        break;
                                      }
                                    }
                                    if (bestSnappedEnd > cur.startTime + 0.1) {
                                      notifier.updateTextClip(clipId, (c) => c.copyWith(endTime: bestSnappedEnd));
                                    }
                                  }
                                 },
                                 onContextMenu: () => _showClipContextMenu(context, clipId, trackType, trackType),
                               )
                             : ClipItemWidget(
                                 clip: clip,
                                 clipType: trackType,
                                 isSelected: isSelected,
                                 zoomLevel: zoomLevel,
                                 isLocked: isLocked,
                                 isHidden: isHidden,
                                 isMuted: isMuted,
                                 isDragging: _isDraggingClip,
                                 onDragStart: () => setState(() {
                                   _snapLinePositionSec = null;
                                   _isDraggingClip = true;
                                 }),
                                 onDragEnd: () => setState(() {
                                   _snapLinePositionSec = null;
                                   _isDraggingClip = false;
                                 }),
                                 onSelect: () {
                                   final isShift = HardwareKeyboard.instance.isShiftPressed;
                                   if (isShift) {
                                     setState(() {
                                       if (_selectedClipIds.contains(clipId)) {
                                         _selectedClipIds.remove(clipId);
                                       } else {
                                         _selectedClipIds.add(clipId);
                                       }
                                     });
                                     widget.onSelectClip(clipId, trackType);
                                   } else {
                                     setState(() => _selectedClipIds.clear());
                                     widget.onSelectClip(clipId, trackType);
                                   }
                                 },
                                 onTransitionTap: clip is VideoClip ? () async {
                                   final videoClip = clip;
                                   final result = await showDialog<Transition>(
                                     context: context,
                                     builder: (context) => TransitionPicker(currentTransition: videoClip.outTransition),
                                   );
                                   if (result != null) {
                                     notifier.updateVideoClip(clipId, (c) => c.copyWith(outTransition: result));
                                   }
                                 } : null,
                                 onContextMenu: () => _showClipContextMenu(context, clipId, trackType, trackType),
                           onMove: (deltaSec) => _handleClipMove(clipId, deltaSec, zoomLevel, playhead),
                          onResizeLeft: (deltaSec) => _handleClipResizeLeft(clipId, deltaSec, zoomLevel, playhead),
                          onResizeRight: (deltaSec) => _handleClipResizeRight(clipId, deltaSec, zoomLevel, playhead),
                        ),
                      );
                    }),
                    if (isHovering)
                      Positioned(
                        left: ref.read(timelineProvider).timeline.playheadSec * zoomLevel,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: TimelineConstants.playheadWidth,
                          color: AppColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
