import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/constants/timeline_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/audio_waveform.dart';
import '../../../shared/utils/thumbnail_generator.dart';

class ClipItemWidget extends StatelessWidget {
  final dynamic clip;
  final String clipType;
  final bool isSelected;
  final double zoomLevel;
  final VoidCallback onSelect;
  final ValueChanged<double> onMove;
  final ValueChanged<double> onResizeLeft;
  final ValueChanged<double> onResizeRight;
  final bool isLocked;
  final bool isHidden;
  final bool isMuted;
  final bool isDragging;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onTransitionTap;
  final VoidCallback? onContextMenu;
  final double clipMinWidth;
  final double resizeHandleWidth;

  const ClipItemWidget({
    super.key,
    required this.clip,
    required this.clipType,
    required this.isSelected,
    required this.zoomLevel,
    required this.onSelect,
    required this.onMove,
    required this.onResizeLeft,
    required this.onResizeRight,
    this.isLocked = false,
    this.isHidden = false,
    this.isMuted = false,
    this.isDragging = false,
    this.onDragStart,
    this.onDragEnd,
    this.onTransitionTap,
    this.onContextMenu,
    this.clipMinWidth = 40.0,
    this.resizeHandleWidth = 12.0,
  });

  LinearGradient _getBackgroundGradient() {
    // Low-saturation, dark-tinted washes of the iOS system palette.
    switch (clipType) {
      case 'video':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3450), Color(0xFF152438)],
        );
      case 'audio':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1D3A2C), Color(0xFF14291F)],
        );
      case 'overlay':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3D2C13), Color(0xFF2A1F0F)],
        );
      case 'subtitle':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123240), Color(0xFF0D232C)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF232326), Color(0xFF1A1A1D)],
        );
    }
  }

  Color _getHeaderColor() {
    return Colors.black.withValues(alpha: 0.3);
  }

  Color _getSelectedBorderColor() {
    // iOS system blue selection frame for every clip type.
    return AppColors.primary;
  }

  String _getLabel() {
    if (clip is VideoClip) {
      return (clip as VideoClip).sourcePath.split('/').last.split('\\').last;
    } else if (clip is AudioClip) {
      return (clip as AudioClip).sourcePath.split('/').last.split('\\').last;
    } else if (clip is SubtitleClip) {
      return (clip as SubtitleClip).text;
    } else if (clip is OverlayClip) {
      return (clip as OverlayClip).sourcePath.split('/').last.split('\\').last;
    }
    return 'clip';
  }

  String _sourcePath() {
    if (clip is VideoClip) return (clip as VideoClip).sourcePath;
    if (clip is AudioClip) return (clip as AudioClip).sourcePath;
    if (clip is OverlayClip) return (clip as OverlayClip).sourcePath;
    return '';
  }

  /// A media clip whose file is empty or no longer on disk. Subtitle clips
  /// carry inline text and are never offline.
  bool get _isMediaOffline {
    if (clipType == 'subtitle') return false;
    final path = _sourcePath();
    if (path.isEmpty) return true;
    try {
      return !File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  double _getClipWidth() {
    double duration = 0.0;
    if (clip is VideoClip) {
      duration = (clip as VideoClip).endTimeInTimeline - (clip as VideoClip).startTimeInTimeline;
    } else if (clip is AudioClip) {
      duration = (clip as AudioClip).endTimeInTimeline - (clip as AudioClip).startTimeInTimeline;
    } else if (clip is OverlayClip) {
      duration = (clip as OverlayClip).endTimeInTimeline - (clip as OverlayClip).startTimeInTimeline;
    } else if (clip is SubtitleClip) {
      duration = (clip as SubtitleClip).endTime - (clip as SubtitleClip).startTime;
    }
    return (duration * zoomLevel).clamp(clipMinWidth, double.infinity);
  }

  Widget _buildTopHeader() {
    final label = _getLabel();
    final double headerHeight = clipType == 'overlay' ? 15.0 : 20.0;
    final hasTransition = clipType == 'video' && (clip as VideoClip).outTransition.type != 'none';
    return Container(
      height: headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _getHeaderColor(),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showAdjustBadge = constraints.maxWidth > 120 && (clipType == 'video' || clipType == 'audio');
          return Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 8.5, color: Colors.white, fontWeight: FontWeight.w500, fontFamily: 'Inter'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr, // filenames: keep extension sane in RTL
                  ),
                ),
              ),
              if (_isMediaOffline && constraints.maxWidth > 64) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: AppColors.destructive.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.destructive, width: 0.5),
                  ),
                  child: const Text(
                    'مفقود',
                    style: TextStyle(fontSize: 7.5, color: AppColors.destructive, fontFamily: 'Inter', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              if (hasTransition) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onTransitionTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: const Color(0xFF8B5CF6), width: TimelineConstants.borderWidth),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, size: 9, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 1),
                        Text(
                          'Transition',
                          style: TextStyle(fontSize: 7.5, color: const Color(0xFF8B5CF6), fontFamily: 'Inter', fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (showAdjustBadge) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    children: [
                      Text(
                        clipType == 'video' ? 'ضبط' : 'صوت',
                        style: TextStyle(fontSize: 7.5, color: Colors.white.withValues(alpha: 0.7), fontFamily: 'Inter'),
                      ),
                      const SizedBox(width: 1),
                      Icon(Icons.arrow_drop_down, size: 9, color: Colors.white.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildContentArea() {
    if (clipType == 'video') {
      final videoClip = clip as VideoClip;
      final clipWidth = _getClipWidth();
      final int thumbCount = (clipWidth / TimelineConstants.thumbnailCellWidth).ceil().clamp(1, TimelineConstants.maxThumbnailCount);
      return Expanded(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: thumbCount,
          itemBuilder: (context, i) {
            final double ratio = thumbCount > 1 ? i / (thumbCount - 1) : 0.0;
            final double clipOffset = ratio * (videoClip.sourceTrimEnd - videoClip.sourceTrimStart);
            final double sourceTimestamp = videoClip.sourceTrimStart + clipOffset;
            return Container(
              width: 60,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.black12, width: TimelineConstants.borderWidth)),
              ),
              child: TimelineVideoThumbnail(
                videoPath: videoClip.sourcePath,
                timestampSec: sourceTimestamp,
                isDragging: isDragging,
              ),
            );
          },
        ),
      );
    }
    if (clipType == 'audio') {
      final audioClip = clip as AudioClip;
      final Color waveColor = isMuted
          ? const Color(0xFF55555F).withValues(alpha: 0.4)
          : AppColors.secondary.withValues(alpha: 0.6);

      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
          child: AudioWaveformLoader(
            audioPath: audioClip.sourcePath,
            builder: (samples) => CustomPaint(
              size: Size.infinite,
              painter: AudioWaveformPainter(
                color: waveColor,
                clipId: audioClip.id,
                zoomLevel: zoomLevel,
                waveformSamples: samples,
                isMuted: isMuted,
              ),
            ),
          ),
        ),
      );
    }
    return const Expanded(child: SizedBox.shrink());
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isHidden ? 0.35 : 1.0,
      child: GestureDetector(
        onTap: onSelect,
        onSecondaryTap: onContextMenu,
        child: DragTarget<double>(
          onAcceptWithDetails: (details) {},
          builder: (context, candidateData, rejectedData) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onHorizontalDragStart: isLocked ? null : (_) => onDragStart?.call(),
                  onHorizontalDragEnd: isLocked ? null : (_) => onDragEnd?.call(),
                  onHorizontalDragUpdate: isLocked
                      ? null
                      : (details) {
                          final deltaSec = details.delta.dx / zoomLevel;
                          onMove(deltaSec);
                        },
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      gradient: _getBackgroundGradient(),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: isSelected
                            ? _getSelectedBorderColor()
                            : (_isMediaOffline
                                ? AppColors.destructive
                                : AppColors.border),
                        width: (isSelected || _isMediaOffline) ? 1.2 : 0.5,
                      ),
                      boxShadow: isSelected
                          ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.28), blurRadius: 10, spreadRadius: -2)]
                          : null,
                    ),
                    child: clipType == 'subtitle'
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0),
                              child: Text(
                                _getLabel(),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'Inter',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTopHeader(),
                              _buildContentArea(),
                            ],
                          ),
                  ),
                ),
                if (isSelected && !isLocked)
                  _buildResizeHandle(
                    isLeft: true,
                    onDragStart: onDragStart,
                    onDragEnd: onDragEnd,
                    onResize: (dx) => onResizeLeft(dx / zoomLevel),
                    indicatorColor: _getSelectedBorderColor(),
                    handleWidth: resizeHandleWidth,
                  ),
                if (isSelected && !isLocked)
                  _buildResizeHandle(
                    isLeft: false,
                    onDragStart: onDragStart,
                    onDragEnd: onDragEnd,
                    onResize: (dx) => onResizeRight(dx / zoomLevel),
                    indicatorColor: _getSelectedBorderColor(),
                    handleWidth: resizeHandleWidth,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildResizeHandle({
    required bool isLeft,
    required VoidCallback? onDragStart,
    required VoidCallback? onDragEnd,
    required ValueChanged<double> onResize,
    required Color indicatorColor,
    required double handleWidth,
  }) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: handleWidth,
      child: Stack(
        children: [
          // Visible indicator: 2px line
          Positioned(
            left: isLeft ? 0 : null,
            right: isLeft ? null : 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 2.0,
              color: indicatorColor,
            ),
          ),
          // Invisible larger hit area
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => onDragStart?.call(),
                onHorizontalDragEnd: (_) => onDragEnd?.call(),
                onHorizontalDragUpdate: (details) {
                  onResize(details.delta.dx);
                },
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimelineVideoThumbnail extends StatefulWidget {
  final String videoPath;
  final double timestampSec;
  final bool isDragging;
  const TimelineVideoThumbnail({
    super.key,
    required this.videoPath,
    required this.timestampSec,
    this.isDragging = false,
  });

  @override
  State<TimelineVideoThumbnail> createState() => _TimelineVideoThumbnailState();
}

class _TimelineVideoThumbnailState extends State<TimelineVideoThumbnail> {
  String? _thumbPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  @override
  void didUpdateWidget(covariant TimelineVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool wasDragging = oldWidget.isDragging;
    final bool isNowDragging = widget.isDragging;
    if (widget.videoPath != oldWidget.videoPath ||
        (!isNowDragging && (wasDragging || widget.timestampSec != oldWidget.timestampSec))) {
      _loadThumb();
    }
  }

  Future<void> _loadThumb() async {
    if (_isLoading) return;
    _isLoading = true;

    await _loadViaFfmpeg();

    _isLoading = false;
  }

  Future<void> _loadViaFfmpeg() async {
    final path = await ThumbnailGenerator.generate(
      widget.videoPath,
      widget.timestampSec,
      width: 160,
      height: 90,
    );
    if (mounted) {
      setState(() => _thumbPath = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbPath != null) {
      return Image.file(
        File(_thumbPath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white.withValues(alpha: 0.08), size: 16),
      ),
    );
  }
}
