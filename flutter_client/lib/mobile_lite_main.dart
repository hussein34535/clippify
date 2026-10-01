import 'package:flutter/material.dart';

import 'mobile_lite/app.dart';

/// نقطة دخول نسخة الموبايل المستقلة (مساعد المونتاج).
///
/// التشغيل على جهاز: `flutter run -t lib/mobile_lite_main.dart`
/// بناء أندرويد: `flutter build apk --release -t lib/mobile_lite_main.dart`
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MobileLiteScope());
}
