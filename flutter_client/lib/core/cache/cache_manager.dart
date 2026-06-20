import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CacheManager {
  static final CacheManager _instance = CacheManager._();
  factory CacheManager() => _instance;
  CacheManager._();

  Future<Directory> get _cacheDir async {
    final appDir = await getTemporaryDirectory();
    final cache = Directory(p.join(appDir.path, 'clippify_cache'));
    if (!await cache.exists()) {
      await cache.create(recursive: true);
    }
    return cache;
  }

  Future<bool> has(String key) async {
    final dir = await _cacheDir;
    final f = File(p.join(dir.path, key));
    return f.exists();
  }

  Future<String> pathFor(String key) async {
    final dir = await _cacheDir;
    return p.join(dir.path, key);
  }

  Future<void> write(String key, List<int> bytes) async {
    final path = await pathFor(key);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<List<int>?> read(String key) async {
    if (!await has(key)) return null;
    final path = await pathFor(key);
    return await File(path).readAsBytes();
  }

  Future<String?> readString(String key) async {
    final bytes = await read(key);
    return bytes == null ? null : String.fromCharCodes(bytes);
  }

  Future<void> writeString(String key, String value) async {
    await write(key, value.codeUnits);
  }

  Future<void> remove(String key) async {
    if (!await has(key)) return;
    final path = await pathFor(key);
    try {
      await File(path).delete();
    } catch (_) {
    }
  }

  Future<void> clear() async {
    final dir = await _cacheDir;
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<int> get sizeInBytes async {
    final dir = await _cacheDir;
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<int> get entryCount async {
    final dir = await _cacheDir;
    if (!await dir.exists()) return 0;
    int count = 0;
    await for (final entity in dir.list()) {
      if (entity is File) count++;
    }
    return count;
  }
}
