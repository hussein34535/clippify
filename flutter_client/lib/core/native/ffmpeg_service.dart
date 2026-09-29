import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import 'rust_engine.dart';

/// Standalone-mode FFmpeg bridge.
///
/// Resolution order:
///   0. `ffmpeg.exe` shipped BESIDE the Rust engine binary (engine bundle)
///   1. `ffmpeg.exe` sitting NEXT TO the running exe (bundled distribution)
///   2. Backend-resolved path (/api/system/ffmpeg — imageio fallback)
///   3. Bare 'ffmpeg' from PATH
///
/// Everything here runs fully offline — no Python backend required.
class FfmpegService {
  FfmpegService._();

  static String? _exe;
  static bool _resolved = false;

  static Future<String> resolveExe() async {
    if (_resolved) return _exe ?? 'ffmpeg';
    _resolved = true;

    // 0) Bundled with the Rust engine distribution
    try {
      final engineDir = await RustEngine.engineDir();
      if (engineDir != null) {
        final candidate = File('$engineDir/ffmpeg.exe');
        if (await candidate.exists()) {
          _exe = candidate.path;
          return _exe!;
        }
      }
    } catch (_) {}

    // 1) Bundled next to exe (portable distribution)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final candidate = File('$exeDir/ffmpeg.exe');
      if (await candidate.exists()) {
        _exe = candidate.path;
        return _exe!;
      }
      final devCandidate = File('ffmpeg.exe');
      if (await devCandidate.exists()) {
        _exe = devCandidate.path;
        return _exe!;
      }
    } catch (_) {}

    // 2) Backend resolver (knows the imageio fallback path)
    try {
      final r = await ApiClient().dio.get('/api/system/ffmpeg',
          options: Options(receiveTimeout: const Duration(seconds: 4)));
      final path = r.data['path'] as String?;
      if (r.data['found'] == true && path != null && path.isNotEmpty &&
          await File(path).exists()) {
        _exe = path;
        return _exe!;
      }
    } catch (_) {}

    // 3) PATH
    _exe = 'ffmpeg';
    return _exe!;
  }

  /// Duration via the Rust engine (primary path). Null on any failure.
  static Future<double?> probeDurationViaRust(String mediaPath) async {
    try {
      final r = await RustEngine.duration(mediaPath);
      final d = r?['duration'];
      return d is num ? d.toDouble() : null;
    } catch (_) {
      return null;
    }
  }

  /// Probe media duration (seconds). Tries the Rust engine first, then
  /// parses ffmpeg's `Duration:` line as fallback.
  static Future<double?> probeDuration(String mediaPath) async {
    final rust = await probeDurationViaRust(mediaPath);
    if (rust != null) return rust;
    try {
      final exe = await resolveExe();
      final result = await Process.run(exe, [
        '-hide_banner', '-i', mediaPath, '-f', 'null', '-',
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      final blob = result.stderr;
      return parseDuration(blob);
    } catch (_) {
      return null;
    }
  }

  /// Speech segments = timeline MINUS silences. Same shape as the backend
  /// /api/detect-silence payload so callers can swap freely.
  static Future<List<Map<String, dynamic>>> detectSilences(
    String mediaPath, {
    double noiseDb = -30,
    double minSilenceDur = 0.5,
  }) async {
    try {
      final exe = await resolveExe();
      final result = await Process.run(exe, [
        '-hide_banner',
        '-i', mediaPath,
        '-af', 'silencedetect=noise=${noiseDb}dB:d=${minSilenceDur.toStringAsFixed(2)}',
        '-f', 'null', '-',
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      final blob = result.stderr;
      return parseSilences(blob);
    } catch (_) {
      return const [];
    }
  }

  /// Extract a single frame → JPEG path (temp). Null on failure.
  static Future<String?> extractFrame(
    String mediaPath,
    double timestampSec, {
    int width = 160,
  }) async {
    try {
      final exe = await resolveExe();
      final tmp = Directory.systemTemp.path;
      final out =
          '$tmp/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await Process.run(exe, [
        '-y',
        '-ss', timestampSec.toStringAsFixed(2),
        '-i', mediaPath,
        '-frames:v', '1',
        '-vf', 'scale=$width:-2',
        '-q:v', '3',
        out,
      ]);
      if (result.exitCode != 0 || !await File(out).exists()) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  // ── Pure parsers (unit-testable) ─────────────────────────────────────────

  /// ffmpeg prints:  Duration: 00:00:72.00  → seconds
  static double? parseDuration(String ffmpegOutput) {
    final m = RegExp(r'Duration:\s*(\d+):(\d+):(\d+\.?\d*)')
        .firstMatch(ffmpegOutput);
    if (m == null) return null;
    return double.parse(m.group(1)!) * 3600 +
        double.parse(m.group(2)!) * 60 +
        double.parse(m.group(3)!);
  }

  /// Parses silencedetect stderr into [{start,end},...] merged intervals.
  static List<Map<String, dynamic>> parseSilences(String ffmpegOutput) {
    final starts = RegExp(r'silence_start:\s*(-?[\d.]+)')
        .allMatches(ffmpegOutput)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    final ends = RegExp(r'silence_end:\s*([\d.]+)')
        .allMatches(ffmpegOutput)
        .map((m) => double.parse(m.group(1)!))
        .toList();

    final silences = <Map<String, dynamic>>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i] < 0 ? 0.0 : starts[i];
      final end = i < ends.length ? ends[i] : start;
      if (end > start) {
        silences.add({'start': start, 'end': end});
      }
    }
    return silences;
  }

  /// Invert silences → speech segments (the clips AutoCut creates).
  static List<Map<String, double>> speechSegments(
    List<Map<String, dynamic>> silences,
    double totalDuration,
  ) {
    final segments = <Map<String, double>>[];
    double cursor = 0.0;
    for (final s in silences) {
      final start = (s['start'] as num).toDouble();
      final end = (s['end'] as num).toDouble();
      if (start > cursor + 0.15) {
        segments.add({'start': cursor, 'end': start});
      }
      cursor = end > cursor ? end : cursor;
    }
    if (cursor < totalDuration - 0.15) {
      segments.add({'start': cursor, 'end': totalDuration});
    }
    return segments;
  }
}
