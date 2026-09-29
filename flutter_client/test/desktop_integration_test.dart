import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/core/backend/auth_store.dart';
import 'package:flutter_client/features/auth/auth_screen.dart';
import 'package:flutter_client/features/layout/widgets/account_sheet.dart';
import 'package:flutter_client/features/layout/widgets/header.dart';
import 'package:flutter_client/features/layout/widgets/settings_modal.dart';

// ─────────────────────────────────────────────
//  Test doubles
// ─────────────────────────────────────────────

class _FakeTokenStore implements TokenStore {
  String? access;
  String? refresh;
  bool cleared = false;

  _FakeTokenStore({this.access, this.refresh});

  @override
  Future<void> saveTokens(
      {required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<String?> readRefresh() async => refresh;

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    cleared = true;
  }
}

class _NeverAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('{"detail":"offline"}', 503);

  @override
  void close({bool force = false}) {}
}

const _testUser = AuthUser(
  id: 'u1',
  email: 'ahmed@test.dev',
  name: 'أحمد',
  plan: 'pro',
  creditsUsed: 4,
  creditsLimit: 30,
);

AuthNotifier _fakeAuthNotifier({_FakeTokenStore? store}) => AuthNotifier(
      tokenStore: store ?? _FakeTokenStore(),
      dioOverride:
          Dio(BaseOptions(baseUrl: 'http://test.local'))
            ..httpClientAdapter = _NeverAdapter(),
      baseUrlOverride: 'http://test.local',
    );

Widget _app({List<Override> overrides = const []}) => ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        home: Scaffold(body: HeaderWidget()),
      ),
    );

void main() {
  setUpAll(() {
    // appPrefsProvider (الهيدر) يقرأ SharedPreferences عند الإنشاء.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Header — زر الحساب', () {
    testWidgets('يُعرض زر الحساب مع tooltip «حسابي»', (tester) async {
      await tester.pumpWidget(_app(
        overrides: [
          authStateProvider.overrideWith((ref) => _fakeAuthNotifier()),
        ],
      ));
      await tester.pump();

      expect(find.byIcon(Icons.account_circle_rounded), findsOneWidget);
      expect(find.byTooltip('حسابي'), findsOneWidget);
    });

    testWidgets('غير مسجل الدخول → لا نقطة خضراء', (tester) async {
      await tester.pumpWidget(_app(
        overrides: [
          authStateProvider.overrideWith((ref) => _fakeAuthNotifier()),
        ],
      ));
      await tester.pump();

      expect(find.byKey(kAccountBadgeDotKey), findsNothing);
    });

    testWidgets('مسجل الدخول → نقطة خضراء تظهر', (tester) async {
      final notifier = _fakeAuthNotifier(
        store: _FakeTokenStore(access: 'a', refresh: 'r'),
      );
      notifier.state = const AuthState(
        status: AuthStatus.authenticated,
        user: _testUser,
      );

      await tester.pumpWidget(_app(
        overrides: [authStateProvider.overrideWith((ref) => notifier)],
      ));
      await tester.pump();

      expect(find.byKey(kAccountBadgeDotKey), findsOneWidget);
    });

    testWidgets('النقر يفتح الورقة وتظهر شاشة الدخول المدمجة', (tester) async {
      // ورقة الحساب أطول من السطح الافتراضي — نكبّر السطح لتجنب overflow.
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(
        overrides: [
          authStateProvider.overrideWith((ref) => _fakeAuthNotifier()),
        ],
      ));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.account_circle_rounded));
      // إطاران ثابتان لإكمال أنيميشن الـ bottom sheet — بلا pumpAndSettle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AuthScreen), findsOneWidget);
      expect(find.text('مرحباً بك في Clippify'), findsOneWidget);
    });
  });

  group('Account sheet — منطق العرض النقي', () {
    test('ألوان وشعارات الخطط: free رمادي / pro بنفسجي / studio ذهبي', () {
      expect(planChipColor('free'), const Color(0xFF8E8E93));
      expect(planChipColor('pro'), const Color(0xFF8B5CF6));
      expect(planChipColor('studio'), const Color(0xFFFFD60A));
      expect(planChipLabel('free'), 'Free');
      expect(planChipLabel('pro'), 'Pro');
      expect(planChipLabel('studio'), 'Studio');
    });
  });

  group('Settings modal — قسم وضع التشغيل', () {
    test('shouldShowCloudSection — دالة نية قابلة للاختبار', () {
      // على Windows يظهر القسم؛ خارجه مخفي تماماً (لا يمكن محاكاة
      // Platform.isWindows في الاختبارات، لذلك الحارس مستخرج هنا).
      expect(SettingsModal.shouldShowCloudSection(isWindows: true), isTrue);
      expect(SettingsModal.shouldShowCloudSection(isWindows: false), isFalse);
    });
  });

  group('BackendModePref — persistence roundtrip', () {
    test('حفظ ثم قراءة عبر SharedPreferences وهمي', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      expect(await BackendModePref.load(), isNull);

      await BackendModePref.save('cloud');
      expect(await BackendModePref.load(), 'cloud');

      await BackendModePref.save('local');
      expect(await BackendModePref.load(), 'local');
    });

    test('قيمة غير معروفة → null وليست crash', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        BackendModePref.key: 'bogus',
      });

      expect(await BackendModePref.load(), isNull);
    });
  });
}
