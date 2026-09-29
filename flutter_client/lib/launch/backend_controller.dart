import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

  String get _apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000';

  /// التحقق من أن الخادم على البورت هو الباك إند الصحيح (وليس خادم HTTP عشوائي)
  Future<bool> _verifyIsOurBackend() async {
    // 1) محرّك Rust: /api/health → {"engine":"rust"}
    if (await _probe('$_apiBaseUrl/api/health', (b) => b.contains('"engine"'))) {
      return true;
    }
    // 2) خادم Python القديم: /docs → Swagger UI
    return _probe('$_apiBaseUrl/docs',
        (b) => b.contains('swagger') || b.contains('FastAPI'));
  }

  Future<bool> _probe(String url, bool Function(String body) ok) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();
      return ok(body);
    } catch (_) {
      return false;
    }
  }

  /// قتل أي عملية غير الباك إند على port 8000
  Future<bool> _killRogueProcessOnPort8000() async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('cmd', ['/c', 'netstat -ano | findstr :8000']);
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.contains('LISTENING')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 5) {
              final pid = parts.last;
              if (pid.isNotEmpty && int.tryParse(pid) != null) {
                Process.killPid(int.parse(pid));
                debugPrint('[BackendController] تم قتل العملية PID $pid');
              }
            }
          }
        }
      } else {
        final result = await Process.run('lsof', ['-ti:8000']);
        final stdout = result.stdout.toString().trim();
        if (stdout.isNotEmpty) {
          final pids = stdout.split('\n');
          for (final pid in pids) {
            final trimmed = pid.trim();
            if (trimmed.isNotEmpty && int.tryParse(trimmed) != null) {
              Process.killPid(int.parse(trimmed));
              debugPrint('[BackendController] تم قتل العملية PID $trimmed');
            }
          }
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    } catch (e) {
      debugPrint('[BackendController] فشل قتل العملية: $e');
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
      final killed = await _killRogueProcessOnPort8000();
      if (!killed) {
        _isStarted = false;
        return;
      }
    }

    var backendDir = await _findBackendCwd();
    debugPrint('[BackendController] مجلد العمل للباك إند: ${backendDir.path}');

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    String program;
    List<String> arguments = ['serve', '--port', '8000'];

    // ترتيب البحث عن الباك إند: محرّك Rust المدمج أولاً، ثم بايثون
    final engineName = Platform.isWindows ? 'clippify_engine.exe' : 'clippify_engine';
    final sidecarName =
        Platform.isWindows ? 'clippify-backend.exe' : 'clippify-backend';
    final engineCandidates = [
      p.join(exeDir, engineName), // بجانب التطبيق (توزيع مدمج)
      p.join(exeDir, sidecarName), // الاسم القديم للموزعة
      p.join(backendDir.path, 'engine', 'target', 'release', engineName),
      p.join(Directory.current.path, 'engine', 'target', 'release', engineName),
    ];

    String? found;
    for (final c in engineCandidates) {
      if (await File(c).exists()) {
        found = c;
        break;
      }
    }

    if (found != null) {
      // شغّل المحرّك من مجلد التطبيق حتى يجد ffmpeg.exe المجاور له
      program = found;
      backendDir = File(found).parent;
    } else {
      // لا يوجد محرّك؟ ارجع لبايثون (وضع التطوير)
      final apiPy = File(p.join(backendDir.path, 'api.py'));
      if (await apiPy.exists()) {
        program = Platform.isWindows ? 'python' : 'python3';
        arguments = ['api.py'];
      } else {
        debugPrint('[BackendController] خطأ: لم يتم العثور على المحرّك أو api.py');
        return;
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
