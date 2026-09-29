import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/features/onboarding/first_run_gate.dart';
import 'package:flutter_client/features/onboarding/onboarding_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> freshPrefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  Widget harness(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: Stack(children: [child])),
        ),
      );

  group('FirstRunGate', () {
    test('fresh prefs -> shouldShow true, markSeen flips it', () async {
      final prefs = await freshPrefs();
      expect(FirstRunGate.shouldShow(prefs), isTrue);
      await FirstRunGate.markSeen(prefs);
      expect(FirstRunGate.shouldShow(prefs), isFalse);
    });

    test('already-seen prefs -> shouldShow false', () async {
      SharedPreferences.setMockInitialValues({FirstRunGate.seenKey: true});
      final prefs = await SharedPreferences.getInstance();
      expect(FirstRunGate.shouldShow(prefs), isFalse);
    });

    test('reset clears the seen flag', () async {
      SharedPreferences.setMockInitialValues({FirstRunGate.seenKey: true});
      final prefs = await SharedPreferences.getInstance();
      expect(FirstRunGate.shouldShow(prefs), isFalse);
      await FirstRunGate.reset(prefs);
      expect(FirstRunGate.shouldShow(prefs), isTrue);
    });
  });

  group('OnboardingOverlay', () {
    testWidgets('hidden entirely when seen before', (tester) async {
      SharedPreferences.setMockInitialValues({FirstRunGate.seenKey: true});
      await tester.pumpWidget(harness(const OnboardingOverlay()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_overlay')), findsNothing);
    });

    testWidgets('fresh install: 3 steps with dots, next navigates, finish marks seen',
        (tester) async {
      final prefs = await freshPrefs();
      var dismissCalls = 0;
      await tester.pumpWidget(harness(OnboardingOverlay(
        onDismiss: () => dismissCalls++,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_overlay')), findsOneWidget);
      expect(find.text('استورد الفيديو'), findsOneWidget);
      expect(find.text('تخطي'), findsOneWidget);
      expect(find.text('التالي'), findsOneWidget);

      // Step 2 via "التالي"
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('دع الذكاء الاصطناعي يختار'), findsOneWidget);

      // Step 3 via "التالي" — primary becomes "ابدأ الآن"
      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('عدّل وصدّر'), findsOneWidget);
      expect(find.text('ابدأ الآن'), findsOneWidget);

      await tester.tap(find.text('ابدأ الآن'));
      await tester.pumpAndSettle();

      expect(dismissCalls, 1);
      expect(FirstRunGate.shouldShow(prefs), isFalse);
      expect(find.byKey(const Key('onboarding_overlay')), findsNothing);
    });

    testWidgets('skip dismiss marks seen and hides overlay', (tester) async {
      final prefs = await freshPrefs();
      var dismissCalls = 0;
      await tester.pumpWidget(harness(OnboardingOverlay(
        onDismiss: () => dismissCalls++,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('onboarding_dismiss_button')));
      await tester.pumpAndSettle();

      expect(dismissCalls, 1);
      expect(FirstRunGate.shouldShow(prefs), isFalse);
      expect(find.byKey(const Key('onboarding_overlay')), findsNothing);
    });

    testWidgets('replay provider shows the overlay again', (tester) async {
      SharedPreferences.setMockInitialValues({FirstRunGate.seenKey: true});
      await tester.pumpWidget(harness(const OnboardingOverlay()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onboarding_overlay')), findsNothing);

      // Simulate the Settings "إعادة عرض الشرح" action.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      container.read(onboardingReplayProvider.notifier).state = true;
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('onboarding_overlay')), findsOneWidget);
    });
  });
}
