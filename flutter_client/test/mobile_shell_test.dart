import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/core/backend/auto_edit_api.dart';
import 'package:flutter_client/core/backend/auth_store.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/auth/profile_screen.dart';
import 'package:flutter_client/features/mobile/library_mobile_page.dart';
import 'package:flutter_client/features/mobile/wizard_mobile_page.dart'
    show answersFromMap, WizardPageMobile;
import 'package:flutter_client/features/shell/device_profile.dart';
import 'package:flutter_client/features/shell/mobile_home_shell.dart';
import 'package:flutter_client/features/wizard/auto_edit_progress_screen.dart';
import 'package:flutter_client/features/wizard/auto_edit_wizard_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────

class FakeAutoEditApi implements AutoEditApi {
  final controller = StreamController<AutoEditEvent>.broadcast();
  int startCalls = 0;
  int cancelCalls = 0;
  String? nextSessionId = 'sidX';
  final startedAnswers = <AutoEditAnswers>[];
  final startedPaths = <String>[];

  @override
  Future<String?> start(String videoPath, AutoEditAnswers answers) async {
    startCalls++;
    startedAnswers.add(answers);
    startedPaths.add(videoPath);
    return nextSessionId;
  }

  @override
  Stream<AutoEditEvent> subscribeProgress(String sessionId) =>
      controller.stream;

  @override
  Future<Map<String, dynamic>?> status(String sessionId) async => null;

  @override
  Future<bool> cancel(String sessionId) async {
    cancelCalls++;
    return true;
  }

  void dispose() => controller.close();
}

/// In-memory TokenStore — avoids flutter_secure_storage platform channels.
class MemTokenStore implements TokenStore {
  final _values = <String, String>{};

  @override
  Future<void> saveTokens({required String access, required String refresh}) =>
      Future.sync(() {
        _values[kAccessTokenKey] = access;
        _values[kRefreshTokenKey] = refresh;
      });

  @override
  Future<String?> readAccess() async => _values[kAccessTokenKey];

  @override
  Future<String?> readRefresh() async => _values[kRefreshTokenKey];

  @override
  Future<void> clear() => Future.sync(_values.clear);
}

Override authOverride(AuthStatus status, {AuthUser? user}) =>
    authStateProvider.overrideWith((ref) {
      return AuthNotifier(tokenStore: MemTokenStore())
        ..state = AuthState(status: status, user: user);
    });

const _testUser = AuthUser(
  id: 'u1',
  email: 'user@clippify.app',
  name: 'مستخدم',
  plan: 'free',
  creditsUsed: 1,
  creditsLimit: 3,
);

void _useBigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
}

// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('device_profile', () {
    test('isCompactWidth threshold is strictly below 600dp', () {
      expect(isCompactWidth(0), isTrue);
      expect(isCompactWidth(599.9), isTrue);
      expect(isCompactWidth(kCompactBreakpoint - 0.1), isTrue);
      expect(isCompactWidth(kCompactBreakpoint), isFalse);
      expect(isCompactWidth(1200), isFalse);
    });

    testWidgets('isCompact reads MediaQuery width (rotation-aware)',
        (tester) async {
      // Default test surface 800x600 → wide desktop.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Directionality(
              textDirection: TextDirection.ltr,
              child: Text(isCompact(context) ? 'COMPACT' : 'WIDE'),
            ),
          ),
        ),
      );
      expect(find.text('WIDE'), findsOneWidget);

      // Simulate a phone in portrait.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(500, 800);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Directionality(
              textDirection: TextDirection.ltr,
              child: Text(isCompact(context) ? 'COMPACT' : 'WIDE'),
            ),
          ),
        ),
      );
      expect(find.text('COMPACT'), findsOneWidget);
    });
  });

  group('answersFromMap', () {
    test('maps CONTRACTS answer keys onto typed AutoEditAnswers', () {
      const m = <String, dynamic>{
        'content_type': 'podcast',
        'platform': 'reels',
        'n_clips': 7,
        'clip_duration_sec': 45,
        'caption_theme': 'Neon',
        'music': true,
        'broll': false,
        'translate_arabic': true,
        'custom_instructions': 'ركّز على الضحك',
      };
      final a = answersFromMap(m);
      expect(a.contentType, 'podcast');
      expect(a.platform, 'reels');
      expect(a.nClips, 7);
      expect(a.clipDurationSec, 45.0);
      expect(a.captionTheme, 'Neon');
      expect(a.music, isTrue);
      expect(a.broll, isFalse);
      expect(a.translateArabic, isTrue);
      expect(a.customInstructions, 'ركّز على الضحك');
    });

    test('falls back to contract defaults for missing keys', () {
      final a = answersFromMap(const {});
      final d = const AutoEditAnswers().toJson();
      expect(a.toJson(), d);
    });
  });

  group('MobileHomeShell', () {
    Widget wrapShell({
      VoidCallback? onLogout,
      AuthStatus authStatus = AuthStatus.unauthenticated,
    }) =>
        ProviderScope(
          overrides: [
            authOverride(authStatus, user: _testUser),
          ],
          child: MaterialApp(home: MobileHomeShell(onLogout: onLogout)),
        );

    setUpAll(() {
      // Silence the real provider if it ever leaks (defensive).
    });

    testWidgets('renders 4 navigation destinations', (tester) async {
      await tester.pumpWidget(wrapShell());
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 4);
      expect(find.text('Clippify'), findsOneWidget);
    });

    testWidgets('switching tabs updates index and preserves state',
        (tester) async {
      await tester.pumpWidget(wrapShell());

      // Go to ✨مونتاج and type a custom instruction.
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pump();
      var navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);

      await tester.enterText(
        find.descendant(
          of: find.byType(WizardPageMobile),
          matching: find.byType(TextField),
        ),
        'keep-me',
      );
      await tester.pump();

      // Switch away to حسابك — unauthenticated override → AuthScreen embedded…
      await tester.tap(find.byIcon(Icons.person_outline));
      await tester.pump();
      navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 3);
      expect(find.text('مرحباً بك في Clippify'), findsOneWidget);

      // …and back: IndexedStack must have preserved the wizard text.
      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pump();
      expect(find.text('keep-me'), findsOneWidget);

      // Results tab shows the honest empty-state pointer back to the library.
      await tester.tap(find.byIcon(Icons.movie_outlined));
      await tester.pump();
      expect(find.text('ابدأ من المكتبة'), findsOneWidget);
      expect(find.text('سجل النتائج يظهر هنا بعد اكتمال أول عملية'),
          findsOneWidget);
      // Nothing written kLastOutputDirPrefKey yet (v1) → button disabled.
      final openDirBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'فتح آخر مجلد تصدير'),
      );
      expect(openDirBtn.onPressed, isNull);
    });
  });

  group('LibraryPageMobile', () {
    Widget wrap(LibraryPageMobile page) => ProviderScope(
          child: MaterialApp(home: Scaffold(body: page)),
        );

    testWidgets('injected picker returns two paths → two tiles appear',
        (tester) async {
      _useBigSurface(tester);
      await tester.pumpWidget(wrap(LibraryPageMobile(
        pickVideos: () async => ['/fake/a.mp4', '/fake/b.mp4'],
      )));
      expect(find.text('مكتبتك فاضية'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('a.mp4'), findsOneWidget);
      expect(find.text('b.mp4'), findsOneWidget);

      final gridView =
          tester.widget<GridView>(find.byType(GridView).first);
      final delegate =
          gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 2);
    });

    testWidgets('tile popup keeps share/delete entries', (tester) async {
      _useBigSurface(tester);
      var shared = false;
      await tester.pumpWidget(wrap(LibraryPageMobile(
        onShareFile: (_) async => shared = true,
        pickVideos: () async => ['/fake/demo.mp4'],
      )));

      // يصرف مؤقت سناك بار الإضافة (4 ثوان) حتى لا يحجب الـ FAB لاحقاً.
      Future<void> drainPickSnack() async {
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(seconds: 1));
      }

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await drainPickSnack();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('✨ مونتاج تلقائي'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.text('حذف'), findsOneWidget);

      await tester.tap(find.text('حذف'));
      await tester.pumpAndSettle();
      expect(find.text('demo.mp4'), findsNothing);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await drainPickSnack();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('مشاركة'));
      await tester.pumpAndSettle();
      expect(shared, isTrue);
    });

    testWidgets('tile popup ✨ مونتاج تلقائي pushes route hosting '
        'AutoEditWizardDialog with injected api', (tester) async {
      _useBigSurface(tester);
      final api = FakeAutoEditApi();
      await tester.pumpWidget(wrap(LibraryPageMobile(
        wizardApi: api,
        pickVideos: () async => ['/fake/demo.mp4'],
      )));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('✨ مونتاج تلقائي'));
      await tester.pumpAndSettle();

      // Full-screen route hosting the existing desktop wizard panel.
      expect(find.byType(AutoEditWizardDialog), findsOneWidget);
      expect(find.text('🪄 المونتاج التلقائي الذكي'), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard_submit')), findsOneWidget);

      // Submitting from the hosted dialog uses the injected api and pushes
      // the real progress screen on top.
      await tester.tap(find.byKey(const ValueKey('wizard_submit')));
      await tester.pumpAndSettle();

      expect(api.startCalls, 1);
      expect(api.startedPaths.single, '/fake/demo.mp4');
      expect(find.byType(AutoEditProgressScreen), findsOneWidget);

      await _unmount(tester);
    });
  });

  group('WizardPageMobile', () {
    Widget wrap(WizardPageMobile page) => ProviderScope(
          child: MaterialApp(home: Scaffold(body: page)),
        );

    testWidgets('submit disabled until a video is picked', (tester) async {
      _useBigSurface(tester);
      await tester.pumpWidget(wrap(WizardPageMobile(
        pickVideos: () async => ['/fake/demo.mp4'],
      )));

      final submitFinder = find.text('ابدأ المونتاج');
      expect(
        tester.widget<FilledButton>(find.ancestor(
          of: submitFinder,
          matching: find.byType(FilledButton),
        )).onPressed,
        isNull,
      );
    });

    testWidgets('submit with fake api sid=sidX pushes AutoEditProgressScreen',
        (tester) async {
      _useBigSurface(tester);
      final api = FakeAutoEditApi()..nextSessionId = 'sidX';
      await tester.pumpWidget(wrap(WizardPageMobile(
        api: api,
        pickVideos: () async => ['/fake/demo.mp4'],
      )));

      await tester.tap(find.text('اختر فيديو'));
      await tester.pumpAndSettle();
      expect(find.text('demo.mp4'), findsOneWidget);

      // Flip a chip so the conversion map→typed object is observable.
      await tester.tap(find.text('ريلز'));
      await tester.pump();

      await tester.tap(find.text('ابدأ المونتاج'));
      await tester.pump(); // setState(_submitting)
      await tester.pump(); // await api.start + navigator.push
      await tester.pumpAndSettle();

      expect(api.startCalls, 1);
      expect(api.startedPaths.single, '/fake/demo.mp4');
      expect(api.startedAnswers.first.platform, 'reels');
      expect(api.startedAnswers.first.contentType, 'auto');
      expect(api.startedAnswers.first.nClips, 5);
      expect(api.startedAnswers.first.broll, isTrue);

      expect(find.byType(AutoEditProgressScreen), findsOneWidget);
      expect(find.textContaining('sidX'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('submit with null session shows error snackbar and stays',
        (tester) async {
      _useBigSurface(tester);
      final api = FakeAutoEditApi()..nextSessionId = null;
      await tester.pumpWidget(wrap(WizardPageMobile(
        api: api,
        pickVideos: () async => ['/fake/demo.mp4'],
      )));

      await tester.tap(find.text('اختر فيديو'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ابدأ المونتاج'));
      await tester.pump();
      await tester.pump();

      expect(api.startCalls, 1);
      expect(find.byType(AutoEditProgressScreen), findsNothing);
      expect(find.textContaining('فشل بدء المونتاج'), findsOneWidget);
      // Re-enabled after failure so the user can retry.
      expect(
        tester.widget<FilledButton>(find.ancestor(
          of: find.text('ابدأ المونتاج'),
          matching: find.byType(FilledButton),
        )).onPressed,
        isNotNull,
      );

      // صرف مؤقت السناك بار (4 ثوان) قبل نهاية الاختبار.
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 1));
      await _unmount(tester);
    });
  });

  group('ProfilePageMobile', () {
    testWidgets('unauthenticated → AuthScreen embedded', (tester) async {
      _useBigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [authOverride(AuthStatus.unauthenticated)],
        child: const MaterialApp(home: Scaffold(body: ProfilePageMobile())),
      ));
      await tester.pump();

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.text('مرحباً بك في Clippify'), findsOneWidget);
    });

    testWidgets('authenticated → ProfileScreen embedded with user data',
        (tester) async {
      _useBigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authOverride(AuthStatus.authenticated, user: _testUser),
        ],
        child: const MaterialApp(home: Scaffold(body: ProfilePageMobile())),
      ));
      await tester.pump();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.text('user@clippify.app'), findsOneWidget);
      expect(find.text('الأرصدة المستخدمة'), findsOneWidget);
    });

    testWidgets('loading → spinner', (tester) async {
      _useBigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [authOverride(AuthStatus.loading)],
        child: const MaterialApp(home: Scaffold(body: ProfilePageMobile())),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AuthScreen), findsNothing);
    });
  });
}
