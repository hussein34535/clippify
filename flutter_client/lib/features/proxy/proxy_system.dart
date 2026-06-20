import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ProxyGenerator {
  Future<String?> generateProxy(String sourcePath, {int width = 720}) async {
    final proxyDir = await _getProxyDir();
    final hash = _getFileHash(sourcePath);
    final proxyName = '${hash}_${width}w.mp4';
    final proxyPath = p.join(proxyDir.path, proxyName);

    final proxyFile = File(proxyPath);
    if (await proxyFile.exists()) return proxyPath;

    try {
      final result = await Process.run('ffmpeg', [
        '-i', sourcePath,
        '-vf', 'scale=$width:-2',
        '-c:v', 'libx264',
        '-crf', '23',
        '-an',
        proxyPath,
      ]);
      if (result.exitCode == 0 && await proxyFile.exists()) {
        debugPrint('[ProxyGenerator] Generated proxy: $proxyPath');
        return proxyPath;
      }
      debugPrint('[ProxyGenerator] FFmpeg failed: ${result.stderr}');
    } catch (e) {
      debugPrint('[ProxyGenerator] Error: $e');
    }
    return null;
  }

  Future<Directory> _getProxyDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final proxyDir = Directory(p.join(appDir.path, 'ClipAI', 'proxies'));
    if (!await proxyDir.exists()) {
      await proxyDir.create(recursive: true);
    }
    return proxyDir;
  }

  String _getFileHash(String sourcePath) {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      return sha256.convert(utf8.encode(sourcePath)).toString().substring(0, 12);
    }
    final stat = file.statSync();
    final raw = '${sourcePath}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 12);
  }
}

class ProxyManager {
  static final ProxyManager _instance = ProxyManager._();
  factory ProxyManager() => _instance;
  ProxyManager._();

  final Map<String, String> _proxyMap = {};
  bool _useProxy = false;

  Future<String?> getProxy(String sourcePath) async {
    if (_proxyMap.containsKey(sourcePath)) return _proxyMap[sourcePath];
    final proxy = await ProxyGenerator().generateProxy(sourcePath);
    if (proxy != null) {
      _proxyMap[sourcePath] = proxy;
    }
    return proxy;
  }

  Future<void> generateProxies(List<String> paths) async {
    for (final path in paths) {
      await getProxy(path);
    }
  }

  void clearProxies() {
    for (final proxy in _proxyMap.values) {
      try {
        File(proxy).deleteSync();
      } catch (_) {}
    }
    _proxyMap.clear();
  }

  bool isUsingProxy() => _useProxy;

  void setUseProxy(bool val) {
    _useProxy = val;
  }

  String? resolvePath(String sourcePath) {
    if (_useProxy && _proxyMap.containsKey(sourcePath)) {
      return _proxyMap[sourcePath];
    }
    return null;
  }
}
