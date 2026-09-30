import 'package:flutter_client/core/export/timeline_export_args.dart';
import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_test/flutter_test.dart';

VideoClip clip({
  required String id,
  required String path,
  required double start,
  required double end,
  double trimStart = 0,
  double? trimEnd,
  double speed = 1,
  double volume = 1,
}) =>
    VideoClip(
      id: id,
      sourcePath: path,
      startTimeInTimeline: start,
      endTimeInTimeline: end,
      sourceTrimStart: trimStart,
      sourceTrimEnd: trimEnd ?? (end - start),
      speed: speed,
      volume: volume,
      transform: TransformState.defaultState(),
      colorGrading: ColorGradingState(),
      filters: const [],
      aiFeatures: AIFeatures(),
    );

void main() {
  group('buildExportSegments', () {
    test('single clip → one segment, no gap', () {
      final segs = buildExportSegments([
        clip(id: 'c1', path: 'a.mp4', start: 0, end: 10, trimEnd: 10),
      ]);
      expect(segs, hasLength(1));
      expect(segs.first.sourcePath, 'a.mp4');
      expect(segs.first.outputDuration, 10);
      expect(segs.first.isGap, isFalse);
    });

    test('inserts gap segments for empty timeline ranges', () {
      final segs = buildExportSegments([
        clip(id: 'c1', path: 'a.mp4', start: 0, end: 5, trimEnd: 5),
        clip(id: 'c2', path: 'b.mp4', start: 8, end: 12, trimEnd: 4),
      ]);
      expect(segs, hasLength(3));
      expect(segs[0].sourcePath, 'a.mp4');
      expect(segs[1].isGap, isTrue);
      expect(segs[1].trimDuration, 3);
      expect(segs[2].sourcePath, 'b.mp4');
    });

    test('sorts clips by timeline start', () {
      final segs = buildExportSegments([
        clip(id: 'b', path: 'b.mp4', start: 6, end: 10, trimEnd: 4),
        clip(id: 'a', path: 'a.mp4', start: 0, end: 5, trimEnd: 5),
      ]);
      expect(segs.first.sourcePath, 'a.mp4');
      expect(segs.last.sourcePath, 'b.mp4');
    });

    test('overlapping clip is clamped at previous end', () {
      final segs = buildExportSegments([
        clip(id: 'a', path: 'a.mp4', start: 0, end: 6, trimEnd: 6),
        clip(id: 'b', path: 'b.mp4', start: 4, end: 10, trimStart: 100,
            trimEnd: 106),
      ]);
      expect(segs, hasLength(2));
      // بداية المقطع الثاني دُفعت لـ6 → التrim يبدأ من 100 + 2*1
      expect(segs[1].trimStart, 102);
      expect(segs[1].trimDuration, 4);
      expect(segs[1].outputDuration, 4);
    });

    test('speed scales output duration', () {
      final segs = buildExportSegments([
        clip(id: 'a', path: 'a.mp4', start: 0, end: 10, trimEnd: 10,
            speed: 2),
      ]);
      expect(segs.first.outputDuration, 5);
    });

    test('empty input → empty segments', () {
      expect(buildExportSegments([]), isEmpty);
    });

    test('degenerate clip (zero length) is skipped', () {
      final segs = buildExportSegments([
        clip(id: 'a', path: 'a.mp4', start: 5, end: 5, trimEnd: 0),
      ]);
      expect(segs, isEmpty);
    });
  });

  group('atempoChain', () {
    test('speed 1 → no filter', () {
      expect(atempoChain(1), isEmpty);
    });
    test('speed 2 → single atempo', () {
      expect(atempoChain(2), 'atempo=2');
    });
    test('speed 4 → chained atempo', () {
      expect(atempoChain(4), 'atempo=2,atempo=2');
    });
    test('speed 0.25 → two slow nodes', () {
      expect(atempoChain(0.25), 'atempo=0.5,atempo=0.5');
    });
    test('speed 1.5 → single decimal node', () {
      expect(atempoChain(1.5), 'atempo=1.5');
    });
    test('invalid speed → empty', () {
      expect(atempoChain(0), isEmpty);
    });
  });

  group('numStr', () {
    test('strips trailing zeros', () {
      expect(numStr(2.0), '2');
      expect(numStr(1.5), '1.5');
      expect(numStr(1.666666), '1.6667');
      expect(numStr(0.1), '0.1');
    });
  });

  group('encoder helpers', () {
    test('usesFfmpegPreset gating', () {
      expect(usesFfmpegPreset('libx264'), isTrue);
      expect(usesFfmpegPreset('h264_nvenc'), isTrue);
      expect(usesFfmpegPreset('prores_ks'), isFalse);
      expect(usesFfmpegPreset('libaom-av1'), isFalse);
      expect(usesFfmpegPreset('libvpx-vp9'), isFalse);
    });
    test('supportsTwoPass gating', () {
      expect(supportsTwoPass('libx264'), isTrue);
      expect(supportsTwoPass('h264_nvenc'), isFalse);
      expect(supportsTwoPass('prores_ks'), isFalse);
    });
    test('watermark position fallback → bottom-right', () {
      expect(watermarkPositionExpr(null), 'W-w-10:H-h-10');
      expect(watermarkPositionExpr('center'), '(W-w)/2:(H-h)/2');
      expect(watermarkPositionExpr('bogus'), 'W-w-10:H-h-10');
    });
  });

  group('buildExportArgs', () {
    List<String> build({
      List<ExportSegment>? segments,
      int pass = 0,
      String encoder = 'libx264',
      String format = 'mp4',
      bool watermark = false,
      bool metadata = true,
    }) =>
        buildExportArgs(
          segments: segments ??
              [
                const ExportSegment(
                    sourcePath: 'a.mp4',
                    trimStart: 0,
                    trimDuration: 10,
                    speed: 1,
                    volume: 1,
                    hasAudio: true),
              ],
          width: 1080,
          height: 1920,
          fps: 30,
          encoder: encoder,
          pixelFormat: 'yuv420p',
          bitrateMbps: 12,
          maxBitrateMbps: 50,
          encoderPreset: 'medium',
          ffmpegFormat: format,
          outputPath: 'out.mp4',
          pass: pass,
          includeMetadata: metadata,
          watermarkPath: watermark ? 'wm.png' : null,
          watermarkPosition: 'bottom-right',
          nullSink: 'NUL',
        );

    test('input seek is precise (-ss/-t before -i)', () {
      final args = build();
      final i = args.indexOf('-i');
      expect(i, greaterThan(0));
      expect(args[i - 1], '10');
      expect(args[i - 2], '-t');
      expect(args[i - 3], '0');
      expect(args[i - 4], '-ss');
      expect(args[i + 1], 'a.mp4');
    });

    test('gap segment gets lavfi color + anullsrc inputs', () {
      final args = build(segments: [
        const ExportSegment(
            sourcePath: null,
            trimStart: 0,
            trimDuration: 2,
            speed: 1,
            volume: 1,
            hasAudio: true),
      ]);
      expect(args.join(' '), contains('color=c=black:s=1080x1920:r=30'));
      expect(args.join(' '), contains('anullsrc=r=48000:cl=stereo'));
      expect(args.join(' '), contains('concat=n=1:v=1:a=1'));
    });

    test('filters unify size, fps and pixel format', () {
      final filter = build().join(' ');
      expect(filter, contains('scale=1080:1920:force_original_aspect_ratio=decrease'));
      expect(filter, contains('pad=1080:1920'));
      expect(filter, contains('fps=30'));
      expect(filter, contains('setsar=1'));
      expect(filter, contains('format=yuv420p'));
    });

    test('speed 2 → setpts division + atempo, output = material/speed', () {
      final filter = build(segments: [
            const ExportSegment(
                sourcePath: 'a.mp4',
                trimStart: 0,
                trimDuration: 10,
                speed: 2,
                volume: 1,
                hasAudio: true),
          ]).join(' ');
      expect(filter, contains('setpts=(PTS-STARTPTS)/2'));
      expect(filter, contains('atempo=2'));
      expect(filter, contains('trim=duration=5'));
    });

    test('single pass maps concat video+audio and ends with output', () {
      final args = build();
      final vMapIndex = args.indexOf('[vc]');
      expect(args[vMapIndex - 1], '-map');
      final aMapIndex = args.indexOf('[ac]');
      expect(args[aMapIndex - 1], '-map');
      expect(args.last, 'out.mp4');
      expect(args, contains('aac'));
      expect(args, contains('+faststart'));
    });

    test('pass 1 maps video only and writes to null sink', () {
      final args = build(pass: 1);
      expect(args[args.indexOf('-pass') + 1], '1');
      final vMapIndex = args.indexOf('[vc]');
      expect(args[vMapIndex - 1], '-map');
      expect(args.contains('[ac]'), isFalse);
      expect(args[args.length - 1], 'NUL');
      expect(args[args.length - 2], 'null');
    });

    test('watermark input appended last with overlay filter', () {
      final args = build(watermark: true);
      expect(args[args.indexOf('wm.png') - 1], '-i');
      expect(args.join(' '), contains('overlay=W-w-10:H-h-10'));
      expect(args.join(' '), contains('[vout]'));
    });

    test('unknown encoder does not get -preset', () {
      final args = build(encoder: 'libaom-av1');
      expect(args.contains('-preset'), isFalse);
      expect(args, contains('libaom-av1'));
    });

    test('metadata disabled adds -map_metadata -1', () {
      expect(build(metadata: false), contains('-map_metadata'));
      expect(build(metadata: false), contains('-1'));
    });

    test('non-mp4 container keeps its format flag without faststart', () {
      final args = build(format: 'mov');
      expect(args, contains('mov'));
      expect(args.contains('+faststart'), isFalse);
    });
  });

  group('parseFfmpegProgress', () {
    test('parses time= into a ratio', () {
      expect(parseFfmpegProgress('frame=100 time=00:00:10.00',
          totalSec: 20), 0.5);
    });
    test('clamps to 1.0', () {
      expect(parseFfmpegProgress('time=00:01:00.00', totalSec: 10), 1.0);
    });
    test('no time → null', () {
      expect(parseFfmpegProgress('nothing here', totalSec: 10), isNull);
    });
    test('total <= 0 → null', () {
      expect(parseFfmpegProgress('time=00:00:01.00', totalSec: 0), isNull);
    });
  });
}
