import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/cache/cache_manager.dart';

class ThumbnailCache {
  static final ThumbnailCache _instance = ThumbnailCache._internal();
  factory ThumbnailCache() => _instance;
  ThumbnailCache._internal();

  final Map<String, String> _memoryCache = {};
  String? _cacheDir;

  String _makeKey(String videoPath, double timestampSec, int width, int height) {
    return '${videoPath.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}_${timestampSec.toStringAsFixed(1)}_${width}x$height';
  }

  Future<String> get _dir async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = p.join(appDir.path, 'ClipAI', 'thumbnails');
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) {
      await dirObj.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  Future<String?> get(String videoPath, double timestampSec, {int width = 160, int height = 90}) async {
    final key = _makeKey(videoPath, timestampSec, width, height);

    if (_memoryCache.containsKey(key)) {
      final path = _memoryCache[key]!;
      if (await File(path).exists()) return path;
      _memoryCache.remove(key);
    }

    final cacheDir = await _dir;
    final filePath = p.join(cacheDir, '$key.jpg');
    if (await File(filePath).exists() || CacheManager().has(key)) {
      _memoryCache[key] = filePath;
      return filePath;
    }

    return null;
  }

  Future<String> set(String videoPath, double timestampSec, String imagePath, {int width = 160, int height = 90}) async {
    final key = _makeKey(videoPath, timestampSec, width, height);
    final cacheDir = await _dir;
    final destPath = p.join(cacheDir, '$key.jpg');

    await File(imagePath).copy(destPath);
    _memoryCache[key] = destPath;
    return destPath;
  }

  Future<void> clear() async {
    _memoryCache.clear();
    final cacheDir = await _dir;
    if (await Directory(cacheDir).exists()) {
      await Directory(cacheDir).delete(recursive: true);
    }
  }

  Future<int> size() async {
    final cacheDir = await _dir;
    if (!await Directory(cacheDir).exists()) return 0;
    int total = 0;
    await for (final entity in Directory(cacheDir).list()) {
      if (entity is File) total++;
    }
    return total;
  }
}

class ThumbnailGenerator {
  static Future<String?> generate(String videoPath, double timestampSec, {int width = 160, int height = 90}) async {
    final cache = ThumbnailCache();

    final cached = await cache.get(videoPath, timestampSec, width: width, height: height);
    if (cached != null) return cached;

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = p.join(tempDir.path, 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final result = await Process.run(
        'ffmpeg',
        [
          '-ss', timestampSec.toStringAsFixed(1),
          '-i', videoPath,
          '-vframes', '1',
          '-q:v', '2',
          '-vf', 'scale=$width:$height',
          '-y',
          tempFile,
        ],
      );

      if (result.exitCode != 0 || !await File(tempFile).exists()) {
        return null;
      }

      final cachedPath = await cache.set(videoPath, timestampSec, tempFile, width: width, height: height);

      try {
        await File(tempFile).delete();
      } catch (_) {}

      return cachedPath;
    } catch (e) {
      debugPrint('[ThumbnailGenerator] Error: $e');
      return null;
    }
  }

  static Future<List<String>> generateBulk(
    String videoPath,
    double startTimestamp,
    double endTimestamp,
    int count, {
    int width = 160,
    int height = 90,
  }) async {
    final results = <String>[];
    final double step = (endTimestamp - startTimestamp) / math.max(1, count - 1);

    for (int i = 0; i < count; i++) {
      final timestamp = startTimestamp + i * step;
      final thumb = await generate(videoPath, timestamp, width: width, height: height);
      if (thumb != null) {
        results.add(thumb);
      }
    }

    return results;
  }
}
