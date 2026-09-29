import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum BackendMode { local, cloud }

/// عقود docs/CONTRACTS.md — قسم Base.
abstract class BackendService {
  bool get isCloud;
  String get baseUrl;

  /// اختيار نقي قابل للاختبار:
  /// محلي فقط عند isWindows && (localMode ?? 'local') != 'cloud'.
  static BackendMode chooseBackend({
    required bool isWindows,
    required String? localMode,
  }) {
    final forcedCloud = (localMode ?? 'local') == 'cloud';
    return (!forcedCloud && isWindows) ? BackendMode.local : BackendMode.cloud;
  }
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
    )) {
      BackendMode.local => LocalBackendService(),
      BackendMode.cloud => CloudBackendService(),
    };

final backendServiceProvider = Provider<BackendService>((ref) => service);
