import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Injectable process runner so tests can fake [Process.run].
typedef EngineRunner = Future<ProcessResult> Function(
    String executable, List<String> arguments);

/// Bridge to the bundled Rust CLI (`clippify_engine.exe`).
///
/// Every subcommand prints a single JSON document to stdout; failures print
/// `Error: ...` to stderr with a non-zero exit code.
class RustEngine {
  RustEngine._();

  /// Swap in a fake runner for tests (null → real [Process.run]).
  @visibleForTesting
  static EngineRunner? runner;

  static String? _exe;
  static bool _resolved = false;

  /// Absolute path of the resolved engine binary, null when unresolved.
  static String? get exePath => _exe;

  @visibleForTesting
  static void reset() {
    _exe = null;
    _resolved = false;
    runner = null;
  }

  /// Force the resolved path (tests seed this instead of touching disk).
  @visibleForTesting
  static void debugSetExe(String? path) {
    _exe = path;
    _resolved = true;
  }

  /// Resolution order:
  ///   1. Next to the running exe (bundled distribution)
  ///   2. `engine/target/release/clippify_engine.exe` relative to cwd / repo
  ///      root (dev checkout)
  ///   3. null
  static Future<String?> resolveEngine() async {
    if (_resolved) return _exe;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    _exe = await resolveFromCandidates([
      '$exeDir/clippify_engine.exe',
      'engine/target/release/clippify_engine.exe',
      '../engine/target/release/clippify_engine.exe',
    ]);
    _resolved = true;
    return _exe;
  }

  /// First candidate that exists on disk wins; null when none do.
  @visibleForTesting
  static Future<String?> resolveFromCandidates(
      List<String> candidates) async {
    for (final c in candidates) {
      try {
        if (await File(c).exists()) return c;
      } catch (_) {}
    }
    return null;
  }

  /// Directory containing the engine binary (null when unresolved).
  static Future<String?> engineDir() async {
    final exe = await resolveEngine();
    if (exe == null) return null;
    return File(exe).parent.path;
  }

  // ── Commands ────────────────────────────────────────────────────────────

  /// `duration <path>` → {"duration": seconds, "status": "ok"}
  static Future<Map<String, dynamic>?> duration(String path) async {
    return _runMap(['duration', path]);
  }

  /// `silences <path>` → {"silences":[{start,end}], "speech":[...]}
  static Future<List<Map<String, dynamic>>> silences(
    String path, {
    double? noiseDb,
    double? minDur,
  }) async {
    return _runKeyedList(<String>[
      'silences',
      path,
      if (noiseDb != null) ...['--noise-db', noiseDb.toString()],
      if (minDur != null) ...['--min-dur', minDur.toString()],
    ], 'silences');
  }

  /// `thumbnails <path> --count N --out DIR` → {"thumbs":[...]}
  static Future<List<Map<String, dynamic>>> thumbnails(
    String path,
    int count,
    String outDir,
  ) async {
    return _runKeyedList(
        ['thumbnails', path, '--count', '$count', '--out', outDir], 'thumbs');
  }

  /// `ask <prompt>` → provider answer payload (null when all fail).
  static Future<Map<String, dynamic>?> ask(
    String prompt, {
    double? temperature,
    bool jsonMode = false,
  }) async {
    return _runMap(<String>[
      'ask',
      prompt,
      if (temperature != null) ...['--temperature', temperature.toString()],
      if (jsonMode) '--json-mode',
    ]);
  }

  /// `status` → LLM providers list.
  static Future<List<Map<String, dynamic>>> status() async {
    return _runKeyedList(['status'], 'providers');
  }

  // ── Internals ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _runMap(List<String> args) async {
    final json = await _runJson(args);
    if (json is Map) return Map<String, dynamic>.from(json);
    return null;
  }

  static Future<List<Map<String, dynamic>>> _runKeyedList(
      List<String> args, String key) async {
    final json = await _runMap(args);
    final raw = json?[key];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  /// Spawn the engine and decode stdout JSON. Null on any failure
  /// (unresolved binary, non-zero exit, malformed output).
  static Future<Object?> _runJson(List<String> args) async {
    try {
      final exe = await resolveEngine();
      if (exe == null) return null;
      final run = runner;
      final result = run != null
          ? await run(exe, args)
          : await Process.run(exe, args,
              stdoutEncoding: utf8, stderrEncoding: utf8);
      if (result.exitCode != 0) return null;
      final out = result.stdout is String
          ? (result.stdout as String).trim()
          : utf8.decode(result.stdout as List<int>, allowMalformed: true).trim();
      if (out.isEmpty) return null;
      return jsonDecode(out);
    } catch (_) {
      return null;
    }
  }
}
