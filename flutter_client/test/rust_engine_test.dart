import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/core/native/rust_engine.dart';

ProcessResult _fail([String msg = 'Error: boom']) =>
    ProcessResult(0, 1, '', msg);
void main() {
  setUp(RustEngine.reset);
  tearDown(RustEngine.reset);

  /// Seed a fake exe so command tests never touch real filesystem
  /// resolution; [payload] receives the args the engine would get.
  void seed(String Function(List<String> args) payload) {
    RustEngine.debugSetExe(r'C:\fake\clippify_engine.exe');
    RustEngine.runner =
        (_, args) async => ProcessResult(0, 0, payload(args), '');
  }

  group('RustEngine JSON parsing (mock runner)', () {
    test('duration parses {"duration": s}', () async {
      List<String>? seen;
      seed((args) {
        seen = args;
        return jsonEncode({'duration': 12.5, 'status': 'ok'});
      });      final r = await RustEngine.duration('x.mp4');
      expect(seen, ['duration', 'x.mp4']);
      expect(r?['duration'], 12.5);
      expect(r?['status'], 'ok');
    });

    test('silences parses list payload + optional flags', () async {
      List<String>? seen;
      seed((args) {
        seen = args;
        return jsonEncode({
          'silences': [
            {'start': 1.0, 'end': 2.5},
            {'start': 4.0, 'end': 5.0},
          ],
          'speech': [],
          'status': 'ok',
        });
      });
      final s = await RustEngine.silences('x.mp4',
          noiseDb: -35.0, minDur: 0.4);
      expect(seen, [
        'silences', 'x.mp4', '--noise-db', '-35.0', '--min-dur', '0.4',
      ]);
      expect(s.length, 2);
      expect(s[0]['end'], 2.5);
    });

    test('thumbnails builds --count/--out and parses thumbs', () async {
      List<String>? seen;
      seed((args) {
        seen = args;
        return jsonEncode({
          'thumbs': [
            {'index': 0, 'path': r'C:\t\0.jpg', 'timestamp_sec': 0.5},
          ],
          'status': 'ok',
        });
      });
      final t = await RustEngine.thumbnails('x.mp4', 3, r'C:\t');
      expect(seen, ['thumbnails', 'x.mp4', '--count', '3', '--out', r'C:\t']);
      expect(t.single['path'], contains('0.jpg'));
    });

    test('ask forwards prompt + temperature + json-mode', () async {
      List<String>? seen;
      seed((args) {
        seen = args;
        return jsonEncode({'text': 'hi', 'status': 'ok'});
      });
      final r = await RustEngine.ask('hello',
          temperature: 0.3, jsonMode: true);
      expect(
          seen, ['ask', 'hello', '--temperature', '0.3', '--json-mode']);
      expect(r?['text'], 'hi');
    });

    test('status extracts providers list', () async {
      seed((_) => jsonEncode({
            'providers': [
              {'provider': 'ollama', 'mode': 'off'},
              {'provider': 'groq', 'mode': 'off'},
            ],
            'status': 'ok',
          }));
      final p = await RustEngine.status();
      expect(p.length, 2);
      expect(p[1]['provider'], 'groq');
    });
  });

  group('RustEngine failure handling', () {
    test('non-zero exit → null map / empty list', () async {
      RustEngine.debugSetExe('engine.exe');
      RustEngine.runner = (_, __) async => _fail();
      expect(await RustEngine.duration('x.mp4'), isNull);
      expect(await RustEngine.silences('x.mp4'), isEmpty);
      expect(await RustEngine.status(), isEmpty);
    });

    test('malformed stdout → null / empty', () async {
      RustEngine.debugSetExe('engine.exe');
      RustEngine.runner =
          (_, __) async => ProcessResult(0, 0, 'not json {{', '');
      expect(await RustEngine.ask('q'), isNull);
      expect(await RustEngine.thumbnails('x.mp4', 2, 'd'), isEmpty);
    });

    test('runner throw → null / empty (never rethrows)', () async {
      RustEngine.debugSetExe('engine.exe');
      RustEngine.runner = (_, __) async => throw StateError('spawn failed');
      expect(await RustEngine.duration('x.mp4'), isNull);
      expect(await RustEngine.silences('x.mp4'), isEmpty);
    });

    test('unresolved engine → null without spawning', () async {
      RustEngine.runner =
          (_, __) => Future.error(StateError('must not spawn'));
      // debugSetExe(null) marks resolved-but-missing.
      RustEngine.debugSetExe(null);
      expect(await RustEngine.duration('x.mp4'), isNull);
    });
  });

  group('resolveFromCandidates fallback chain', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rust_engine_test');
    });
    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('first existing candidate wins', () async {
      final a = File('${tmp.path}/a.exe')..writeAsStringSync('');
      final b = File('${tmp.path}/b.exe')..writeAsStringSync('');
      final got = await RustEngine.resolveFromCandidates([
        '${tmp.path}/missing.exe',
        a.path,
        b.path,
      ]);
      expect(got, a.path);
    });

    test('falls through missing entries to later candidate', () async {
      final b = File('${tmp.path}/b.exe')..writeAsStringSync('');
      final got = await RustEngine.resolveFromCandidates([
        '${tmp.path}/nope1.exe',
        '${tmp.path}/nope2.exe',
        b.path,
      ]);
      expect(got, b.path);
    });

    test('all missing → null', () async {
      expect(
        await RustEngine.resolveFromCandidates([
          '${tmp.path}/ghost1.exe',
          '${tmp.path}/ghost2.exe',
        ]),
        isNull,
      );
    });
  });
}
