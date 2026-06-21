import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/timeline_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/timeline_constants.dart';
import '../../../shared/providers/macro_provider.dart';
import 'timeline_painters.dart';

class TimelineToolbar extends ConsumerWidget {
  final String? selectedClipId;
  final Function(String?, String) onSelectClip;
  final VoidCallback? onAutoCut;
  final VoidCallback? onAutoFrame;

  const TimelineToolbar({
    super.key,
    required this.selectedClipId,
    required this.onSelectClip,
    this.onAutoCut,
    this.onAutoFrame,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineData = ref.watch(timelineProvider);
    final notifier = ref.read(timelineProvider.notifier);
    final timelineState = timelineData.timeline;
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
                  onPressed: selectedClipId != null
                      ? () {
                          notifier.removeVideoClip(selectedClipId!);
                          onSelectClip(null, 'video');
                        }
                      : null,
                  tooltip: 'حذف الكليب المحدد (Del)',
                ),
                const VerticalDivider(width: 20, indent: 12, endIndent: 12),
                if (onAutoCut != null)
                  TextButton.icon(
                    onPressed: selectedClipId != null ? onAutoCut : null,
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('قص الصمت تلقائياً', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
                if (onAutoFrame != null)
                  TextButton.icon(
                    onPressed: selectedClipId != null ? onAutoFrame : null,
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
}
