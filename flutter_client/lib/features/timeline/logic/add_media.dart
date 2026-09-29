import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/timeline_models.dart';
import '../../../shared/providers/toast_provider.dart';
import '../providers/timeline_provider.dart';

/// Resolves media info (duration, etc.) for a file path.
/// Returns the raw backend payload, or null when unavailable.
typedef MediaInfoResolver = Future<Map<String, dynamic>?> Function(
    String path);

/// Real implementation backed by [ApiClient.getMediaInfo].
Future<Map<String, dynamic>?> defaultMediaInfoResolver(String path) async {
  try {
    final result = await ApiClient().getMediaInfo(path);
    switch (result) {
      case Success(data: final info):
        return info;
      case Failure():
        return null;
    }
  } catch (_) {
    // Backend down / network error — caller falls back to a sane default
    // duration so the user still sees their media land on the timeline.
    return null;
  }
}

/// .mp3/.wav land on audio tracks, everything else defaults to video.
bool isAudioFilePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp3') || lower.endsWith('.wav');
}

/// Fallback duration when the backend cannot tell us the real one.
const double kUnknownMediaDurationFallback = 10.0;

class AddMediaResult {
  final String clipId;
  final String trackType;
  final double startTime;
  final double duration;

  const AddMediaResult({
    required this.clipId,
    required this.trackType,
    required this.startTime,
    required this.duration,
  });
}

/// Single source of truth for turning a media file path into a timeline clip.
///
/// Used by BOTH the media library (drag onto timeline + double-tap to add)
/// and the timeline drop targets, so every entry point behaves identically.
///
/// - [trackType]: 'video' | 'audio' | 'overlay'. Defaults by extension
///   (.mp3/.wav → audio, else video). Subtitle/text are rejected with a hint.
/// - [atSec]: where to place the clip. Defaults to the current playhead.
Future<AddMediaResult?> addMediaFromPath(
  WidgetRef ref,
  BuildContext context,
  String path, {
  String? trackType,
  double? atSec,
  MediaInfoResolver? mediaInfoResolver,
}) async {
  final resolvedTrackType =
      trackType ?? (isAudioFilePath(path) ? 'audio' : 'video');
  final startAt = atSec ?? ref.read(timelineProvider).timeline.playheadSec;

  if (resolvedTrackType != 'video' &&
      resolvedTrackType != 'audio' &&
      resolvedTrackType != 'overlay') {
    ref.read(toastProvider.notifier).info('اسحب للمسار الصحيح');
    return null;
  }

  double mediaDuration = kUnknownMediaDurationFallback;
  try {
    final resolver = mediaInfoResolver ?? defaultMediaInfoResolver;
    final info = await resolver(path);
    if (info != null &&
        info['status'] == 'success' &&
        info['duration'] != null) {
      final dur = (info['duration'] as num).toDouble();
      if (dur > 0) mediaDuration = dur;
    }
  } catch (_) {}

  // Unit sanity: some backends report milliseconds. Anything above 6h for a
  // single imported clip is almost certainly ms — convert. Hard-cap at 6h
  // regardless so a poisoned value can never stretch the timeline again.
  if (mediaDuration > 6 * 3600) mediaDuration = mediaDuration / 1000.0;
  mediaDuration = mediaDuration.clamp(0.1, 6 * 3600.0);

  // Use the REAL media duration for both the on-timeline span and the source
  // trim; fall back to a sensible default only when unknown.
  final double dur =
      mediaDuration > 0.1 ? mediaDuration : kUnknownMediaDurationFallback;

  final notifier = ref.read(timelineProvider.notifier);
  final String clipId;
  switch (resolvedTrackType) {
    case 'video':
      clipId = 'clip_v_${DateTime.now().millisecondsSinceEpoch}';
      notifier.addVideoClip(VideoClip(
        id: clipId,
        sourcePath: path,
        startTimeInTimeline: startAt,
        endTimeInTimeline: startAt + dur,
        sourceTrimStart: 0.0,
        sourceTrimEnd: dur,
        sourceDuration: mediaDuration,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(),
        filters: [],
        aiFeatures: AIFeatures(),
      ));
      break;
    case 'audio':
      clipId = 'clip_a_${DateTime.now().millisecondsSinceEpoch}';
      notifier.addAudioClip(AudioClip(
        id: clipId,
        sourcePath: path,
        startTimeInTimeline: startAt,
        endTimeInTimeline: startAt + dur,
        sourceTrimStart: 0.0,
        sourceTrimEnd: dur,
        sourceDuration: mediaDuration,
        effects: [],
      ));
      break;
    case 'overlay':
      clipId = 'clip_o_${DateTime.now().millisecondsSinceEpoch}';
      notifier.addOverlayClip(OverlayClip(
        id: clipId,
        type: 'image',
        sourcePath: path,
        startTimeInTimeline: startAt,
        endTimeInTimeline: startAt + dur,
        sourceTrimStart: 0.0,
        sourceTrimEnd: dur,
        sourceDuration: mediaDuration,
        transform: TransformState.defaultState(),
      ));
      break;
    default:
      ref.read(toastProvider.notifier).info('اسحب للمسار الصحيح');
      return null;
  }

  notifier.setPlayhead(startAt);
  if (context.mounted) {
    ref.read(toastProvider.notifier).success('تمت إضافة الوسائط إلى المسار');
  }
  return AddMediaResult(
    clipId: clipId,
    trackType: resolvedTrackType,
    startTime: startAt,
    duration: dur,
  );
}
