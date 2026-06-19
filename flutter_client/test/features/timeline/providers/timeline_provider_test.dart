import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/features/timeline/providers/timeline_provider.dart';
import 'package:flutter_client/core/models/timeline_models.dart';

void main() {
  group('TimelineNotifier', () {
    late TimelineNotifier notifier;

    setUp(() {
      notifier = TimelineNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state is empty', () {
      final state = notifier.state.timeline;
      expect(state.projectId, 'project_new');
      expect(state.playheadSec, 0.0);
      expect(state.zoomLevel, 30.0);
    });

    test('setPlayhead updates playhead position', () {
      notifier.setPlayhead(15.5);
      expect(notifier.state.timeline.playheadSec, 15.5);
    });

    test('setZoom updates zoom level', () {
      notifier.setZoom(100.0);
      expect(notifier.state.timeline.zoomLevel, 100.0);
    });

    test('setZoom clamps to valid range', () {
      notifier.setZoom(0.5);
      expect(notifier.state.timeline.zoomLevel, 1.0);
      notifier.setZoom(1000.0);
      expect(notifier.state.timeline.zoomLevel, 500.0);
    });

    test('addVideoClip adds clip and creates undo entry', () {
      final clip = VideoClip(
        id: 'v1', sourcePath: '/test.mp4',
        startTimeInTimeline: 0, endTimeInTimeline: 10,
        sourceTrimStart: 0, sourceTrimEnd: 10,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(),
        filters: [], aiFeatures: AIFeatures(),
      );
      notifier.addVideoClip(clip);
      final tracks = notifier.state.timeline.tracks;
      expect(tracks.video[0].clips.length, 1);
      expect(tracks.video[0].clips[0].id, 'v1');
      expect(notifier.state.undoStack.length, 1);
    });

    test('removeVideoClip removes clip', () {
      final clip = VideoClip(
        id: 'v1', sourcePath: '/test.mp4',
        startTimeInTimeline: 0, endTimeInTimeline: 10,
        sourceTrimStart: 0, sourceTrimEnd: 10,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(),
        filters: [], aiFeatures: AIFeatures(),
      );
      notifier.addVideoClip(clip);
      notifier.removeVideoClip('v1');
      expect(notifier.state.timeline.tracks.video[0].clips, isEmpty);
    });

    test('addTextClip adds text clip', () {
      notifier.addTextClip(TextClip(id: 't1', text: 'Hello', startTime: 0, endTime: 5));
      expect(notifier.state.timeline.tracks.text[0].clips.length, 1);
      expect(notifier.state.timeline.tracks.text[0].clips[0].text, 'Hello');
    });

    test('undo reverts last addVideoClip', () {
      notifier.addVideoClip(VideoClip(
        id: 'v1', sourcePath: '/test.mp4',
        startTimeInTimeline: 0, endTimeInTimeline: 10,
        sourceTrimStart: 0, sourceTrimEnd: 10,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(), filters: [], aiFeatures: AIFeatures(),
      ));
      expect(notifier.state.timeline.tracks.video[0].clips.length, 1);
      notifier.undo();
      expect(notifier.state.timeline.tracks.video[0].clips.length, 0);
    });

    test('redo re-applies undone addVideoClip', () {
      notifier.addVideoClip(VideoClip(
        id: 'v1', sourcePath: '/test.mp4',
        startTimeInTimeline: 0, endTimeInTimeline: 10,
        sourceTrimStart: 0, sourceTrimEnd: 10,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(), filters: [], aiFeatures: AIFeatures(),
      ));
      notifier.undo();
      expect(notifier.state.timeline.tracks.video[0].clips.length, 0);
      notifier.redo();
      expect(notifier.state.timeline.tracks.video[0].clips.length, 1);
    });

    test('updateVideoClip updates specific clip', () {
      notifier.addVideoClip(VideoClip(
        id: 'v1', sourcePath: '/test.mp4',
        startTimeInTimeline: 0, endTimeInTimeline: 10,
        sourceTrimStart: 0, sourceTrimEnd: 10,
        transform: TransformState.defaultState(),
        colorGrading: ColorGradingState(), filters: [], aiFeatures: AIFeatures(),
      ));
      notifier.updateVideoClip('v1', (c) => c.copyWith(speed: 2.0));
      expect(notifier.state.timeline.tracks.video[0].clips[0].speed, 2.0);
    });

    test('loadProject replaces entire state', () {
      final newState = TimelineState.empty().copyWith(projectName: 'Test Project');
      notifier.loadProject(newState);
      expect(notifier.state.timeline.projectName, 'Test Project');
    });
  });
}
