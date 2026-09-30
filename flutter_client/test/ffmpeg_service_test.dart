import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_client/core/native/ffmpeg_service.dart';

const _silenceFixture = '''
[Parsed_silencedetect_0 @ xxx] silence_start: 0.842
[Parsed_silencedetect_0 @ xxx] silence_end: 1.906 | silence_duration: 1.064
[Parsed_silencedetect_0 @ xxx] silence_start: 3.2
[Parsed_silencedetect_0 @ xxx] silence_end: 4.5 | silence_duration: 1.3
''';

const _durationFixture = '''
Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'x.mp4':
  Duration: 00:01:12.48, start: 0.000000, bitrate: 1234 kb/s
''';

void main() {
  group('FfmpegService.parseSilences', () {
    test('extracts merged intervals from silencedetect stderr', () {
      final s = FfmpegService.parseSilences(_silenceFixture);
      expect(s.length, 2);
      expect(s[0]['start'], 0.842);
      expect(s[0]['end'], 1.906);
      expect(s[1]['start'], 3.2);
      expect(s[1]['end'], 4.5);
    });

    test('negative silence_start clamps to zero', () {
      final s = FfmpegService.parseSilences('silence_start: -0.02\nsilence_end: 0.5');
      expect(s.first['start'], 0.0);
    });

    test('empty output → empty list', () {
      expect(FfmpegService.parseSilences(''), isEmpty);
    });
  });

  group('FfmpegService.parseDuration', () {
    test('parses Duration line', () {
      expect(FfmpegService.parseDuration(_durationFixture), closeTo(72.48, 0.001));
    });

    test('returns null when absent', () {
      expect(FfmpegService.parseDuration('nope'), isNull);
    });
  });

  group('FfmpegService.speechSegments', () {
    test('inverts silences into speech clips incl. tail', () {
      final silences = FfmpegService.parseSilences(_silenceFixture);
      final speech = FfmpegService.speechSegments(silences, 6.0);
      expect(speech, [
        {'start': 0.0, 'end': 0.842},
        {'start': 1.906, 'end': 3.2},
        {'start': 4.5, 'end': 6.0},
      ]);
    });

    test('all-silence audio → no segments', () {
      final speech = FfmpegService.speechSegments([
        {'start': 0.0, 'end': 5.0},
      ], 5.0);
      expect(speech, isEmpty);
    });
  });

  group('FfmpegService.silenceThresholdFor (adaptive)', () {
    test('short files get finer thresholds', () {
      expect(FfmpegService.silenceThresholdFor(1.0), 0.1);
      expect(FfmpegService.silenceThresholdFor(3.0), 0.2);
      expect(FfmpegService.silenceThresholdFor(10.0), 0.35);
      expect(FfmpegService.silenceThresholdFor(60.0), 0.5);
      expect(FfmpegService.silenceThresholdFor(0), 0.5);
    });
  });

  group('FfmpegService.speechConfidence', () {
    test('slivers score 0, solid speech scores 1', () {
      expect(FfmpegService.speechConfidence(0.1), 0.0);
      expect(FfmpegService.speechConfidence(0.15), 0.0);
      expect(FfmpegService.speechConfidence(1.0), 1.0);
      expect(FfmpegService.speechConfidence(5.0), 1.0);
      final mid = FfmpegService.speechConfidence(0.575);
      expect(mid, inInclusiveRange(0.0, 1.0));
      expect(mid, greaterThan(0.0));
    });
  });

  group('FfmpegService.mergeWeakSpeechSegments', () {
    test('strong segments pass through untouched', () {
      const segs = [
        {'start': 0.0, 'end': 3.0},
        {'start': 4.0, 'end': 8.0},
      ];
      expect(FfmpegService.mergeWeakSpeechSegments(segs), segs);
    });

    test('weak middle dissolves into previous (content kept)', () {
      final out = FfmpegService.mergeWeakSpeechSegments([
        {'start': 0.0, 'end': 3.0},
        {'start': 3.5, 'end': 3.7},
        {'start': 4.0, 'end': 8.0},
      ]);
      expect(out, [
        {'start': 0.0, 'end': 3.7},
        {'start': 4.0, 'end': 8.0},
      ]);
    });

    test('leading weak run joins the first strong', () {
      final out = FfmpegService.mergeWeakSpeechSegments([
        {'start': 0.0, 'end': 0.2},
        {'start': 0.3, 'end': 0.5},
        {'start': 1.0, 'end': 5.0},
      ]);
      expect(out, [
        {'start': 0.0, 'end': 5.0},
      ]);
    });

    test('trailing weak is preserved, never deleted', () {
      final out = FfmpegService.mergeWeakSpeechSegments([
        {'start': 0.0, 'end': 5.0},
        {'start': 5.5, 'end': 5.7},
      ]);
      expect(out, [
        {'start': 0.0, 'end': 5.7},
      ]);
    });

    test('lone weak survives (no deletion ever)', () {
      const segs = [
        {'start': 2.0, 'end': 2.2},
      ];
      expect(FfmpegService.mergeWeakSpeechSegments(segs), segs);
    });

    test('empty stays empty', () {
      expect(FfmpegService.mergeWeakSpeechSegments([]), isEmpty);
    });

    test('merge invariants hold on randomized timelines (property)', () {
      final rnd = math.Random(42);
      double covered(List<Map<String, double>> segs) => segs.fold<double>(
          0, (s, e) => s + (e['end']! - e['start']!));
      for (var trial = 0; trial < 200; trial++) {
        // مقاطع مرتبة غير متداخلة بأطوال وفجوات عشوائية.
        final segs = <Map<String, double>>[];
        var cursor = rnd.nextDouble() * 2;
        final n = 1 + rnd.nextInt(6);
        for (var i = 0; i < n; i++) {
          final len = rnd.nextDouble() * 3;
          segs.add({'start': cursor, 'end': cursor + len});
          cursor += len + rnd.nextDouble() * 2;
        }
        final out =
            FfmpegService.mergeWeakSpeechSegments(segs);
        expect(out, isNotEmpty);
        // الحدود محفوظة: لا تقليم من البداية ولا النهاية أبدًا.
        expect(out.first['start'], segs.first['start']);
        expect(out.last['end'], segs.last['end']);
        // التغطية لا تنقص أبدًا (دمج يوسّع فقط).
        expect(covered(out), greaterThanOrEqualTo(covered(segs) - 1e-9));
        // مرتبة وغير متداخلة.
        for (var i = 1; i < out.length; i++) {
          expect(out[i]['start']!, greaterThanOrEqualTo(out[i - 1]['end']!));
        }
      }
    });
  });
}
