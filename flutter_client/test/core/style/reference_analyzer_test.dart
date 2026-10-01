import 'dart:typed_data';

import 'package:flutter_client/core/style/reference_analyzer.dart';
import 'package:flutter_client/core/style/reference_dna.dart';
import 'package:flutter_test/flutter_test.dart';

Int16List sineWithTransients() {
  const rate = 8000;
  const len = rate * 4;
  final pcm = Int16List(len);
  for (var i = 0; i < len; i++) {
    final t = i / rate;
    // جيب ضعيف مستمر + 3 طرقات حادة في 1.0 و2.0 و3.0
    var s = 0.1 * (i % 100 < 50 ? 1.0 : -1.0);
    for (final hit in [1.0, 2.0, 3.0]) {
      final dt = (t - hit).abs();
      if (dt < 0.02) s += 0.9 * (1 - dt / 0.02);
    }
    pcm[i] = (s.clamp(-1.0, 1.0) * 30000).round();
  }
  return pcm;
}

void main() {
  group('ReferenceDna model', () {
    test('roundtrip preserves everything', () {
      const dna = ReferenceDna(
        channel: 'قناة',
        videoId: 'abc',
        sourceDuration: 612.5,
        rhythm: RhythmDna(avgShot: 2.4, cutsPerMin: 25, accelerating: true),
        transitions: TransitionDna(cut: 0.8, dissolve: 0.2, fade: 0, wipe: 0),
        sfx: SfxDna(eventsPerMin: 6, onCutRatio: 0.7, types: ['whoosh']),
        music: MusicDna(hasBed: true, tempoBpm: 96, mood: 'groovy'),
        color: ColorDna(mood: 'warm', saturation: 1.15),
        captions: CaptionDna(density: 0.9),
        bookends: BookendsDna(hasIntro: true, introSec: 3),
        hook: HookDna(style: 'cold_open', firstShotSec: 1.2),
      );
      final back = ReferenceDna.decode(dna.encode());
      expect(back.channel, 'قناة');
      expect(back.rhythm.avgShot, 2.4);
      expect(back.transitions.dominant, 'cut');
      expect(back.sfx.types, ['whoosh']);
      expect(back.music.tempoBpm, 96);
      expect(back.color.mood, 'warm');
      expect(back.bookends.hasIntro, isTrue);
      expect(back.hook.style, 'cold_open');
    });

    test('decode tolerates garbage and partial docs', () {
      expect(() => ReferenceDna.decode('nope{{'), throwsA(anything));
      final back = ReferenceDna.decode('{"channel": 5}');
      expect(back.channel, '');
      expect(back.version, '1');
    });

    test('TransitionDna.dominant picks the max', () {
      expect(
          const TransitionDna(cut: 0.2, dissolve: 0.7, fade: 0.1, wipe: 0)
              .dominant,
          'dissolve');
    });
  });

  group('parseSceneCuts', () {
    test('extracts shot starts incl. zero', () {
      const log = '''
[Parsed_showinfo_1 @ x] n:   0 pts:       0 pts_time:0
[Parsed_showinfo_1 @ x] n:  48 pts:    4800 pts_time:1.6
[Parsed_showinfo_1 @ x] n: 120 pts:   12000 pts_time:4.0
''';
      expect(parseSceneCuts(log), [0.0, 1.6, 4.0]);
    });

    test('ignores non-showinfo lines, dedupes, sorts', () {
      const log = '''
frame= 10 fps=30 time=00:00:01.00
[Parsed_showinfo_1 @ x] n:  90 pts:    9000 pts_time:3.0
[Parsed_showinfo_1 @ x] n:  90 pts:    9000 pts_time:3.0
[Parsed_showinfo_1 @ x] n:  30 pts:    3000 pts_time:1.0
''';
      expect(parseSceneCuts(log), [0.0, 1.0, 3.0]);
    });

    test('empty → just zero', () {
      expect(parseSceneCuts('nothing here'), [0.0]);
    });
  });

  group('parseBrightnessCurve + classifyTransitions', () {
    String curve(List<double> ys, {double step = 0.1}) {
      final sb = StringBuffer();
      for (var i = 0; i < ys.length; i++) {
        sb.writeln(
            'frame:$i \tpts:${i * 3} \tpts_time:${(i * step).toStringAsFixed(1)}');
        sb.writeln('lavfi.signalstats.YAVG=${ys[i]}');
      }
      return sb.toString();
    }

    test('flat curve parses with timestamps', () {
      final c = parseBrightnessCurve(curve([100, 100, 100]));
      expect(c, hasLength(3));
      expect(c[1]['time'], moreOrLessEquals(0.1));
      expect(c[2]['y'], 100);
    });

    test('single shot → all cut', () {
      expect(
          classifyTransitions([0.0], [], 10.0)['cut'], 1.0);
    });

    test('dip to black at boundary → fade', () {
      // سطوع ثابت 120 ثم هبوط حاد للأسود عند 2.0 ثم عودة
      final ys = List<double>.filled(41, 120.0);
      for (var i = 18; i <= 22; i++) {
        ys[i] = 5.0;
      }
      final c = parseBrightnessCurve(curve(ys));
      final r = classifyTransitions([0.0, 2.0, 4.0], c, 5.0);
      expect(r['fade'], greaterThan(0.0));
    });

    test('hard cut with steady brightness → cut', () {
      final ys = List<double>.filled(61, 120.0);
      final c = parseBrightnessCurve(curve(ys));
      final r = classifyTransitions([0.0, 3.0, 6.0], c, 7.0);
      expect(r['cut'], 1.0);
    });

    test('gradual ramp → dissolve', () {
      final ys = <double>[];
      for (var i = 0; i < 61; i++) {
        ys.add(i < 20 ? 120.0 : (120.0 - (i - 20) * 5.0).clamp(0.0, 120.0));
      }
      final c = parseBrightnessCurve(curve(ys));
      final r = classifyTransitions([0.0, 2.5, 6.0], c, 7.0);
      expect(r['dissolve'], greaterThan(0.0));
    });
  });

  group('detectOnsets + estimateTempo', () {
    test('finds the three synthetic hits', () {
      final r = detectOnsets(sineWithTransients(), 8000);
      expect(r.times, hasLength(3));
      expect(r.times[0], inInclusiveRange(0.8, 1.2));
      expect(r.times[1], inInclusiveRange(1.8, 2.2));
      expect(r.times[2], inInclusiveRange(2.8, 3.2));
      expect(r.sharpness.every((s) => s > 1.0), isTrue);
    });

    test('silence → no onsets', () {
      final r = detectOnsets(Int16List(8000 * 2), 8000);
      expect(r.times, isEmpty);
    });

    test('too short → empty', () {
      expect(detectOnsets(Int16List(100), 8000).times, isEmpty);
    });

    test('tempo from 0.5s grid → ~120bpm', () {
      final onsets = [for (var i = 0; i < 10; i++) i * 0.5];
      expect(estimateTempo(onsets), inInclusiveRange(115.0, 125.0));
    });

    test('sparse onsets → 0', () {
      expect(estimateTempo([0.0, 5.0]), 0);
      expect(estimateTempo([]), 0);
    });
  });

  group('detectMusicBed', () {
    test('onsets inside silences → bed present', () {
      final onsets = [for (var i = 0; i < 20; i++) i * 0.5];
      final silences = [
        {'start': 0.0, 'end': 3.0},
        {'start': 6.0, 'end': 9.0},
      ];
      expect(
          detectMusicBed(
              onsets: onsets, silences: silences, totalDuration: 10.0),
          isTrue);
    });

    test('onsets only outside silences → no bed', () {
      final onsets = [3.5, 4.0, 4.5, 5.0, 5.5];
      final silences = [
        {'start': 0.0, 'end': 3.0},
        {'start': 6.0, 'end': 9.0},
      ];
      expect(
          detectMusicBed(
              onsets: onsets, silences: silences, totalDuration: 10.0),
          isFalse);
    });

    test('degenerate inputs → false', () {
      expect(
          detectMusicBed(onsets: [], silences: [], totalDuration: 10.0),
          isFalse);
      expect(
          detectMusicBed(
              onsets: [1.0],
              silences: [
                {'start': 0.0, 'end': 1.0}
              ],
              totalDuration: 0),
          isFalse);
    });
  });

  group('colorMood', () {
    test('warm / cool / muted / vivid', () {
      expect(colorMood(200, 120, 100, 0.5)['mood'], 'warm');
      expect(colorMood(100, 120, 200, 0.5)['mood'], 'cool');
      expect(colorMood(120, 120, 120, 0.1)['mood'], 'muted');
      expect(colorMood(150, 50, 140, 0.67)['mood'], 'vivid');
      expect(colorMood(130, 125, 120, 0.3)['mood'], 'neutral');
    });

    test('temperature moves with red-blue gap', () {
      final warm = colorMood(200, 120, 100, 0.5)['temperature'] as double;
      final cool = colorMood(100, 120, 200, 0.5)['temperature'] as double;
      expect(warm, lessThan(cool));
    });
  });

  group('detectBookends + hookStyle', () {
    test('short first + long last → intro/outro', () {
      final b = detectBookends([0.0, 2.0, 5.0, 8.0, 20.0], 30.0);
      expect(b['has_intro'], isTrue);
      expect(b['intro_sec'], 2.0);
      expect(b['has_outro'], isTrue);
      expect(b['outro_sec'], 10.0);
    });

    test('single static shot → none', () {
      final b = detectBookends([0.0], 30.0);
      expect(b['has_intro'], isFalse);
      expect(b['has_outro'], isFalse);
    });

    test('hook styles by first shot', () {
      expect(hookStyle([0.0, 1.0, 5.0], 10.0)['style'], 'cold_open');
      expect(hookStyle([0.0, 2.5, 6.0], 10.0)['style'], 'quick_hook');
      expect(hookStyle([0.0, 5.0, 9.0], 10.0)['style'], 'statement');
      expect(
          hookStyle([0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 12.0], 15.0)['style'],
          'fast_montage');
    });
  });
}
