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

  group('سحب الكليبات (free drag + magnetic drop)', () {
    late TimelineNotifier notifier;

    setUp(() {
      notifier = TimelineNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    VideoClip clipAt(String id, double s, double e) => VideoClip(
          id: id,
          sourcePath: '/test.mp4',
          startTimeInTimeline: s,
          endTimeInTimeline: e,
          sourceTrimStart: 0,
          sourceTrimEnd: e - s,
          transform: TransformState.defaultState(),
          colorGrading: ColorGradingState(),
          filters: [],
          aiFeatures: AIFeatures(),
        );

    VideoClip clipById(String id) => notifier.state.timeline.tracks.video
        .expand((t) => t.clips)
        .firstWhere((c) => c.id == id);

    test('كليب ملاصق لجيرانه يتحرك بحرية (لا تجميد)', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      notifier.addVideoClip(clipAt('v2', 4, 8));

      notifier.moveVideoClip('v1', 2.0);

      expect(clipById('v1').startTimeInTimeline, moreOrLessEquals(2.0));
      expect(clipById('v1').endTimeInTimeline, moreOrLessEquals(6.0));
    });

    test('السحب لا يتجاوز بداية التايم لاين', () {
      notifier.addVideoClip(clipAt('v1', 4, 8));

      notifier.moveVideoClip('v1', -5.0);

      expect(clipById('v1').startTimeInTimeline, 0.0);
      expect(clipById('v1').endTimeInTimeline, 4.0);
    });

    test('كليب على مسار ثانٍ يتحرك (المسار يُستنتج تلقائيًا)', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      notifier.addVideoClip(clipAt('v2', 4, 8), trackIndex: 1);

      notifier.moveVideoClip('v2', 10.0);

      expect(notifier.state.timeline.tracks.video.length, 2);
      expect(
        notifier.state.timeline.tracks.video[1].clips.first.startTimeInTimeline,
        moreOrLessEquals(10.0),
        reason: 'كليب على المسار 2 كان يفشل صامتًا لأن trackIndex كان 0 دائمًا',
      );
    });

    test('كامل السحب = حدث تراجع واحد (undo checkpoint)', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      final depthBefore = notifier.state.undoStack.length;

      notifier.beginGesture();
      for (var i = 1; i <= 15; i++) {
        notifier.moveVideoClip('v1', i * 0.1);
      }
      notifier.endGesture();

      expect(notifier.state.undoStack.length, depthBefore + 1,
          reason: 'سحب بكسل بكسل كان يملأ الـ undo stack بالكامل');
      notifier.undo();
      expect(clipById('v1').startTimeInTimeline, 0.0);
    });

    test('بعد رفع اليد: الكليب يبقى مكانه والجار يُدفع لليمين', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      notifier.addVideoClip(clipAt('v2', 4, 8));

      // سحب v1 يمينًا فوق v2 → تداخل مؤقت [3,7) × [4,8)
      notifier.moveVideoClip('v1', 3.0);
      notifier.resolveVideoOverlaps('v1');

      expect(clipById('v1').startTimeInTimeline, moreOrLessEquals(3.0),
          reason: 'المسحوب يبقى حيث سقط');
      expect(clipById('v2').startTimeInTimeline, moreOrLessEquals(7.0),
          reason: 'الجار يُدفع لليمين (سلوك مغناطيسي)');
      expect(clipById('v2').endTimeInTimeline, moreOrLessEquals(11.0));
    });

    test('الجر يسارًا فوق جار: المسحوب يبقى والجار يعدّي لليمين', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      notifier.addVideoClip(clipAt('v2', 4, 8));

      // سحب v2 يسارًا فوق v1 → [1,5) يتداخل مع [0,4)
      notifier.moveVideoClip('v2', 1.0);
      notifier.resolveVideoOverlaps('v2');

      expect(clipById('v2').startTimeInTimeline, moreOrLessEquals(1.0),
          reason: 'المسحوب يبقى حيث سقط');
      expect(clipById('v1').startTimeInTimeline, moreOrLessEquals(5.0),
          reason: 'v1 يعدّي إلى يمين v2 (بلا تداخل)');
    });

    test('رفع بلا تداخل لا يغيّر شيئًا', () {
      notifier.addVideoClip(clipAt('v1', 0, 4));
      notifier.addVideoClip(clipAt('v2', 4, 8));

      notifier.moveVideoClip('v2', 9.0); // فراغ: [9,13) لا يمسّ [0,4)
      notifier.resolveVideoOverlaps('v2');

      expect(clipById('v1').startTimeInTimeline, moreOrLessEquals(0.0));
      expect(clipById('v2').startTimeInTimeline, moreOrLessEquals(9.0));
      expect(clipById('v2').endTimeInTimeline, moreOrLessEquals(13.0));
    });
  });
}
