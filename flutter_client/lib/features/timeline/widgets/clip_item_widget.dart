import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
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
  });

  LinearGradient _getBackgroundGradient() {
    switch (clipType) {
      case 'video':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF047857)],
        );
      case 'audio':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
        );
      case 'overlay':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF59E0B), Color(0xFFB45309)],
        );
      case 'subtitle':
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0EA5E9), Color(0xFF1D4ED8)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1B20), Color(0xFF1A1B20)],
        );
    }
  }

  Color _getHeaderColor() {
    return Colors.black.withValues(alpha: 0.3);
  }

  Color _getSelectedBorderColor() {
    switch (clipType) {
      case 'video':   return const Color(0xFF818CF8); // Soft Pastel Indigo
      case 'audio':   return const Color(0xFF2DD4BF); // Soft Mint Teal
      case 'overlay': return const Color(0xFFFB923C); // Soft Pastel Orange
      case 'subtitle': return const Color(0xFF34D399); // Soft Sage Emerald
      default:        return Colors.white;
    }
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
    return duration * zoomLevel;
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
                  ),
                ),
              ),
              if (hasTransition) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onTransitionTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: const Color(0xFF8B5CF6), width: 0.5),
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
                        clipType == 'video' ? 'Adjust Video' : 'Adjust VO',
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
      final int thumbCount = (clipWidth / 60.0).ceil().clamp(1, 50);
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
                border: Border(right: BorderSide(color: Colors.black12, width: 0.5)),
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
          : const Color(0xFF0D9488).withValues(alpha: 0.6);

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
    final double clipWidth = _getClipWidth();
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
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? _getSelectedBorderColor() : Colors.white.withValues(alpha: 0.08),
                        width: isSelected ? 1.5 : 0.8,
                      ),
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
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (clipWidth / 3.0).clamp(2.0, 8.0),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => onDragStart?.call(),
                        onHorizontalDragEnd: (_) => onDragEnd?.call(),
                        onHorizontalDragUpdate: (details) {
                          final deltaSec = details.delta.dx / zoomLevel;
                          onResizeLeft(deltaSec);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: _getSelectedBorderColor(),
                                width: 3.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (isSelected && !isLocked)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: (clipWidth / 3.0).clamp(2.0, 8.0),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => onDragStart?.call(),
                        onHorizontalDragEnd: (_) => onDragEnd?.call(),
                        onHorizontalDragUpdate: (details) {
                          final deltaSec = details.delta.dx / zoomLevel;
                          onResizeRight(deltaSec);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: _getSelectedBorderColor(),
                                width: 3.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
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
      color: const Color(0xFF1E1F24),
      child: Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white.withValues(alpha: 0.08), size: 16),
      ),
    );
  }
}
