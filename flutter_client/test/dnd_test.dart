import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/core/constants/timeline_constants.dart';
import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/features/library/widgets/media_library_widget.dart';
import 'package:flutter_client/features/timeline/providers/timeline_provider.dart';
import 'package:flutter_client/features/timeline/widgets/timeline_widget.dart';
import 'package:flutter_client/shared/providers/toast_provider.dart';

/// Fake backend media-info — no network, deterministic 8s duration.
Future<Map<String, dynamic>?> fakeResolver(String path) async =>
    <String, dynamic>{'status': 'success', 'duration': 8.0};

const double _kZoom = 30.0;

TimelineNotifier _seededNotifier({double playhead = 0.0}) {
  final notifier = TimelineNotifier();
  notifier.loadProject(
    TimelineState(
      projectId: 'dnd_test',
      projectName: 'DnD Test',
      settings: TimelineSettings(),
      // Exactly ONE empty video track → lanes = [video], height 78 + 4 gap.
      tracks: Tracks(
        video: [
          VideoTrack(id: 'v_main', name: 'Video 1', index: 0, clips: []),
        ],
        audio: [],
        subtitles: [],
        overlays: [],
        text: [],
      ),
      playheadSec: playhead,
      zoomLevel: _kZoom,
    ),
  );
  return notifier;
}

const String _kAddedToast = 'تمت إضافة الوسائط إلى المسار';
const String _kWrongTrackToast = 'اسحب للمسار الصحيح';

Widget _toastProbe(List<String> log) => Consumer(
      builder: (context, ref, _) {
        for (final t in ref.watch(toastProvider)) {
          if (!log.contains(t.message)) log.add(t.message);
        }
        return const SizedBox.shrink();
      },
    );

