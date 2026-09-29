import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'auth_store.dart';
import 'backend_service.dart' show service;

const String _kRetriedExtra = 'clippify_retried_after_refresh';

/// Interceptor يضيف Bearer من [TokenStore]، وعند 401 يجدِّد التوكن
/// (single-flight) ويعيد الطلب مرة واحدة فقط.
class AuthInterceptor extends Interceptor {
  final TokenStore store;

  /// Dio يُستخدم لإعادة إرسال الطلب الأصلي بعد التجديد.
  final Dio? retryDio;

  /// تنفيذ التجديد — افتراضياً POST {base}/api/auth/refresh عبر dio عارٍ.
  Future<void> Function(String refreshToken)? onRefresh;

  Future<void>? _refreshing;

  AuthInterceptor(this.store, {this.retryDio, this.onRefresh});

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    try {
      final token = await store.readAccess();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint('[AuthInterceptor] read token failed: $e');
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final opts = err.requestOptions;
    final alreadyRetried = opts.extra[_kRetriedExtra] == true;
    final isRefreshCall = opts.uri.path.endsWith('/auth/refresh');
    if (err.response?.statusCode != 401 || alreadyRetried || isRefreshCall) {
      handler.next(err);
      return;
    }
    try {
      await refreshTokens();
      final newToken = await store.readAccess();
      if (newToken == null || newToken.isEmpty) {
        handler.next(err);
        return;
      }
      final client = retryDio ?? Dio();
      final response = await client.fetch<dynamic>(
        opts
          ..extra[_kRetriedExtra] = true
          ..headers['Authorization'] = 'Bearer $newToken',
      );
      handler.resolve(response);
    } catch (_) {
      handler.next(err);
    }
  }

  /// single-flight: طلبات 401 متوازية تنتظر تجديداً واحداً.
  Future<void> refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final executor = onRefresh;
    if (executor != null) {
      final refresh = await store.readRefresh();
      if (refresh == null || refresh.isEmpty) {
        throw StateError('لا يوجد refresh_token');
      }
      return executor(refresh);
    }
    // أعد استخدام نفس الـ client إن توفّر (اختبارات/محولات مخصصة)،
    // وإلا أنشئ Dio عارياً على نفس القاعدة.
    final bare = retryDio ??
        Dio(BaseOptions(baseUrl: service.baseUrl));
    final refresh = await store.readRefresh();
    if (refresh == null || refresh.isEmpty) {
      throw StateError('لا يوجد refresh_token');
    }
    final res = await bare.post<Map<String, dynamic>>(
      '/api/auth/refresh',
      data: {'refresh_token': refresh},
    );
    final data = res.data!;
    await store.saveTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
  }
}

/// مصنع Dio مُصادق جاهز للاستخدام في كل نقاط /api/* السحابية.
Dio createAuthedDio({TokenStore? store, String? baseUrl}) {
  final tokenStore = store ?? SecureTokenStore();
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl ?? service.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(minutes: 5),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor(tokenStore, retryDio: dio));
  return dio;
}
