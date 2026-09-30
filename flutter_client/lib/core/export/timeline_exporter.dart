import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/export/data/export_settings.dart';
import '../models/timeline_models.dart';
import '../native/ffmpeg_service.dart';
import '../services/services.dart';
import 'timeline_export_args.dart';

/// ريندر محلي للفيديو: يبني أمر ffmpeg من التايملاين ويشغّله مباشرة —
/// بديل عن `/api/render-plan` الـ501.
class TimelineExporter {
  const TimelineExporter();

  /// [onProgress] يُستدعى بقيمة 0..1 وحالة نصية قصيرة.
  Future<ExportResult> render({
    required TimelineState timeline,
    required ExportSettings settings,
    required String outputPath,
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      final videoTracks = timeline.tracks.video;
      final clips =
          videoTracks.isEmpty ? <VideoClip>[] : videoTracks.first.clips;
      if (clips.isEmpty) {
        return ExportResult(success: false, error: 'لا توجد مقاطع على التايملاين.');
      }

      var segments = buildExportSegments(clips);
      if (segments.isEmpty) {
        return ExportResult(success: false, error: 'لا توجد مقاطع صالحة للتصدير.');
      }

      onProgress?.call(0.01, 'Probing media...');
      segments = await _probeAudio(segments);

      final pro = settings.presetPro;
      final width = pro?.width ?? timeline.settings.width;
      final height = pro?.height ?? timeline.settings.height;
      final fps = pro?.fps ?? timeline.settings.fps;
      final ffmpegFormat = pro?.container.ffmpegFormat ?? 'mp4';
      final encoder = settings.codec ?? pro?.encoder.ffmpegCodec ?? 'libx264';
      final pixelFormat =
          settings.pixelFormat ?? pro?.encoder.pixelFormat ?? 'yuv420p';
      final encoderPreset = pro?.encoder.preset ?? 'medium';
      final qualityBitrate = _qualityBitrate(settings.exportQuality);
      final cap = pro?.maxBitrateMbps ?? 60;
      // الصريح من السلايدر يغلب خريطة الجودة.
      final bitrate = settings.bitrateMbps ??
          (qualityBitrate < cap ? qualityBitrate : cap);
      final maxBitrate =
          pro?.maxBitrateMbps != null && pro!.maxBitrateMbps > bitrate
              ? pro.maxBitrateMbps
              : bitrate + 4;

      final notes = <String>[];
      final wantTwoPass = settings.twoPass || pro?.twoPass == true;
      final twoPass = wantTwoPass && supportsTwoPass(encoder);
      if (wantTwoPass && !twoPass) {
        notes.add('المرور المزدوج يعمل مع الترميز البرمجي فقط — تم التصدير بمرور واحد.');
      }
      // أبعاد البريست ≠ أبعاد المشروع تعني letterbox لم يُعايَن.
      if (pro != null &&
          width * timeline.settings.height !=
              height * timeline.settings.width) {
        notes.add(
            'أبعاد البريست ($width×$height) تختلف عن المشروع — ستظهر أشرطة حول الصورة.');
      }
      var watermarkPath = settings.watermarkPath;
      if (watermarkPath != null && watermarkPath.isNotEmpty) {
        if (!await File(watermarkPath).exists()) {
          notes.add('ملف العلامة المائية مفقود — تم التصدير بدونها.');
          watermarkPath = null;
        }
      }

      final dir = p.dirname(outputPath);
      if (dir.isNotEmpty) await Directory(dir).create(recursive: true);

      final totalDur =
          segments.fold<double>(0, (sum, s) => sum + s.outputDuration);
      final nullSink = Platform.isWindows ? 'NUL' : '/dev/null';

      List<String> buildArgs(int pass) => buildExportArgs(
            segments: segments,
            width: width,
            height: height,
            fps: fps,
            encoder: encoder,
            pixelFormat: pixelFormat,
            bitrateMbps: bitrate,
            maxBitrateMbps: maxBitrate,
            encoderPreset: encoderPreset,
            ffmpegFormat: ffmpegFormat,
            outputPath: outputPath,
            pass: pass,
            includeMetadata: settings.includeMetadata,
            watermarkPath: watermarkPath,
            watermarkPosition: settings.watermarkPosition,
            nullSink: nullSink,
          );

      if (twoPass) {
        onProgress?.call(0.0, 'Pass 1/2 (analysis)...');
        final first = await _run(
          buildArgs(1),
          totalDur: totalDur,
          progressOffset: 0.0,
          progressScale: 0.5,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (first.cancelled) {
          return ExportResult(success: false, error: 'أُلغي التصدير.');
        }
        if (first.code != 0) {
          return ExportResult(
              success: false,
              outputPath: outputPath,
              error: 'Pass 1 failed:\n${first.errorTail}');
        }
        onProgress?.call(0.5, 'Pass 2/2 (encoding)...');
        final second = await _run(
          buildArgs(2),
          totalDur: totalDur,
          progressOffset: 0.5,
          progressScale: 0.5,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (second.cancelled) {
          return ExportResult(success: false, error: 'أُلغي التصدير.');
        }
        if (second.code != 0) {
          return ExportResult(
              success: false,
              outputPath: outputPath,
              error: 'Pass 2 failed:\n${second.errorTail}');
        }
      } else {
        final run = await _run(
          buildArgs(0),
          totalDur: totalDur,
          progressOffset: 0.0,
          progressScale: 1.0,
          onProgress: onProgress,
          isCancelled: isCancelled,
        );
        if (run.cancelled) {
          return ExportResult(success: false, error: 'أُلغي التصدير.');
        }
        if (run.code != 0) {
          return ExportResult(
              success: false,
              outputPath: outputPath,
              error: 'FFmpeg failed (code ${run.code}):\n${run.errorTail}');
        }
      }

      final out = File(outputPath);
      if (!await out.exists() || await out.length() == 0) {
        return ExportResult(
            success: false, outputPath: outputPath, error: 'لم يتم إنشاء الملف.');
      }
      onProgress?.call(1.0, 'Done');
      return ExportResult(success: true, outputPath: outputPath, notes: notes);
    } catch (e) {
      return ExportResult(success: false, error: e.toString());
    }
  }

  Future<List<ExportSegment>> _probeAudio(List<ExportSegment> segments) async {
    final cache = <String, bool>{};
    final out = <ExportSegment>[];
    for (final seg in segments) {
      if (seg.sourcePath == null) {
        out.add(seg);
        continue;
      }
      final known = cache[seg.sourcePath!];
      final has = known ?? await FfmpegService.probeHasAudio(seg.sourcePath!);
      cache[seg.sourcePath!] = has;
      out.add(has == seg.hasAudio
          ? seg
          : ExportSegment(
              sourcePath: seg.sourcePath,
              trimStart: seg.trimStart,
              trimDuration: seg.trimDuration,
              speed: seg.speed,
              volume: seg.volume,
              hasAudio: has,
            ));
    }
    return out;
  }

  Future<_RunResult> _run(
    List<String> args, {
    required double totalDur,
    required double progressOffset,
    required double progressScale,
    void Function(double progress, String status)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final exe = await FfmpegService.resolveExe();
    final proc = await Process.start(exe, args, runInShell: false);
    final errTail = <String>[];
    var cancelled = false;

    proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (errTail.length > 60) errTail.removeAt(0);
      errTail.add(line);
      final p = parseFfmpegProgress(line, totalSec: totalDur);
      if (p != null) {
        final overall = (progressOffset + p * progressScale).clamp(0.0, 1.0);
        onProgress?.call(overall, 'Encoding ${(overall * 100).toStringAsFixed(0)}%');
      }
    });
    unawaited(proc.stdout.drain<void>());

    Timer? watchdog;
    if (isCancelled != null) {
      watchdog = Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (isCancelled()) {
          cancelled = true;
          proc.kill(ProcessSignal.sigkill);
          t.cancel();
        }
      });
    }

    final code = await proc.exitCode;
    watchdog?.cancel();

    final errorTail = errTail
        .where((l) => l.trim().isNotEmpty && !l.contains('time='))
        .toList()
        .join('\n');
    return _RunResult(code: code, errorTail: errorTail, cancelled: cancelled);
  }

  int _qualityBitrate(String quality) {
    switch (quality.toLowerCase()) {
      case 'low':
        return 4;
      case 'medium':
        return 8;
      case 'ultra':
      case 'ultrahigh':
        return 24;
      case 'high':
      default:
        return 12;
    }
  }
}

class _RunResult {
  final int code;
  final String errorTail;
  final bool cancelled;
  const _RunResult(
      {required this.code, required this.errorTail, required this.cancelled});
}
