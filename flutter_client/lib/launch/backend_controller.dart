import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class BackendController {
  static final BackendController _instance = BackendController._internal();
  factory BackendController() => _instance;
  BackendController._internal();

  Process? _backendProcess;
  bool _isStarted = false;

  bool get isStarted => _isStarted;

  /// فحص ما إذا كان البورت 8000 مشغولاً بالفعل
  Future<bool> isPortInUse(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
      await socket.close();
      return true; // البورت مشغول
    } catch (_) {
      return false; // البورت متاح
    }
  }

  /// البحث عن مسار خادم بايثون أو الملف التنفيذي للباك إند
  Future<Directory> _findBackendCwd() async {
    // نبدأ من مسار العمل الحالي
    Directory dir = Directory.current;
    
    // سنصعد إلى الأعلى حتى نجد ملف api.py
    for (int i = 0; i < 4; i++) {
      final apiPy = File(p.join(dir.path, 'api.py'));
      if (await apiPy.exists()) {
        return dir;
      }
      dir = dir.parent;
    }
    
    // إذا لم نجد في التطوير، نفترض مجلد التطبيق التنفيذي
    final exeDir = File(Platform.resolvedExecutable).parent;
    return exeDir;
  }

  /// التحقق من أن الخادم على البورت هو الباك إند الصحيح (وليس خادم HTTP عشوائي)
  Future<bool> _verifyIsOurBackend() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('http://localhost:8000/docs'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      // FastAPI يرسل صفحة Swagger UI تحتوي على "swagger" أو "FastAPI"
      return body.contains('swagger') || body.contains('FastAPI');
    } catch (_) {
      return false;
    }
  }

  /// تشغيل عملية الباك إند
  Future<void> startBackend() async {
    if (await isPortInUse(8000)) {
      final isOurs = await _verifyIsOurBackend();
      if (isOurs) {
        debugPrint('[BackendController] البورت 8000 مشغول بالباك إند الصحيح. تم التخطي.');
        _isStarted = true;
        return;
      }
      debugPrint('[BackendController] تحذير: البورت 8000 مشغول بعملية أخرى غير الباك إند!');
      debugPrint('[BackendController] محاولة قتل العملية المخالفة وإعادة تشغيل الباك إند...');
      try {
        final result = await Process.run('netstat', ['-ano', '|', 'findstr', ':8000'], runInShell: true);
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('LISTENING')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            final pid = parts.last;
            if (pid.isNotEmpty && int.tryParse(pid) != null) {
              Process.killPid(int.parse(pid));
              debugPrint('[BackendController] تم قتل العملية PID $pid');
            }
          }
        }
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        debugPrint('[BackendController] فشل قتل العملية: $e');
        _isStarted = false;
        return;
      }
    }

    final backendDir = await _findBackendCwd();
    debugPrint('[BackendController] مجلد العمل للباك إند: ${backendDir.path}');

    String program;
    List<String> arguments = [];

    // تحديد البرنامج والوسائط بناءً على بيئة التشغيل وجودة التطوير
    if (kDebugMode) {
      // في وضع التطوير، نستخدم بايثون النظام لتشغيل api.py
      final apiPy = File(p.join(backendDir.path, 'api.py'));
      if (await apiPy.exists()) {
        program = Platform.isWindows ? 'python' : 'python3';
        arguments = ['api.py'];
      } else {
        debugPrint('[BackendController] تحذير: لم يتم العثور على api.py في وضع التطوير!');
        return;
      }
    } else {
      // في وضع الإنتاج، نبحث عن الملف التنفيذي المدمج بجانب التطبيق
      final exeDir = File(Platform.resolvedExecutable).parent;
      final sidecarExe = File(p.join(exeDir.path, Platform.isWindows ? 'clipai-backend.exe' : 'clipai-backend'));
      
      if (await sidecarExe.exists()) {
        program = sidecarExe.path;
      } else {
        // محاولة البحث في مجلد المخرجات (build/windows/runner/Release)
        final buildSidecar = File(p.join(backendDir.path, 'dist', Platform.isWindows ? 'clipai-backend.exe' : 'clipai-backend'));
        if (await buildSidecar.exists()) {
          program = buildSidecar.path;
        } else {
          debugPrint('[BackendController] خطأ: لم يتم العثور على ملف الباك إند التنفيذي sidecar!');
          return;
        }
      }
    }

    try {
      debugPrint('[BackendController] تشغيل: $program ${arguments.join(' ')}');
      _backendProcess = await Process.start(
        program,
        arguments,
        workingDirectory: backendDir.path,
        runInShell: true,
      );

      _isStarted = true;
      debugPrint('[BackendController] تم تشغيل خادم الباك إند بنجاح (PID: ${_backendProcess?.pid})');

      // الاستماع لمخرجات العملية للتحقق والـ debug
      _backendProcess!.stdout.listen((data) {
        final message = String.fromCharCodes(data);
        debugPrint('[Backend StdOut] $message');
      });

      _backendProcess!.stderr.listen((data) {
        final message = String.fromCharCodes(data);
        debugPrint('[Backend StdErr] $message');
      });

      // إعطاء الخادم ثانية واحدة للتهيئة
      await Future.delayed(const Duration(seconds: 1));
    } catch (e) {
      debugPrint('[BackendController] فشل تشغيل الباك إند: $e');
      _isStarted = false;
    }
  }

  /// إيقاف الباك إند بأمان
  Future<void> stopBackend() async {
    if (_backendProcess != null) {
      debugPrint('[BackendController] إيقاف خادم الباك إند (PID: ${_backendProcess?.pid})...');
      _backendProcess!.kill();
      final exitCode = await _backendProcess!.exitCode;
      debugPrint('[BackendController] تم إيقاف خادم الباك إند بكود الخروج: $exitCode');
      _backendProcess = null;
      _isStarted = false;
    }
  }
}
