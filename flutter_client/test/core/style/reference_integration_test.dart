import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client/core/style/reference_analyzer.dart';
import 'package:flutter_client/core/style/reference_dna.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// تحقق مستقل: فيديو صناعي بمشهدين مختلفين يمرّ عبر analyzeReference
/// الكامل على ffmpeg المجمّع — أي كسر في السلسلة (أوامر/parsers) يسقط هنا.
String? _bundledFfmpeg() {
  final root = Directory.current.path;
  final candidates = [
    p.join(root, '..', 'engine', 'target', 'release', 'ffmpeg.exe'),
    if (!Platform.isWindows)
      p.join(root, '..', 'engine', 'target', 'release', 'ffmpeg'),
  ];
  for (final c in candidates) {
    if (File(c).existsSync()) return File(c).path;
  }
  return null;
}

Future<void> _run(String exe, List<String> args) async {
  final r = await Process.run(exe, args,
      stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) {
    fail('ffmpeg failed (${r.exitCode}):\n${r.stderr}');
  }
}

void main() {
  test('analyzeReference on synthetic 2-scene video', () async {
    final ffmpeg = _bundledFfmpeg();
    if (ffmpeg == null) {
      markTestSkipped('bundled ffmpeg not found — engine not built');
      return;
    }
    final dir = Directory.systemTemp.createTempSync('clippify_dna_test');
    try {
      final a = p.join(dir.path, 'a.mp4');
      final b = p.join(dir.path, 'b.mp4');
      final joined = p.join(dir.path, 'joined.mp4');
      await _run(ffmpeg, [
        '-y', '-f', 'lavfi', '-i', 'testsrc2=s=320x240:r=15:d=2',
        '-f', 'lavfi', '-i', 'sine=frequency=440:d=2',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
        '-shortest', a,
      ]);
      await _run(ffmpeg, [
        '-y', '-f', 'lavfi', '-i', 'rgbtestsrc=s=320x240:r=15:d=2',
        '-f', 'lavfi', '-i', 'sine=frequency=880:d=2',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac',
        '-shortest', b,
      ]);
      final list = p.join(dir.path, 'list.txt');
      await File(list).writeAsString("file '$a'\nfile '$b'\n");
      await _run(ffmpeg, [
        '-y', '-f', 'concat', '-safe', '0', '-i', list,
        '-c', 'copy', joined,
      ]);

      final progresses = <double>[];
      final dna = await const ReferenceAnalyzer().analyzeReference(
        joined,
        channel: 'test',
        videoId: 'synth',
        onProgress: (v, _) => progresses.add(v),
      );

      expect(dna.sourceDuration, inInclusiveRange(3.5, 4.5));
      expect(dna.rhythm.cutsPerMin, greaterThan(0));
      expect(dna.rhythm.avgShot, greaterThan(0));
      // القطع الصلب هو الغالب في concat مباشر.
      expect(dna.transitions.dominant, 'cut');
      // الموسيقى: جيب مستمر بلا نبض ولا صمت → لا طبقة، لا tempo.
      expect(dna.music.hasBed, isFalse);
      // الألوان: طور مشبع → ليس محايدًا فارغًا.
      expect(dna.color.saturation, greaterThan(0.1));
      // التقدم أحادي التزايد وينتهي عند ~1.
      expect(progresses, isNotEmpty);
      for (var i = 1; i < progresses.length; i++) {
        expect(progresses[i], greaterThanOrEqualTo(progresses[i - 1]));
      }
      // تسلسل JSON كامل ذهابًا وإيابًا.
      final back = ReferenceDna.decode(dna.encode());
      expect(back.rhythm.cutsPerMin, dna.rhythm.cutsPerMin);
      expect(back.color.mood, dna.color.mood);
      expect(back.transitions.dominant, dna.transitions.dominant);
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
