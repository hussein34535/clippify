import 'package:flutter/material.dart';
import 'package:flutter_client/mobile_lite/flow_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiteFlowScreen (standalone assistant)', () {
    testWidgets('walks platform → content → length → touches → pick',
        (tester) async {
      final orig = pickVideoFile;
      pickVideoFile = () async => ['/tmp/vid.mp4'];
      addTearDown(() => pickVideoFile = orig);

      String? gotPath;
      await tester.pumpWidget(
        MaterialApp(
          home: LiteFlowScreen(
            onReady: (_, path) => gotPath = path,
          ),
        ),
      );

      // Q1: منصة
      expect(find.text('إيه المنصة؟'), findsOneWidget);
      await tester.tap(find.text('تيك توك'));
      await tester.pumpAndSettle();

      // Q2: محتوى
      expect(find.text('الفيديو عن إيه؟'), findsOneWidget);
      await tester.tap(find.text('كوميدي'));
      await tester.pumpAndSettle();

      // Q3: مدة
      expect(find.text('عايزه طوله قد إيه؟'), findsOneWidget);
      await tester.tap(find.textContaining('قصير'));
      await tester.pumpAndSettle();

      // Q4: لمسات
      expect(find.text('اللمسات الأخيرة'), findsOneWidget);
      await tester.tap(find.text('نيون'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('كمّل لاختيار الفيديو'));
      await tester.pumpAndSettle();

      // اختيار فيديو (محقون)
      expect(find.text('اختار الفيديو'), findsOneWidget);
      await tester.tap(find.text('اختار فيديو'));
      await tester.pumpAndSettle();
      expect(find.textContaining('vid.mp4'), findsOneWidget);

      await tester.tap(find.text('راجع وابدأ'));
      await tester.pumpAndSettle();

      // مراجعة + بدء
      expect(find.textContaining('3 مقاطع'), findsOneWidget);
      await tester.tap(find.text('يلا ابدأ المونتاج'));
      await tester.pumpAndSettle();
      expect(gotPath, '/tmp/vid.mp4');
    });

    testWidgets('back button returns to previous question', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiteFlowScreen(onReady: (_, __) {}),
        ),
      );
      await tester.tap(find.text('تيك توك'));
      await tester.pumpAndSettle();
      expect(find.text('الفيديو عن إيه؟'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('إيه المنصة؟'), findsOneWidget);
    });
  });
}
