import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/shared/widgets/keyboard_shortcuts.dart';

/// حارس الكتابة: الاختصارات العارية لا تعمل داخل حقول النص.
void main() {
  Future<void> pumpHarness(
    WidgetTester tester, {
    required List<String> calls,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: KeyboardShortcutsWidget(
              onAddText: () => calls.add('add_text'),
              onSplit: () => calls.add('split'),
              onSave: () => calls.add('save'),
              child: Column(
                children: const [
                  TextField(key: Key('field')),
                  Expanded(child: SizedBox(key: Key('body'))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('bare letters are swallowed while typing', (tester) async {
    final calls = <String>[];
    await pumpHarness(tester, calls: calls);

    await tester.tap(find.byKey(const Key('field')));
    await tester.pump();
    expect(KeyboardShortcutsWidget.isEditingNow(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(calls, isEmpty);
  });

  testWidgets('bare letters fire when not editing', (tester) async {
    final calls = <String>[];
    await pumpHarness(tester, calls: calls);

    // التركيز على الجسم لا حقل النص.
    await tester.tap(find.byKey(const Key('body')));
    await tester.pump();
    expect(KeyboardShortcutsWidget.isEditingNow(), isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(calls, ['add_text']);
  });

  testWidgets('Ctrl+S is separate from bare S', (tester) async {
    final calls = <String>[];
    await pumpHarness(tester, calls: calls);

    await tester.tap(find.byKey(const Key('body')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(calls, ['save']);
  });

  testWidgets('ShortcutsDialog lists the real bindings', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ShortcutsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // القائمة أطول من النافذة (بناء كسول) — اسحب حتى يظهر كل عنصر.
    Future<void> reveal(String label) async {
      for (var i = 0;
          i < 12 && find.text(label).evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      expect(find.text(label), findsOneWidget);
    }

    await reveal('حفظ المشروع');
    await reveal('قص عند المؤشر');
    // شارة S العارية بجانب القص (لا Ctrl+S) — مرئية مع نفس الصف.
    expect(find.text('S'), findsOneWidget);
    await reveal('هذه القائمة');
  });
}
