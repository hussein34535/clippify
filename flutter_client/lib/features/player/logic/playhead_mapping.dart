import 'dart:math' as math;

import '../../../core/models/timeline_models.dart';

/// Timeline → media-file position for the clip under [timelineSec].
///
/// Returns null when the playhead sits in a gap (no clip) — the caller
/// decides the fallback (the player uses identity to preserve old behaviour).
/// Uses the constant clip speed; variable speed-ramps are approximated.
double? timelineToMediaSec(double timelineSec, List<VideoClip> clipsInOrder) {
  for (final clip in clipsInOrder) {
    if (timelineSec >= clip.startTimeInTimeline &&
        timelineSec < clip.endTimeInTimeline) {
      final speed = clip.speed == 0 ? 1.0 : clip.speed;
      final clipLen =
          math.max(0.0, clip.endTimeInTimeline - clip.startTimeInTimeline);
      final timeInClip = (timelineSec - clip.startTimeInTimeline)
          .clamp(0.0, clipLen)
          .toDouble();
      final lo = math.min(clip.sourceTrimStart, clip.sourceTrimEnd);
      final hi = math.max(clip.sourceTrimStart, clip.sourceTrimEnd);
      return (clip.sourceTrimStart + timeInClip * speed)
          .clamp(lo, hi)
          .toDouble();
    }
  }
  return null;
}

/// Media-file → timeline position.
///
/// عدة sources قد تغطي نفس المجال (تقطيع نفس الملف مرتين، نسخ كليب) —
/// التطابق الأول كان يقفز بالمؤشر للكليب القديم ويعلّق التشغيل. الأفضلية الآن:
/// 1) الكليب تحت المؤشر الحالي [currentClipId] إذا كانت موضعه ينطبق.
/// 2) وإلا أقرب خط زمني مُعيَّن إلى [playheadSec].
///
/// Returns null when the media position lies outside every clip's trim range
/// (gap/past end) — the caller skips the update instead of letting the
/// playhead run away into unmapped territory.
double? mediaToTimelineSec({
  required double mediaSec,
  required List<VideoClip> clipsInOrder,
  required String? currentClipId,
  required double playheadSec,
}) {
  String? idMatch;
  VideoClip? nearest;
  double nearestDelta = double.infinity;

  for (final clip in clipsInOrder) {
    if (mediaSec < clip.sourceTrimStart || mediaSec >= clip.sourceTrimEnd) {
      continue;
    }
    final speed = clip.speed == 0 ? 1.0 : clip.speed;
    final mapped = clip.startTimeInTimeline +
        (mediaSec - clip.sourceTrimStart) / speed;
    if (clip.id == currentClipId && idMatch == null) {
      idMatch = clip.id;
      nearest = clip;
      nearestDelta = 0;
      continue;
    }
    final delta = (mapped - playheadSec).abs();
    if (delta < nearestDelta) {
      nearestDelta = delta;
      nearest = clip;
    }
  }

  if (nearest == null) return null;
  final speed = nearest.speed == 0 ? 1.0 : nearest.speed;
  return nearest.startTimeInTimeline +
      (mediaSec - nearest.sourceTrimStart) / speed;
}
