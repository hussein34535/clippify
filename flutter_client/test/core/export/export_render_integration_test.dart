import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_client/core/export/timeline_export_args.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// تحقق مستقل بالتنفيذ الحقيقي: نبني أمر ffmpeg من الـ builder ونشغّله
/// على الـ ffmpeg المجمّع فعليًا بمدخلات صناعية — أي خطأ في صياغة
/// الـ filter_complex يسقط هنا لا عند المستخدم.
///
/// يُتخطى تلقائيًا إن لم يوجد المجمّع (CI بلا engine).
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

Future<void> _run(String name, String exe, List<String> args) async {
  final r = await Process.run(exe, args,
      stdoutEncoding: utf8, stderrEncoding: utf8);
  if (r.exitCode != 0) {
    fail('$name failed (${r.exitCode}):\n${r.stderr}');
  }
}

void main() {
  test('real ffmpeg renders clip+gap+speed graph (7s expected)',
      () async {
    final ffmpeg = _bundledFfmpeg();
    if (ffmpeg == null) {
      markTestSkipped('bundled ffmpeg not found — engine not built');
      return;
    }

    final dir = Directory.systemTemp.createTempSync('clippify_render_test');
    try {
      final src = '${dir.path}${Platform.pathSeparator}src.mp4';
      final out = '${dir.path}${Platform.pathSeparator}out.mp4';

      // مصدر صناعي 6 ثوانٍ (صورة + صوت).
      await _run('synthesize', ffmpeg, [
        '-y',
        '-f', 'lavfi', '-i', 'testsrc2=s=640x360:r=30:d=6',
        '-f', 'lavfi', '-i', 'sine=frequency=440:d=6',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-shortest', src,
      ]);

      // مقطع 4s بسرعة 1 + فجوة 2s + مقطع 2s بسرعة 2 (= 1s مخرج).
      final segments = [
        ExportSegment(
            sourcePath: src,
            trimStart: 0,
            trimDuration: 4,
            speed: 1,
            volume: 1,
            hasAudio: true),
        const ExportSegment(
            sourcePath: null,
            trimStart: 0,
            trimDuration: 2,
            speed: 1,
            volume: 1,
            hasAudio: true),
        ExportSegment(
            sourcePath: src,
            trimStart: 0,
            trimDuration: 2,
            speed: 2,
            volume: 0.5,
            hasAudio: true),
      ];
      const total = 7.0;

      final args = buildExportArgs(
        segments: segments,
        width: 640,
        height: 360,
        fps: 30,
        encoder: 'libx264',
        pixelFormat: 'yuv420p',
        bitrateMbps: 2,
        maxBitrateMbps: 4,
        encoderPreset: 'ultrafast',
        ffmpegFormat: 'mp4',
        outputPath: out,
        pass: 0,
      );

      final proc = await Process.start(ffmpeg, args);
      final stderr = StringBuffer();
      proc.stderr.transform(utf8.decoder).listen(stderr.write);
      unawaited(proc.stdout.drain<void>());
      final code = await proc.exitCode;
      final log = stderr.toString();
      expect(code, 0, reason: 'ffmpeg log:\n$log');
      expect(File(out).existsSync(), isTrue);

      // المدة الفعلية ≈ 7 ثوانٍ (يُستكشَف المخرج لا سطر الإدخال).
      final probe = await Process.run(
          ffmpeg, ['-hide_banner', '-i', out],
          stdoutEncoding: utf8, stderrEncoding: utf8);
      final m = RegExp(r'Duration: (\d+):(\d+):([\d.]+)')
          .firstMatch(probe.stderr as String);
      expect(m, isNotNull, reason: 'no Duration in:\n${probe.stderr}');
      final secs = int.parse(m!.group(1)!) * 3600 +
          int.parse(m.group(2)!) * 60 +
          double.parse(m.group(3)!);
      expect(secs, inInclusiveRange(6.5, 7.5));

      // خطوط التقدم time= تُفسَّر بتزايد حتى النهاية.
      final ratios = RegExp(r'time=(\d+):(\d+):(\d+)\.(\d+)')
          .allMatches(log)
          .map((mm) =>
              int.parse(mm.group(1)!) * 3600 +
              int.parse(mm.group(2)!) * 60 +
              int.parse(mm.group(3)!) +
              int.parse(mm.group(4)!) / 100.0)
          .map((t) => t / total)
          .toList();
      expect(ratios, isNotEmpty);
      expect(ratios.last, greaterThanOrEqualTo(0.9));
      for (var i = 1; i < ratios.length; i++) {
        expect(ratios[i], greaterThanOrEqualTo(ratios[i - 1] - 0.05));
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
