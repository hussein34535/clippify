import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/features/command_palette/palette.dart';
import 'package:flutter_client/features/command_palette/registry.dart';
import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/shared/widgets/keyboard_shortcuts.dart';

PaletteCommand _fakeCmd(String id, List<String> calls) {
  return PaletteCommand(
    id: id,
    labelAr: 'أمر $id',
    icon: Icons.star,
    action: (_) => calls.add(id),
  );
}

Future<void> _pumpPalette(
  WidgetTester tester,
  List<PaletteCommand> commands,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showCommandPalette(context, commands),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('filter narrows results by query', (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [
      _fakeCmd('undo', calls),
      _fakeCmd('redo', calls),
      _fakeCmd('export', calls),
    ]);

    expect(find.byKey(const ValueKey('palette_row_undo_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette_row_redo_1')), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'أمر un');
    await tester.pump();

    expect(find.byKey(const ValueKey('palette_row_undo_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette_row_redo_0')), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('arrow down moves selection highlight', (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [
      _fakeCmd('a', calls),
      _fakeCmd('b', calls),
      _fakeCmd('c', calls),
    ]);

    expect(find.byKey(const ValueKey('palette_selected_0')), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const ValueKey('palette_selected_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('palette_selected_0')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byKey(const ValueKey('palette_selected_0')), findsOneWidget);
  });

  testWidgets('selection clamps at list bounds', (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [_fakeCmd('only', calls)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byKey(const ValueKey('palette_selected_0')), findsOneWidget);
  });

  testWidgets('Enter runs selected command and closes palette',
      (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [_fakeCmd('doit', calls)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(calls, ['doit']);
    expect(find.byType(CommandPaletteOverlay), findsNothing);
  });

  testWidgets('Escape closes palette without running anything',
      (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [_fakeCmd('nope', calls)]);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.byType(CommandPaletteOverlay), findsNothing);
  });

  testWidgets('empty query shows all; no match shows لا نتائج',
      (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [
      _fakeCmd('x1', calls),
      _fakeCmd('x2', calls),
    ]);

    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('لا نتائج'), findsNothing);

    await tester.enterText(find.byType(TextField), 'غير موجود إطلاقاً');
    await tester.pump();

    expect(find.text('لا نتائج'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('click runs command and closes', (tester) async {
    final calls = <String>[];
    await _pumpPalette(tester, [_fakeCmd('clickme', calls)]);

    await tester.tap(find.byKey(const ValueKey('palette_row_clickme_0')));
    await tester.pumpAndSettle();

    expect(calls, ['clickme']);
    expect(find.byType(CommandPaletteOverlay), findsNothing);
  });

  testWidgets('disabled command shows reason and does nothing on Enter',
      (tester) async {
    final calls = <String>[];
    final disabled = PaletteCommand(
      id: 'auto_edit',
      labelAr: 'مونتاج تلقائي',
      icon: Icons.auto_awesome,
      enabled: false,
      disabledReason: 'اختر فيديو أولاً',
      action: (_) => calls.add('auto_edit'),
    );
    await _pumpPalette(tester, [disabled]);

    expect(find.text('اختر فيديو أولاً'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(calls, isEmpty);
    expect(find.byType(CommandPaletteOverlay), findsOneWidget);
  });

  testWidgets('Ctrl+K on KeyboardShortcutsWidget opens palette with defaults',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: KeyboardShortcutsWidget(
            child: Scaffold(body: SizedBox()),
          ),
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('اكتب أمراً…'), findsOneWidget);
    expect(find.byType(CommandPaletteOverlay), findsOneWidget);
    expect(find.text('تراجع'), findsOneWidget);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('اختر فيديو أولاً'), findsOneWidget);
  });

  group('firstVideoSourcePath (pure)', () {
    TimelineState stateWith(List<VideoTrack> video) => TimelineState(
          projectId: 'p',
          projectName: 'p',
          settings: TimelineSettings(),
          tracks: Tracks(
            video: video,
            audio: const [],
            subtitles: const [],
            overlays: const [],
            text: const [],
          ),
        );

    VideoClip vclip(String id, String path) => VideoClip(
          id: id,
          sourcePath: path,
          startTimeInTimeline: 0,
          endTimeInTimeline: 5,
          sourceTrimStart: 0,
          sourceTrimEnd: 5,
          transform: TransformState.defaultState(),
          colorGrading: ColorGradingState(),
          filters: const [],
          aiFeatures: AIFeatures(),
        );

    test('empty timeline → null', () {
      expect(firstVideoSourcePath(TimelineState.empty()), isNull);
    });

    test('returns first clip of first non-empty track', () {
      final state = stateWith([
        VideoTrack(id: 'v0', name: 'V0', index: 0, clips: const []),
        VideoTrack(
            id: 'v1', name: 'V1', index: 1, clips: [vclip('c1', 'b.mp4')]),
      ]);
      expect(firstVideoSourcePath(state), 'b.mp4');
    });
  });
}
