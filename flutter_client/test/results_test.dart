import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/features/results/auto_edit_results_screen.dart';
import 'package:flutter_client/features/results/rendered_clip.dart';
import 'package:flutter_client/features/results/timeline_bridge.dart';
import 'package:flutter_client/features/timeline/providers/timeline_provider.dart';

RenderedClipData mk(int index, double score, double durationSec, {String hook = 'هوك'}) =>
    RenderedClipData(
      index: index,
      fileUrl: 'out_$index.mp4',
      viralScore: score,
      hookText: hook,
      hookStart: 0,
      hookEnd: 1,
      durationSec: durationSec,
      captionTheme: 'TikTok',
    );

VideoClip _vc(String id, double start, double end) => VideoClip(
      id: id,
      sourcePath: 'a.mp4',
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
  group('RenderedClipData.fromJson — golden cases', () {
    test('full DoneEvent clip payload (CONTRACTS.md shape)', () {
      final clip = RenderedClipData.fromJson(const {
        'index': 0,
        'file_url': 'C:/renders/out_0.mp4',
        'viral_score': 0.87,
        'hook': {'text': 'لا تصدق ما سيحدث', 'start_sec': 1.2, 'end_sec': 4.8},
        'duration_sec': 58.4,
        'caption_theme': 'TikTok Yellow',
      });
      expect(clip.index, 0);
      expect(clip.fileUrl, 'C:/renders/out_0.mp4');
      expect(clip.viralScore, 0.87);
      expect(clip.hookText, 'لا تصدق ما سيحدث');
      expect(clip.hookStart, 1.2);
      expect(clip.hookEnd, 4.8);
      expect(clip.durationSec, 58.4);
      expect(clip.captionTheme, 'TikTok Yellow');
    });

    test('missing hook → empty defaults', () {
      final clip = RenderedClipData.fromJson(const {
        'index': 3,
        'file_url': 'x.mp4',
        'viral_score': 0.5,
        'duration_sec': 10,
      });
      expect(clip.hookText, '');
      expect(clip.hookStart, 0.0);
      expect(clip.hookEnd, 0.0);
    });

    test('missing numerics & theme → zero/empty defaults', () {
      final clip = RenderedClipData.fromJson(const {});
      expect(clip.index, 0);
      expect(clip.fileUrl, '');
      expect(clip.viralScore, 0.0);
      expect(clip.durationSec, 0.0);
      expect(clip.captionTheme, '');
    });

    test('round-trip toJson keeps contract keys', () {
      final json = mk(2, 0.9, 30).toJson();
      expect(json.containsKey('file_url'), isTrue);
      expect(json.containsKey('viral_score'), isTrue);
      expect(json.containsKey('duration_sec'), isTrue);
      expect(json.containsKey('caption_theme'), isTrue);
      final back = RenderedClipData.fromJson(json);
      expect(back.index, 2);
      expect(back.viralScore, 0.9);
      expect(back.durationSec, 30);
    });

    test('fromBackend maps a same-field backend object directly', () {
      const fake = _FakeBackendClip();
      final clip = RenderedClipData.fromBackend(fake);
      expect(clip.index, 7);
      expect(clip.fileUrl, 'b.mp4');
      expect(clip.viralScore, 0.66);
      expect(clip.hookText, 'هوك خادع');
      expect(clip.durationSec, 42.0);
      expect(clip.captionTheme, 'Bold');
    });
  });

  group('clipsToVideoClips — sequencing math', () {
    test('contiguous placement starting at insertAtSec', () {
      final clips = [mk(0, .8, 10), mk(1, .6, 20), mk(2, .9, 30)];
      final vcs = clipsToVideoClips(clips, insertAtSec: 12.5);

      expect(vcs.length, 3);
      expect(vcs[0].startTimeInTimeline, 12.5);
      expect(vcs[0].endTimeInTimeline, 22.5);
      expect(vcs[1].startTimeInTimeline, 22.5);
      expect(vcs[1].endTimeInTimeline, 42.5);
      expect(vcs[2].startTimeInTimeline, 42.5);
      expect(vcs[2].endTimeInTimeline, 72.5);
      for (var i = 1; i < vcs.length; i++) {
        expect(vcs[i].startTimeInTimeline, vcs[i - 1].endTimeInTimeline);
      }
    });

    test('ids unique + source mapping + AI defaults', () {
      final vcs = clipsToVideoClips(
          [mk(0, .8, 10), mk(1, .6, 20), mk(2, .9, 30), mk(3, .7, 15)],
          insertAtSec: 0);
      expect(vcs.map((c) => c.id).toSet().length, 4);
      for (var i = 0; i < vcs.length; i++) {
        expect(vcs[i].id.startsWith('ai_${i}_'), isTrue);
        expect(vcs[i].sourcePath, 'out_$i.mp4');
        expect(vcs[i].sourceTrimStart, 0);
        expect(vcs[i].sourceTrimEnd, vcs[i].endTimeInTimeline - vcs[i].startTimeInTimeline);
        expect(vcs[i].sourceDuration, closeTo(vcs[i].endTimeInTimeline - vcs[i].startTimeInTimeline, 1e-9));
        expect(vcs[i].aiFeatures.faceTracking, isFalse);
      }
    });

    test('empty input yields empty output', () {
      expect(clipsToVideoClips(const [], insertAtSec: 5), isEmpty);
    });
  });

  group('appendToTimeline — undo semantics via real provider', () {
    test('appends after existing clips and undo restores previous state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(timelineProvider.notifier);

      notifier.setClips([_vc('existing_1', 0, 5)]);
      expect(mainTrackClipsOf(container.read(timelineProvider)), hasLength(1));

      final added = appendMergedClips(
          notifier,
          List.of(mainTrackClipsOf(container.read(timelineProvider))),
          clipsToVideoClips([mk(0, .8, 10), mk(1, .6, 20)], insertAtSec: 5));

      expect(added, 2);
      final trackClips = mainTrackClipsOf(container.read(timelineProvider));
      expect(trackClips, hasLength(3));
      expect(trackClips[0].startTimeInTimeline, 0);
      expect(trackClips[1].startTimeInTimeline, 5);
      expect(trackClips[1].endTimeInTimeline, 15);
      expect(trackClips.last.startTimeInTimeline, 15);
      expect(trackClips.last.endTimeInTimeline, 35);

      expect(notifier.canUndo, isTrue);
      notifier.undo();
      expect(mainTrackClipsOf(container.read(timelineProvider)), hasLength(1));
    });
  });

  group('AutoEditResultsScreen — widget tests', () {
    late List<RenderedClipData> capturedAddAll;
    late List<RenderedClipData> capturedSendOne;

    Widget host() {
      capturedAddAll = [];
      capturedSendOne = [];
      return ProviderScope(
        child: MaterialApp(
        home: AutoEditResultsScreen(
          clips: [
            mk(0, 0.9, 58.4, hook: 'الأقوى'),
            mk(1, 0.4, 40.0, hook: 'الأضعف'),
            mk(2, 0.7, 45.5, hook: 'المتوسط'),
          ],
          compiledUrl: null,
          sourceVideoPath: 'src.mp4',
          onAddAll: (sorted) {
            capturedAddAll.addAll(sorted);
            return sorted.length;
          },
          onSendOne: (c) {
            capturedSendOne.add(c);
            return 1;
          },
          onSave: (_) async {},
          onPreview: (_) async {},
        ),
        ),
      );
    }

    Future<void> pumpBig(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host());
    }

    testWidgets('rank badges #1..#3 in score-desc grid order', (tester) async {
      await pumpBig(tester);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      final r1 = tester.getRect(find.text('#1'));
      final r2 = tester.getRect(find.text('#2'));
      final r3 = tester.getRect(find.text('#3'));
      expect(r1.left, lessThan(r2.left));
      expect(r3.top, greaterThan(r1.bottom));
    });

    testWidgets('score colors distinct across red/amber/green range', (tester) async {
      final c09 = AutoEditResultsScreen.scoreColor(0.9);
      final c04 = AutoEditResultsScreen.scoreColor(0.4);
      final c07 = AutoEditResultsScreen.scoreColor(0.7);
      expect(c09, isNot(c04));
      expect(c04, isNot(c07));
      expect(c07, isNot(c09));
      expect(AutoEditResultsScreen.scoreColor(0.0), const Color(0xFFFF453A));
      expect(AutoEditResultsScreen.scoreColor(0.5), const Color(0xFFFFD60A));
      expect(AutoEditResultsScreen.scoreColor(1.0), const Color(0xFF30D158));
    });

    testWidgets('add-all button present and sends score-desc list', (tester) async {
      await pumpBig(tester);
      final btn = find.byKey(const ValueKey('add_all'));
      expect(btn, findsOneWidget);

      await tester.tap(btn);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4)); // flush toast removal timer

      expect(capturedAddAll.map((c) => c.index).toList(), [0, 2, 1]);
    });

    testWidgets('per-card send uses highest-ranked card first', (tester) async {
      await pumpBig(tester);
      await tester.tap(find.text('➕ للتايملاين').first);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4)); // flush toast removal timer

      expect(capturedSendOne, hasLength(1));
      expect(capturedSendOne.first.index, 0);
    });

    testWidgets('header title and count chip render', (tester) async {
      await pumpBig(tester);
      expect(find.text('🎬 النتائج الفيروسية'), findsOneWidget);
      expect(find.text('3 مقاطع'), findsOneWidget);
    });
  });
}

/// كائن بمطابقة أسماء حقول صنف الوكيل المتوقع في auto_edit_api.dart.
class _FakeBackendClip {
  const _FakeBackendClip();
  final int index = 7;
  final String fileUrl = 'b.mp4';
  final double viralScore = 0.66;
  final String hookText = 'هوك خادع';
  final double hookStart = 2.0;
  final double hookEnd = 6.0;
  final double durationSec = 42.0;
  final String captionTheme = 'Bold';
}
