import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_service.dart';

/// عقود docs/CONTRACTS.md — قسم Auth.

const String kAccessTokenKey = 'clippify_jwt';
const String kRefreshTokenKey = 'clippify_refresh';
const String kSkipAuthKey = 'skipAuthProvider';

/// واجهة تخزين التوكنات — تسمح بحقن نسخة في الذاكرة للاختبارات.
abstract class TokenStore {
  Future<void> saveTokens({required String access, required String refresh});
  Future<String?> readAccess();
  Future<String?> readRefresh();
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> saveTokens({required String access, required String refresh}) =>
      Future.wait([
        _storage.write(key: kAccessTokenKey, value: access),
        _storage.write(key: kRefreshTokenKey, value: refresh),
      ]).then((_) {});

  @override
  Future<String?> readAccess() => _storage.read(key: kAccessTokenKey);

  @override
  Future<String?> readRefresh() => _storage.read(key: kRefreshTokenKey);

  @override
  Future<void> clear() async {
    await _storage.delete(key: kAccessTokenKey);
    await _storage.delete(key: kRefreshTokenKey);
  }
}

class AuthUser {
  final String id;
  final String email;
  final String name;
  final String plan; // free | pro | studio
  final int creditsUsed;
  final int creditsLimit;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.plan,
    required this.creditsUsed,
    required this.creditsLimit,
  });

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: (j['id'] ?? '').toString(),
        email: (j['email'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        plan: (j['plan'] ?? 'free').toString(),
        creditsUsed: (j['credits_used'] as num?)?.toInt() ?? 0,
        creditsLimit: (j['credits_limit'] as num?)?.toInt() ?? 3,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'plan': plan,
        'credits_used': creditsUsed,
        'credits_limit': creditsLimit,
      };

  bool get isPro => plan != 'free';
}

enum AuthStatus { unauthenticated, authenticated, loading }

class AuthState {
  final AuthStatus status;
  final AuthUser? user;

  const AuthState({
    this.status = AuthStatus.unauthenticated,
    this.user,
  });

  AuthState copyWith({AuthStatus? status, AuthUser? user}) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
      );
}

class AuthException implements Exception {
  final String messageAr;
  AuthException(this.messageAr);
  @override
  String toString() => messageAr;
}

/// حالة المصادقة العامة — قابلة للحقن بالكامل عبر [TokenStore] و [Dio].
class AuthNotifier extends StateNotifier<AuthState> {
  final TokenStore tokenStore;
  final Dio? dioOverride;
  final String? baseUrlOverride;

  AuthNotifier({
    required this.tokenStore,
    this.dioOverride,
    this.baseUrlOverride,
  }) : super(const AuthState());

  Dio _dio() {
    if (dioOverride != null) return dioOverride!;
    return Dio(BaseOptions(
      baseUrl: baseUrlOverride ?? service.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  Options _bearer(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<void> login(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final res = await _dio().post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'email': email, 'password': password},
      );
      await _applySession(res.data!);
    } on DioException catch (e) {
      state = const AuthState();
      throw AuthException(_mapAuthError(e, wrongCreds: 'بيانات الدخول غير صحيحة'));
    } catch (_) {
      state = const AuthState();
      rethrow;
    }
  }

  Future<void> register(String email, String password, String name) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final res = await _dio().post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {'email': email, 'password': password, 'name': name},
      );
      await _applySession(res.data!);
    } on DioException catch (e) {
      state = const AuthState();
      throw AuthException(
          _mapAuthError(e, wrongCreds: 'تعذر إنشاء الحساب، تحقق من البيانات'));
    } catch (_) {
      state = const AuthState();
      rethrow;
    }
  }

  /// تدفق الاستعادة عند الإقلاع: refresh ثم me — أي فشل → unauthenticated.
  Future<void> restoreOnStartup() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final refresh = await tokenStore.readRefresh();
      if (refresh == null || refresh.isEmpty) {
        state = const AuthState();
        return;
      }
      final refreshed = await _dio().post<Map<String, dynamic>>(
        '/api/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = refreshed.data!;
      await tokenStore.saveTokens(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String,
      );
      final me = await _dio().get<Map<String, dynamic>>(
        '/api/auth/me',
        options: _bearer(data['access_token'] as String),
      );
      state = AuthState(
        status: AuthStatus.authenticated,
        user: AuthUser.fromJson((me.data!['user'] as Map).cast<String, dynamic>()),
      );
    } catch (e) {
      debugPrint('[Auth] restore failed: $e');
      try {
        await tokenStore.clear();
      } catch (_) {}
      state = const AuthState();
    }
  }

  Future<void> logout() async {
    try {
      final access = await tokenStore.readAccess();
      if (access != null) {
        await _dio().post('/api/auth/logout', options: _bearer(access));
      }
    } catch (_) {
      // best-effort
    }
    await tokenStore.clear();
    state = const AuthState();
  }

  Future<void> _applySession(Map<String, dynamic> data) async {
    await tokenStore.saveTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
    );
    final user =
        AuthUser.fromJson((data['user'] as Map).cast<String, dynamic>());
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  String _mapAuthError(DioException e, {required String wrongCreds}) {
    switch (e.response?.statusCode) {
      case 401:
        return wrongCreds;
      case 409:
        return 'هذا البريد الإلكتروني مسجّل مسبقاً';
      case 422:
        return 'تحقق من صحة البريد وكلمة المرور';
      default:
        return 'تعذر الاتصال بالخادم، حاول مجدداً';
    }
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final notifier = AuthNotifier(tokenStore: SecureTokenStore());
  notifier.restoreOnStartup();
  return notifier;
});

/// وضع الزائر — يُخزَّن محلياً في SharedPreferences.
final skipAuthProviderProvider = StateProvider<bool>((ref) => false);

class GuestFlag {
  static Future<void> set(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kSkipAuthKey, value);
  }

  static Future<bool> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kSkipAuthKey) ?? false;
  }
}
