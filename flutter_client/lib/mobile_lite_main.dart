import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/backend/backend_service.dart';
import 'mobile_lite/app.dart';

/// نقطة دخول نسخة الموبايل المستقلة (مساعد المونتاج).
///
/// التشغيل على جهاز: `flutter run -t lib/mobile_lite_main.dart`
/// بناء أندرويد: `flutter build apk --release -t lib/mobile_lite_main.dart`
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // إعدادات الاتصال (LOCAL_MODE/API_BASE_URL) — بدونها يرمي dotenv
  // NotInitializedError عند أول currentBaseUrl (شاشة خطأ دائمة).
  try {
    await dotenv.load(fileName: 'assets/.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: 'assets/.env.example');
    } catch (_) {}
  }
  BackendService.bootSavedMode = await BackendModePref.load();
  runApp(const MobileLiteScope());
}
