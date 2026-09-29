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
}
