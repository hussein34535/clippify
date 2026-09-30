import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/features/player/logic/playhead_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

VideoClip clip({
  required String id,
  required double start,
  required double end,
  double trimStart = 0,
  double? trimEnd,
  double speed = 1,
  double volume = 1,
}) =>
    VideoClip(
      id: id,
      sourcePath: 's.mp4',
      startTimeInTimeline: start,
      endTimeInTimeline: end,
      sourceTrimStart: trimStart,
      sourceTrimEnd: trimEnd ?? (end - start),
      speed: speed,
      volume: volume,
      transform: TransformState.defaultState(),
      colorGrading: ColorGradingState(),
      filters: const [],
      aiFeatures: AIFeatures(),
    );

void main() {
  group('effectivePlayerVolume (media_kit 0–100 scale)', () {
    test('unity gains → 100', () {
      expect(
          effectivePlayerVolume(clipVolume: 1, master: 1, muted: false), 100.0);
    });
    test('multiplies clip gain by master', () {
      expect(
          effectivePlayerVolume(clipVolume: 0.5, master: 0.8, muted: false),
          moreOrLessEquals(40.0));
    });
    test('muted always wins', () {
      expect(effectivePlayerVolume(clipVolume: 2, master: 1, muted: true), 0.0);
    });
    test('clamps hot gains at 100', () {
      expect(
          effectivePlayerVolume(clipVolume: 3, master: 1, muted: false), 100.0);
    });
    test('regression: old code returned ~1% at unity (missing ×100)', () {
      // كان _applyClipSettings يستدعي setVolume(1.0) بدل setVolume(100.0).
      expect(
          effectivePlayerVolume(clipVolume: 1, master: 1, muted: false),
          greaterThan(50.0));
    });
  });

  group('timelineToMediaSec', () {
    test('maps inside clip with speed', () {
      final c = clip(id: 'a', start: 10, end: 20, trimEnd: 10, speed: 2);
      // الثانية 12 على التايملاين = 2s داخل المقطع × 2 = المادة 4
      expect(timelineToMediaSec(12, [c]), moreOrLessEquals(4.0));
    });
    test('gap returns null', () {
      final c = clip(id: 'a', start: 10, end: 20, trimEnd: 10);
      expect(timelineToMediaSec(5, [c]), isNull);
    });
  });

  group('mediaToTimelineSec', () {
    test('prefers current clip on repeated source', () {
      final a = clip(id: 'a', start: 0, end: 10, trimEnd: 10);
      final b = clip(id: 'b', start: 30, end: 40, trimEnd: 10);
      final mapped = mediaToTimelineSec(
        mediaSec: 5,
        clipsInOrder: [a, b],
        currentClipId: 'b',
        playheadSec: 32,
      );
      expect(mapped, moreOrLessEquals(35.0));
    });
    test('outside every trim → null', () {
      final a = clip(id: 'a', start: 0, end: 10, trimEnd: 10);
      expect(
          mediaToTimelineSec(
              mediaSec: 50,
              clipsInOrder: [a],
              currentClipId: 'a',
              playheadSec: 5),
          isNull);
    });
  });
}
