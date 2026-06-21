import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'launch/backend_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // تهيئة مشغل الفيديو media_kit
  MediaKit.ensureInitialized();

  // تهيئة window_manager لسطح المكتب
  await windowManager.ensureInitialized();

  try {
    await dotenv.load(fileName: "assets/.env");
  } catch (e) {
    debugPrint("Failed to load assets/.env, falling back to assets/.env.example: $e");
    await dotenv.load(fileName: "assets/.env.example");
  }

  // تشغيل خادم الباك إند (بايثون) قبل تحميل واجهة المستخدم
  final backendController = BackendController();
  await backendController.startBackend();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    minimumSize: Size(960, 540),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Clippify - Editor',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    // منع الإغلاق التلقائي لكي يتسنى لنا قتل عملية البايثون
    await windowManager.setPreventClose(true);
  });

  runApp(
    const ProviderScope(
      child: ClippifyApp(),
    ),
  );
}
