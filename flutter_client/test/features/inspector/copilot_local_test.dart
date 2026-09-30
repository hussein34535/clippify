import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/features/inspector/providers/copilot_provider.dart';
import 'package:flutter_client/features/timeline/providers/timeline_provider.dart';
import 'package:flutter_test/flutter_test.dart';

VideoClip vclip(String id, double start, double end) => VideoClip(
      id: id,
      sourcePath: 's.mp4',
      startTimeInTimeline: start,
      endTimeInTimeline: end,
      sourceTrimStart: 0,
      sourceTrimEnd: end - start,
      transform: TransformState.defaultState(),
      colorGrading: ColorGradingState(),
      filters: const [],
      aiFeatures: AIFeatures(),
    );

void main() {
  group('parseLocalCopilotCommand (pure)', () {
    test('undo / redo عربي وإنجليزي', () {
      expect(parseLocalCopilotCommand('تراجع')?.kind, LocalCopilotKind.undo);
      expect(parseLocalCopilotCommand('undo')?.kind, LocalCopilotKind.undo);
      expect(parseLocalCopilotCommand('إعادة')?.kind, LocalCopilotKind.redo);
    });

    test('split variants', () {
      expect(parseLocalCopilotCommand('قص عند المؤشر')?.kind,
          LocalCopilotKind.splitAtPlayhead);
      expect(
          parseLocalCopilotCommand('split')?.kind, LocalCopilotKind.splitAtPlayhead);
    });

    test('delete variants', () {
      expect(parseLocalCopilotCommand('احذف المقطع')?.kind,
          LocalCopilotKind.deleteClip);
      expect(parseLocalCopilotCommand('delete clip')?.kind,
          LocalCopilotKind.deleteClip);
    });

    test('speed with western and arabic-indic numbers', () {
      final a = parseLocalCopilotCommand('خلي السرعة 2');
      expect(a?.kind, LocalCopilotKind.setSpeed);
      expect(a?.value, 2.0);
      final b = parseLocalCopilotCommand('السرعة ١٫٥');
      expect(b?.kind, LocalCopilotKind.setSpeed);
      expect(b?.value, moreOrLessEquals(1.5));
      final c = parseLocalCopilotCommand('سرّع المقطع');
      expect(c?.kind, LocalCopilotKind.setSpeed);
      expect(c?.value, -1);
      final d = parseLocalCopilotCommand('slow down');
      expect(d?.kind, LocalCopilotKind.setSpeed);
      expect(d?.value, -2);
    });

    test('volume absolute, percent, mute, relative', () {
      expect(parseLocalCopilotCommand('الصوت 50')?.value,
          moreOrLessEquals(0.5));
      expect(
          parseLocalCopilotCommand('volume 0.8')?.value, moreOrLessEquals(0.8));
      expect(parseLocalCopilotCommand('اكتم الصوت')?.value, 0.0);
      expect(
          parseLocalCopilotCommand('اخفض الصوت')?.value, -1);
      expect(parseLocalCopilotCommand('ارفع الصوت')?.value, -2);
    });

    test('unknown prompts fall through to backend (null)', () {
      expect(parseLocalCopilotCommand('ما أجمل الطقس اليوم؟'), isNull);
      expect(parseLocalCopilotCommand(''), isNull);
      expect(parseLocalCopilotCommand('اقترح فكرة فيديو'), isNull);
    });
  });

  group('applyLocalCommand (real TimelineNotifier)', () {
    late TimelineNotifier timeline;
    late CopilotNotifier copilot;

    setUp(() {
      timeline = TimelineNotifier();
      copilot = CopilotNotifier();
      timeline.addVideoClip(vclip('v1', 0, 10));
    });

    tearDown(() {
      timeline.dispose();
      copilot.dispose();
    });

    test('delete removes first video clip', () {
      final reply = copilot.applyLocalCommand(
          const LocalCopilotCommand(LocalCopilotKind.deleteClip), timeline);
      expect(reply, contains('تم حذف'));
      expect(timeline.state.timeline.tracks.video.first.clips, isEmpty);
    });

    test('setSpeed resizes through withSpeed', () {
      copilot.applyLocalCommand(
          const LocalCopilotCommand(LocalCopilotKind.setSpeed, 2.0), timeline);
      final c = timeline.state.timeline.tracks.video.first.clips.first;
      expect(c.speed, 2.0);
      expect(c.endTimeInTimeline, moreOrLessEquals(5.0));
    });

    test('setVolume scales clip gain', () {
      copilot.applyLocalCommand(
          const LocalCopilotCommand(LocalCopilotKind.setVolume, 0.5), timeline);
      expect(timeline.state.timeline.tracks.video.first.clips.first.volume,
          moreOrLessEquals(0.5));
    });

    test('split/undo/redo roundtrip', () {
      timeline.setPlayhead(4);
      expect(
          copilot.applyLocalCommand(
              const LocalCopilotCommand(LocalCopilotKind.splitAtPlayhead),
              timeline),
          contains('تم القص'));
      expect(timeline.state.timeline.tracks.video.first.clips, hasLength(2));
      expect(
          copilot.applyLocalCommand(
              const LocalCopilotCommand(LocalCopilotKind.undo), timeline),
          contains('تم التراجع'));
      expect(timeline.state.timeline.tracks.video.first.clips, hasLength(1));
    });

    test('empty timeline gives honest replies, no crash', () {
      timeline.removeVideoClip('v1');
      expect(
          copilot.applyLocalCommand(
              const LocalCopilotCommand(LocalCopilotKind.deleteClip),
              timeline),
          contains('لا يوجد'));
      expect(
          copilot.applyLocalCommand(
              const LocalCopilotCommand(LocalCopilotKind.undo), timeline),
          isNotEmpty);
    });
  });
}
