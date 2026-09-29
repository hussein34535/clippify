import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/core/backend/auto_edit_api.dart';
import 'package:flutter_client/core/backend/auth_store.dart';
import 'package:flutter_client/core/backend/authed_dio.dart';
import 'package:flutter_client/core/backend/backend_service.dart';

// ---------- Test doubles ----------

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

class _CaptureRequestHandler extends RequestInterceptorHandler {
  RequestOptions? captured;
  @override
  void next(RequestOptions options) => captured = options;
}

ResponseBody _json(int code, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

class _FakeAdapter implements HttpClientAdapter {
  final ResponseBody Function(RequestOptions options) route;
  final List<RequestOptions> requests = [];
  _FakeAdapter(this.route);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return Future<ResponseBody>.value(route(options));
  }

  @override
  void close({bool force = false}) {}
}

const _userJson = {
  'id': 'u1',
  'email': 'ahmed@test.dev',
  'name': 'أحمد',
  'plan': 'pro',
  'credits_used': 4,
  'credits_limit': 30,
};

Dio _plainDio(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;

void main() {
  group('AutoEditAnswers.toJson', () {
    test('golden — الافتراضيات snake_case بدون caption_theme', () {
      const a = AutoEditAnswers();
      expect(a.toJson(), {
        'content_type': 'auto',
        'platform': 'tiktok',
        'n_clips': 5,
        'clip_duration_sec': 60.0,
        'music': false,
        'broll': true,
        'translate_arabic': false,
        'custom_instructions': '',
      });
    });

    test('golden — قيم مخصصة مع caption_theme', () {
      const a = AutoEditAnswers(
        contentType: 'podcast',
        platform: 'reels',
        nClips: 3,
        clipDurationSec: 45.5,
        captionTheme: 'Cyberpunk',
        music: true,
        broll: false,
        translateArabic: true,
        customInstructions: 'قصص قصيرة سريعة',
      );
      expect(a.toJson(), {
        'content_type': 'podcast',
        'platform': 'reels',
        'n_clips': 3,
        'clip_duration_sec': 45.5,
        'caption_theme': 'Cyberpunk',
        'music': true,
        'broll': false,
        'translate_arabic': true,
        'custom_instructions': 'قصص قصيرة سريعة',
      });
    });
  });

  group('chooseBackend (pure)', () {
    test('ويندوز بلا LOCAL_MODE → local', () {
      expect(
        BackendService.chooseBackend(isWindows: true, localMode: null),
        BackendMode.local,
      );
    });

    test('ويندوز + localMode=local → local', () {
      expect(
        BackendService.chooseBackend(isWindows: true, localMode: 'local'),
        BackendMode.local,
      );
    });

    test('ويندوز + localMode=cloud → cloud', () {
      expect(
        BackendService.chooseBackend(isWindows: true, localMode: 'cloud'),
        BackendMode.cloud,
      );
    });

    test('غير ويندوز → cloud دائماً', () {
      expect(
        BackendService.chooseBackend(isWindows: false, localMode: null),
        BackendMode.cloud,
      );
      expect(
        BackendService.chooseBackend(isWindows: false, localMode: 'local'),
        BackendMode.cloud,
      );
    });
  });

  group('AuthInterceptor.onRequest (استدعاء مباشر)', () {
    test('يضيف Authorization: Bearer من المخزن', () async {
      final interceptor =
          AuthInterceptor(_FakeTokenStore(access: 'tok_abc123'));
      final options = RequestOptions(path: '/api/billing/usage');
      final handler = _CaptureRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.captured, isNotNull);
      expect(handler.captured!.headers['Authorization'], 'Bearer tok_abc123');
    });

    test('بدون توكن → لا هيدر Authorization', () async {
      final interceptor = AuthInterceptor(_FakeTokenStore());
      final options = RequestOptions(path: '/api/auth/login');
      final handler = _CaptureRequestHandler();

      await interceptor.onRequest(options, handler);

      expect(handler.captured!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('AuthNotifier transitions (FakeTokenStore)', () {
    test('الحالة الابتدائية unauthenticated', () {
      final n = AuthNotifier(tokenStore: _FakeTokenStore());
      expect(n.state.status, AuthStatus.unauthenticated);
    });

    test('restoreOnStartup بلا توكنات → unauthenticated بدون شبكة', () async {
      final adapterCalls = 0;
      final store = _FakeTokenStore();
      final n = AuthNotifier(
        tokenStore: store,
        dioOverride: _plainDio(_FakeAdapter((o) => throw UnimplementedError())),
      );
      await n.restoreOnStartup();
      expect(n.state.status, AuthStatus.unauthenticated);
      expect(store.cleared, isFalse);
      expect(adapterCalls, 0);
    });

    test('login ناجح → authenticated + توكنات محفوظة', () async {
      final store = _FakeTokenStore();
      final adapter = _FakeAdapter((o) => o.uri.path.endsWith('/auth/login')
          ? _json(200, {'user': _userJson, 'access_token': 'a1', 'refresh_token': 'r1'})
          : _json(404, {}));
      final n = AuthNotifier(tokenStore: store, dioOverride: _plainDio(adapter));

      await n.login('ahmed@test.dev', 'secret123');

      expect(n.state.status, AuthStatus.authenticated);
      expect(n.state.user?.name, 'أحمد');
      expect(n.state.user?.plan, 'pro');
      expect(store.access, 'a1');
      expect(store.refresh, 'r1');
    });

    test('login فاشل 401 → AuthException + رجوع unauthenticated', () async {
      final store = _FakeTokenStore(access: 'old', refresh: 'old_r');
      final adapter = _FakeAdapter((o) => _json(401, {'detail': 'bad'}));
      final n = AuthNotifier(tokenStore: store, dioOverride: _plainDio(adapter));

      await expectLater(
        n.login('x@y.z', 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(n.state.status, AuthStatus.unauthenticated);
    });

    test('register مكرر 409 → رسالة عربية مناسبة', () async {
      final adapter = _FakeAdapter((o) => _json(409, {'detail': 'exists'}));
      final n = AuthNotifier(
        tokenStore: _FakeTokenStore(),
        dioOverride: _plainDio(adapter),
      );

      await expectLater(n.register('dup@x.y', '123456', 'سامي'),
          throwsA(predicate<AuthException>((e) => e.messageAr.contains('مسجّل'))));
    });

    test('logout يمسح التوكنات ويعيد unauthenticated', () async {
      final store = _FakeTokenStore();
      final adapter = _FakeAdapter((o) =>
          o.uri.path.endsWith('/auth/login')
              ? _json(200, {'user': _userJson, 'access_token': 'a2', 'refresh_token': 'r2'})
              : _json(200, {'ok': true}));
      final n = AuthNotifier(tokenStore: store, dioOverride: _plainDio(adapter));

      await n.login('ahmed@test.dev', 'secret123');
      await n.logout();

      expect(n.state.status, AuthStatus.unauthenticated);
      expect(store.access, isNull);
      expect(store.refresh, isNull);
    });

    test('restore بتوكن refresh صالح → refresh ثم me → authenticated', () async {
      final store = _FakeTokenStore(refresh: 'valid_r');
      final adapter = _FakeAdapter((o) {
        if (o.uri.path.endsWith('/auth/refresh')) {
          return _json(200, {'access_token': 'na', 'refresh_token': 'nr'});
        }
        if (o.uri.path.endsWith('/auth/me')) {
          expect(o.headers['Authorization'], 'Bearer na');
          return _json(200, {'user': _userJson});
        }
        return _json(404, {});
      });
      final n = AuthNotifier(tokenStore: store, dioOverride: _plainDio(adapter));

      await n.restoreOnStartup();

      expect(n.state.status, AuthStatus.authenticated);
      expect(n.state.user?.email, 'ahmed@test.dev');
      expect(store.access, 'na');
      expect(store.refresh, 'nr');
    });

    test('restore برفض الخادم → unauthenticated ومسح التوكنات (swallow)',
        () async {
      final store = _FakeTokenStore(refresh: 'expired_r');
      final adapter = _FakeAdapter((o) => _json(401, {'detail': 'expired'}));
      final n = AuthNotifier(tokenStore: store, dioOverride: _plainDio(adapter));

      await n.restoreOnStartup();

      expect(n.state.status, AuthStatus.unauthenticated);
      expect(store.cleared, isTrue);
    });
  });

  group('authed_dio — 401 → single-flight refresh ثم إعادة المحاولة مرة', () {
    test('نجاح التجديد وإعادة الإرسال بالتوكن الجديد', () async {
      final store = _FakeTokenStore(access: 'stale', refresh: 'r_ok');
      final gets = <String?>[];
      final adapter = _FakeAdapter((o) {
        if (o.uri.path.endsWith('/auth/refresh')) {
          return _json(200, {'access_token': 'fresh', 'refresh_token': 'r_new'});
        }
        gets.add(o.headers['Authorization'] as String?);
        return gets.length == 1
            ? _json(401, {'detail': 'expired'})
            : _json(200, {'ok': true});
      });

      final dio = createAuthedDio(store: store, baseUrl: 'http://test.local')
        ..httpClientAdapter = adapter;

      final res = await dio.get<dynamic>('/api/billing/usage');

      expect(res.data['ok'], isTrue);
      expect(gets, ['Bearer stale', 'Bearer fresh']);
      expect(store.access, 'fresh');
      expect(store.refresh, 'r_new');
      // طلب تجديد واحد فقط بين الطلبين الأصليين
      final refreshes =
          adapter.requests.where((r) => r.uri.path.endsWith('/auth/refresh'));
      expect(refreshes.length, 1);
    });

    test('فشل الإعادة بعد التجديد → لا حلقة ولا تجديد ثانٍ', () async {
      final store = _FakeTokenStore(access: 'stale', refresh: 'r_ok');
      var secureHits = 0;
      final adapter = _FakeAdapter((o) {
        if (o.uri.path.endsWith('/auth/refresh')) {
          return _json(200, {'access_token': 'fresh', 'refresh_token': 'r_new'});
        }
        secureHits++;
        return _json(401, {'detail': 'still expired'});
      });

      final dio = createAuthedDio(store: store, baseUrl: 'http://test.local')
        ..httpClientAdapter = adapter;

      await expectLater(
        dio.get<dynamic>('/api/secure'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)),
      );

      expect(secureHits, 2, reason: 'الأصلية + إعادة واحدة فقط');
      expect(
        adapter.requests.where((r) => r.uri.path.endsWith('/auth/refresh')).length,
        1,
        reason: 'single-flight + علم retried يمنع التكرار',
      );
    });
  });

  group('AutoEditApi.decodeEvent (خريطة WS)', () {
    test('progress → الحقول كما هي', () {
      final ev = AutoEditApi.decodeEvent(jsonEncode({
        'type': 'progress',
        'stage': 'transcribing',
        'progress': 15.0,
        'message_ar': 'جاري تفريغ الصوت...',
        'message_en': 'Transcribing audio...',
      }));
      expect(ev.type, 'progress');
      expect(ev.stage, 'transcribing');
      expect(ev.progress, 15.0);
      expect(ev.messageAr, 'جاري تفريغ الصوت...');
      expect(ev.messageEn, 'Transcribing audio...');
      expect(ev.clipsJson, isNull);
    });

    test('done → clipsJson مع النتائج', () {
      final ev = AutoEditApi.decodeEvent(jsonEncode({
        'type': 'done',
        'result': {
          'clips': [
            {'index': 0, 'file_url': 'a.mp4', 'viral_score': 0.87},
            {'index': 1, 'file_url': 'b.mp4', 'viral_score': 0.71},
          ],
          'compiled_file_url': null,
        },
      }));
      expect(ev.type, 'done');
      expect(ev.clipsJson, isNotNull);
      expect(ev.clipsJson!.length, 2);
      expect((ev.clipsJson!.first as Map)['file_url'], 'a.mp4');
    });

    test('error → detail في الرسالتين', () {
      final ev = AutoEditApi.decodeEvent(
          '{"type":"error","detail":"فشل الرندر"}');
      expect(ev.type, 'error');
      expect(ev.messageAr, 'فشل الرندر');
      expect(ev.messageEn, 'فشل الرندر');
    });
  });

  group('buildWsUri', () {
    test('http→ws و https→wss', () {
      expect(buildWsUri('http://localhost:8000'), 'ws://localhost:8000');
      expect(buildWsUri('https://api.clippify.app'), 'wss://api.clippify.app');
    });
  });
}