/// Harness: [drag source above] + Row[110px spacer | Expanded(TimelineWidget)].
Widget buildHarness({
  double seedPlayhead = 0.0,
  required List<String> toastLog,
  bool useRealLibraryCard = false,
}) {
  final notifier = _seededNotifier(playhead: seedPlayhead);
  return ProviderScope(
    overrides: [
      timelineProvider.overrideWith((ref) => notifier),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                SizedBox(
                  height: useRealLibraryCard ? 220 : 100,
                  width: double.infinity,
                  child: useRealLibraryCard
                      ? MediaLibraryWidget(
                          onSelectVideo: (_) {},
                          importedFiles: [
                            MediaFile(path: '/fake/v.mp4', name: 'v.mp4'),
                          ],
                          onFileAdded: (_) {},
                          mediaInfoResolver: fakeResolver,
                        )
                      : Center(
                          child: Container(
                            key: const ValueKey('drag_card'),
                            color: Colors.deepPurple,
                            width: 90,
                            height: 60,
                            alignment: Alignment.center,
                            child: Draggable<String>(
                              data: '/fake/v.mp4',
                              // Feedback follows the pointer so the drop
                              // offset delivered to targets is exact.
                              dragAnchorStrategy: pointerDragAnchorStrategy,
                              feedback: Container(
                                width: 80,
                                height: 50,
                                color: Colors.purpleAccent,
                              ),
                              child: const Text('CARD'),
                            ),
                          ),
                        ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      const SizedBox(width: TimelineConstants.sidebarWidth),
                      Expanded(
                        child: TimelineWidget(
                          selectedClipId: null,
                          onSelectClip: (_, __) {},
                          mediaInfoResolver: fakeResolver,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _toastProbe(toastLog),
          ],
        ),
      ),
    ),
  );
}

void _useBigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Manual press→move→release so the Draggable's MultiDrag recognizer gets
/// frames to spawn the avatar and the DragTargets get real hover/drop events.
Future<void> _dragCard(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 50));
  final delta = to - from;
  await gesture.moveBy(delta * 0.5);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveBy(delta * 0.5);
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('drag & drop', () {
    testWidgets(
        '(a) drop on video lane center → startSec matches lane geometry '
        '(±0.3s — proves the old +70px magic number is dead)', (tester) async {
      _useBigSurface(tester);
      final toasts = <String>[];
      await tester.pumpWidget(buildHarness(toastLog: toasts));
      await tester.pump();

      final laneFinder = find.byKey(const ValueKey('lane_video'));
      final laneRect = tester.getRect(laneFinder);
      final laneCenter = tester.getCenter(laneFinder);
      // Pure geometry: time = (dropX − lane left edge) / zoom, scroll at 0.
      final expectedSec =
          (laneCenter.dx - laneRect.left) / _kZoom;

      final cardCenter = tester.getCenter(find.byKey(const ValueKey('drag_card')));
      await _dragCard(tester, cardCenter, laneCenter);

      final clips = readVideoClips(tester);
      expect(clips.length, 1);
      expect((clips.first.startTimeInTimeline - expectedSec).abs(), lessThan(0.3),
          reason:
              'startSec ${clips.first.startTimeInTimeline} vs geometric $expectedSec');
      // Injected resolver drove the real 8s span (not the 10s fallback).
      expect(clips.first.endTimeInTimeline - clips.first.startTimeInTimeline,
          moreOrLessEquals(8.0, epsilon: 0.01));
      expect(toasts, contains(_kAddedToast));

      await _drainTimers(tester);
    });

    testWidgets(
        '(b) drop on empty space BELOW the lanes → routed to nearest track '
        'and added at the X-derived time', (tester) async {
      _useBigSurface(tester);
      final toasts = <String>[];
      await tester.pumpWidget(buildHarness(toastLog: toasts));
      await tester.pump();

      final laneRect = tester.getRect(find.byKey(const ValueKey('lane_video')));
      final cardCenter = tester.getCenter(find.byKey(const ValueKey('drag_card')));
      // Well below the lane (inside the fallback area, outside every lane).
      final dropPoint = Offset(laneRect.left + 300, laneRect.bottom + 60);
      await _dragCard(tester, cardCenter, dropPoint);

      final clips = readVideoClips(tester);
      expect(clips.length, 1,
          reason: 'fallback must route to the nearest (only) track');
      final expectedSec = (dropPoint.dx - laneRect.left) / _kZoom;
      expect((clips.first.startTimeInTimeline - expectedSec).abs(), lessThan(0.3),
          reason:
              'startSec ${clips.first.startTimeInTimeline} vs geometric $expectedSec');
      expect(clips.first.sourcePath, '/fake/v.mp4');

      await _drainTimers(tester);
    });

    testWidgets('(c) double-tap library card → added at the current playhead',
        (tester) async {
      _useBigSurface(tester);
      final toasts = <String>[];
      await tester.pumpWidget(
        buildHarness(seedPlayhead: 5.0, toastLog: toasts, useRealLibraryCard: true),
      );
      await tester.pump();

      await tester.tap(find.text('v.mp4'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(find.text('v.mp4'), warnIfMissed: false);
      await tester.pump();
      await tester.pump();

      final clips = readVideoClips(tester);
      expect(clips.length, 1);
      // Seeded playhead was 5.0 → click-to-add lands there, not at 0.
      expect(clips.first.startTimeInTimeline, moreOrLessEquals(5.0, epsilon: 0.01));

      await _drainTimers(tester);
    });

    testWidgets('(d) locked track rejects the drop gracefully', (tester) async {
      _useBigSurface(tester);
      final toasts = <String>[];
      await tester.pumpWidget(buildHarness(toastLog: toasts));
      await tester.pump();

      // Lock the only (video) track from its sidebar button.
      await tester.tap(find.byTooltip('قفل المسار').first);
      await tester.pump();

      final laneCenter = tester.getCenter(find.byKey(const ValueKey('lane_video')));
      final cardCenter = tester.getCenter(find.byKey(const ValueKey('drag_card')));
      await _dragCard(tester, cardCenter, laneCenter);

      // With a single seeded track, locking it means "all locked" → both the
      // lane target and the fallback refuse. Either way: no clip, no crash.
      expect(readVideoClips(tester), isEmpty,
          reason: 'locked track must not receive the clip');
      expect(toasts, isNot(contains(_kAddedToast)));
      expect(toasts, isNot(contains(_kWrongTrackToast)));

      await _drainTimers(tester);
    });
  });
}

/// Fire pending toast (3s) / autosave (2s debounce) timers so the test zone
/// exits clean. Never pumpAndSettle — streams keep scheduling frames.
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 4));
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
}

/// Reads the seeded video track's clips straight off the live provider.
List<VideoClip> readVideoClips(WidgetTester tester) {
  final element = tester.element(find.byType(TimelineWidget));
  final container = ProviderScope.containerOf(element);
  return container.read(timelineProvider).timeline.tracks.video.first.clips;
}
