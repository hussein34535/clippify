import 'package:flutter/material.dart';
import 'package:flutter_client/mobile_lite/flow_screen.dart';
import 'package:flutter_client/mobile_lite/models.dart';
import 'package:flutter_client/mobile_lite/studio_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final videoPicker = find.text('اختار فيديو');
  final options = find.text('إعدادات المقطع (اختياري)');
  final start = find.widgetWithText(FilledButton, 'يلا ابدأ المونتاج');
  final providerSettings = find.byTooltip('إعدادات الذكاء الاصطناعي');

  void stubPicker(Future<List<String>> Function() picker) {
    final original = pickVideoFile;
    pickVideoFile = picker;
    addTearDown(() => pickVideoFile = original);
  }

  testWidgets('picks a video and starts with defaults on the same screen', (
    tester,
  ) async {
    const videoPath = r'C:\videos\clip.mp4';
    stubPicker(() async => [videoPath]);

    (LiteAnswers, String)? result;
    await tester.pumpWidget(
      MaterialApp(
        home: LiteFlowScreen(
          onReady: (answers, path) => result = (answers, path),
        ),
      ),
    );
    final route = ModalRoute.of(tester.element(find.byType(LiteFlowScreen)));

    expect(find.byType(LiteFlowScreen), findsOneWidget);
    expect(find.text('حوّل فيديوك لريل جاهز'), findsOneWidget);
    expect(start, findsNothing);
    expect(options, findsNothing);
    expect(providerSettings, findsNothing);

    await tester.tap(videoPicker);
    await tester.pumpAndSettle();

    expect(find.text('clip.mp4'), findsOneWidget);
    expect(options, findsOneWidget);
    expect(find.text('مقطع واحد لمنصة تيك توك · 45 ثانية'), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(LiteFlowScreen))),
      same(route),
    );
    expect(result, isNull);

    await tester.tap(start);
    await tester.pumpAndSettle();

    final (answers, path) = result!;
    expect(path, videoPath);
    expect(answers.platform, LitePlatform.tiktok);
    expect(answers.length.seconds, 45);
  });

  testWidgets('lets the user override the platform and target duration', (
    tester,
  ) async {
    stubPicker(() async => ['/tmp/clip.mp4']);
    LiteAnswers? result;
    await tester.pumpWidget(
      MaterialApp(
        home: LiteFlowScreen(onReady: (answers, _) => result = answers),
      ),
    );
    await tester.tap(videoPicker);
    await tester.pumpAndSettle();
    final reaction = find.widgetWithText(ChoiceChip, 'رد فعل');
    await tester.ensureVisible(reaction);
    await tester.tap(reaction);
    await tester.pumpAndSettle();
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();

    ChoiceChip chip(String label) =>
        tester.widget(find.widgetWithText(ChoiceChip, label));

    expect(find.widgetWithText(ChoiceChip, 'ريلز'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'شورتس'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'يوتيوب'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, '30 ثانية'), findsOneWidget);
    expect(chip('45 ثانية').selected, isTrue);
    expect(chip('تيك توك').selected, isTrue);

    final shorts = find.widgetWithText(ChoiceChip, 'شورتس');
    final sixty = find.widgetWithText(ChoiceChip, '60 ثانية');
    await tester.ensureVisible(shorts);
    await tester.pumpAndSettle();
    await tester.tap(shorts);
    await tester.ensureVisible(sixty);
    await tester.pumpAndSettle();
    await tester.tap(sixty);
    await tester.pumpAndSettle();

    expect(chip('شورتس').selected, isTrue);
    expect(chip('60 ثانية').selected, isTrue);
    expect(find.text('مقطع واحد لمنصة شورتس · 60 ثانية'), findsOneWidget);

    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(result?.platform, LitePlatform.shorts);
    expect(result?.length.seconds, 60);
    expect(result?.creative, LiteCreative.reaction);
  });

  testWidgets('cancelling the picker keeps the previous video if any', (
    tester,
  ) async {
    final picks = <List<String>>[
      [],
      ['/tmp/clip.mp4'],
      [],
    ].iterator;
    stubPicker(() async {
      picks.moveNext();
      return picks.current;
    });
    await tester.pumpWidget(
      MaterialApp(home: LiteFlowScreen(onReady: (_, _) {})),
    );

    await tester.tap(videoPicker);
    await tester.pumpAndSettle();
    expect(options, findsNothing);
    expect(start, findsNothing);

    await tester.tap(videoPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('غيّر الفيديو'));
    await tester.pumpAndSettle();

    expect(find.text('clip.mp4'), findsOneWidget);
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
  });

  testWidgets('opens provider settings when the callback is supplied', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LiteFlowScreen(
          onReady: (_, _) {},
          onProviderSettings: () => opened = true,
        ),
      ),
    );

    await tester.tap(providerSettings);
    expect(opened, isTrue);
  });

  testWidgets('primary action stays accessible on a narrow RTL phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    stubPicker(() async => ['/tmp/الفيديو الطويل للتجربة.mp4']);
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(ThemeData.dark()),
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 620),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: LiteFlowScreen(onReady: (_, path) => picked = path),
      ),
    );
    await tester.tap(videoPicker);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(options, 140);
    await tester.ensureVisible(options);
    await tester.pumpAndSettle();
    await tester.tap(options);
    await tester.pumpAndSettle();
    expect(find.text('30 ثانية'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(start.hitTestable());
    expect(picked, '/tmp/الفيديو الطويل للتجربة.mp4');
  });
}
