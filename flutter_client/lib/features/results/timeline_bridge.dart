import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/timeline_models.dart';
import '../timeline/providers/timeline_provider.dart';
import 'rendered_clip.dart';

/// يحوّل نتائج الـ Auto-Edit إلى كليبات فيديو متتالية على التايملاين.
///
/// - التوزيع يبدأ من [insertAtSec] وكل كليب يلتصق بنهاية سابقه (contiguous).
/// - المعرفات فريدة: `ai_${index}_${timestamp}`.
/// - `sourcePath = fileUrl`، والقص المصدر يغطي كامل مدة الكليب.
///
/// ملاحظة توافق: `VideoClip` الحقيقي لا يملك حقل `name` — نص الهوك
/// (مقتطعاً 40 حرفاً) غير قابل للتخزين حالياً، لذا يُوثّق هنا فقط حتى
/// يضاف الحقل للنموذج مستقبلاً.
List<VideoClip> clipsToVideoClips(
  List<RenderedClipData> clips, {
  required double insertAtSec,
}) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  double cursor = insertAtSec;
  final result = <VideoClip>[];
  for (final c in clips) {
    final start = cursor;
    final end = start + c.durationSec;
    // الاسم المخطوط (غير مدعوم في VideoClip): hookText trimmed 40 chars
    result.add(VideoClip(
      id: 'ai_${c.index}_$timestamp',
      sourcePath: c.fileUrl,
      startTimeInTimeline: start,
      endTimeInTimeline: end,
      sourceTrimStart: 0.0,
      sourceTrimEnd: c.durationSec,
      sourceDuration: c.durationSec,
      transform: TransformState.defaultState(),
      colorGrading: ColorGradingState(),
      filters: const [],
      aiFeatures: AIFeatures(faceTracking: false),
    ));
    cursor = end;
  }
  return result;
}

/// كليبات المسار الرئيسي الحالي.
List<VideoClip> mainTrackClipsOf(TimelineStateData data) =>
    data.timeline.tracks.video.isNotEmpty ? data.timeline.tracks.video.first.clips : const [];

/// دمج بلا تداخل: تُدفع الكليبات الجديدة لتبدأ بعد نهاية آخر كليب موجود
/// عندما يتداخل موضع الإدراج مع الموجود — وبذلك يظل عدم التداخل invariant
/// محفوظًا (نفس سلوك الحل المغناطيسي في السحب).
int appendMergedClips(
    TimelineNotifier notifier, List<VideoClip> existing, List<VideoClip> clips) {
  if (clips.isEmpty) return 0;
  double maxEnd = 0;
  for (final c in existing) {
    if (c.endTimeInTimeline > maxEnd) maxEnd = c.endTimeInTimeline;
  }
  double firstStart = clips.first.startTimeInTimeline;
  for (final c in clips) {
    if (c.startTimeInTimeline < firstStart) firstStart = c.startTimeInTimeline;
  }
  final delta = maxEnd - firstStart;
  final shifted = delta > 0
      ? clips
          .map((c) => c.copyWith(
                startTimeInTimeline: c.startTimeInTimeline + delta,
                endTimeInTimeline: c.endTimeInTimeline + delta,
              ))
          .toList()
      : clips;
  notifier.setClips([...existing, ...shifted]);
  return shifted.length;
}

/// واجهة الـ UI — تعمل من أي ConsumerWidget/ConsumerState مع الحفاظ
/// على دلالات التراجع (قراءة الكليبات الموجودة أولاً ثم النشر الكامل).
int appendToTimeline(WidgetRef ref, List<VideoClip> clips) => appendMergedClips(
    ref.read(timelineProvider.notifier), List.of(mainTrackClipsOf(ref.read(timelineProvider))), clips);
