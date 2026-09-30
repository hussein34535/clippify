import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BackendMode { local, cloud }

/// تخزين وضع التشغيل (محلي/سحابي) في SharedPreferences.
///
/// القيم: `'local'` | `'cloud'` — مفتاح: [BackendModePref.key].
/// المالك هنا (core) عن قصد: الإعدادات تُقرأ عند الإقلاع قبل أي ودجت.
class BackendModePref {
  static const String key = 'clippify_backend_mode';

  /// يقرأ الوضع المحفوظ؛ يعيد null إن كان غائباً أو قيمة غير معروفة.
  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(key);
      return (v == 'local' || v == 'cloud') ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, mode);
  }
}

/// عقود docs/CONTRACTS.md — قسم Base.
abstract class BackendService {
  bool get isCloud;
  String get baseUrl;

  /// اختيار نقي قابل للاختبار.
  ///
  /// الأسبقية: `localMode` (إعداد النشر `LOCAL_MODE`) ثم `savedMode`
  /// (اختيار المستخدم المحفوظ عند الإقلاع) ثم الافتراضي `'local'`.
  /// محلي فقط عند isWindows && الوضع الفعّال != 'cloud'.
  static BackendMode chooseBackend({
    required bool isWindows,
    required String? localMode,
    String? savedMode,
  }) {
    final effective = localMode ?? savedMode ?? 'local';
    return (effective != 'cloud' && isWindows)
        ? BackendMode.local
        : BackendMode.cloud;
  }

  /// اختيار المستخدم المحمَّل في main() قبل أول استخدام لـ [service].
  static String? bootSavedMode;
}

class LocalBackendService implements BackendService {
  @override
  final String baseUrl;

  LocalBackendService({String? baseUrl})
      : baseUrl =
            baseUrl ?? dotenv.maybeGet('API_BASE_URL') ?? 'http://localhost:8000';

  @override
  bool get isCloud => false;
}

class CloudBackendService implements BackendService {
  @override
  final String baseUrl;

  CloudBackendService({String? baseUrl})
      : baseUrl = baseUrl ??
            dotenv.maybeGet('CLOUD_API_URL') ??
            'https://api.clippify.app';

  @override
  bool get isCloud => true;
}

/// نقطة الالتقاء الوحيدة لبقية التطبيق.
// ignore: avoid_redundant_argument_values
BackendService get service => switch (BackendService.chooseBackend(
      // على الويب لا يوجد dart:io — التطبيق دسكتوب/موبايل فقط، kIsWeb حارس شكلي
      isWindows: kIsWeb ? false : Platform.isWindows,
      localMode: dotenv.maybeGet('LOCAL_MODE'),
      savedMode: BackendService.bootSavedMode,
    )) {
      BackendMode.local => LocalBackendService(),
      BackendMode.cloud => CloudBackendService(),
    };

final backendServiceProvider = Provider<BackendService>((ref) => service);
