import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/features/timeline/providers/timeline_provider.dart';
import 'package:flutter_client/core/models/timeline_models.dart';

void main() {
  group('TimelineStateData', () {
    test('copyWith updates timeline', () {
      final initial = TimelineStateData(
        timeline: TimelineState.empty(),
        undoStack: [],
        redoStack: [],
      );
      final updated = initial.copyWith(
        timeline: initial.timeline.copyWith(playheadSec: 10.0),
      );
      expect(updated.timeline.playheadSec, 10.0);
      expect(initial.timeline.playheadSec, 0.0);
    });
  });

  group('TimelineNotifier', () {
    test('initial state has empty timeline', () {
      final notifier = TimelineNotifier();
      expect(notifier.state.timeline.playheadSec, 0.0);
      expect(notifier.state.timeline.zoomLevel, 30.0);
      expect(notifier.state.undoStack, isEmpty);
      expect(notifier.state.redoStack, isEmpty);
    });

    test('setPlayhead updates playhead position', () {
      final notifier = TimelineNotifier();
      notifier.setPlayhead(15.0);
      expect(notifier.state.timeline.playheadSec, 15.0);
    });

    test('setPlayhead clamps to non-negative', () {
      final notifier = TimelineNotifier();
      notifier.setPlayhead(-5.0);
      expect(notifier.state.timeline.playheadSec, 0.0);
    });

    test('setZoom updates zoom level', () {
      final notifier = TimelineNotifier();
      notifier.setZoom(100.0);
      expect(notifier.state.timeline.zoomLevel, 100.0);
    });

    test('setZoom clamps between min and max', () {
      final notifier = TimelineNotifier();
      notifier.setZoom(0.5);
      expect(notifier.state.timeline.zoomLevel, 1.0);
      notifier.setZoom(999.0);
      expect(notifier.state.timeline.zoomLevel, 500.0);
    });

    test('undo restores previous state', () {
      final notifier = TimelineNotifier();
      notifier.setPlayhead(10.0);
      notifier.setZoom(100.0);
      notifier.undo();
      expect(notifier.state.timeline.playheadSec, 10.0);
    });

    test('redo restores undone state', () {
      final notifier = TimelineNotifier();
      notifier.undo();
      expect(notifier.state.timeline, isNotNull);
    });
  });

  group('VideoClip', () {
    test('create and copy', () {
      final clip = VideoClip(
        id: 'test1',
        sourcePath: '/path/to/video.mp4',
        startTimeInTimeline: 5.0,
        endTimeInTimeline: 15.0,
        sourceTrimStart: 0.0,
        sourceTrimEnd: 10.0,
        sourceDuration: 60.0,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(),
        filters: [],
        aiFeatures: AIFeatures(),
      );
      expect(clip.id, 'test1');
      expect(clip.endTimeInTimeline - clip.startTimeInTimeline, 10.0);
    });
  });
}
