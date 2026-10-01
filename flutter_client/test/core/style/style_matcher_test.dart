import 'package:flutter_client/core/style/reference_dna.dart';
import 'package:flutter_client/core/style/style_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

ReferenceDna richDna() => const ReferenceDna(
      channel: 'ch',
      videoId: 'v',
      sourceDuration: 600,
      rhythm: RhythmDna(avgShot: 2.4, cutsPerMin: 25),
      transitions: TransitionDna(cut: 0.9, dissolve: 0.1, fade: 0, wipe: 0),
      sfx: SfxDna(eventsPerMin: 6, onCutRatio: 0.7, types: ['whoosh']),
      music: MusicDna(hasBed: true, tempoBpm: 96, mood: 'groovy'),
      color: ColorDna(mood: 'warm'),
      captions: CaptionDna(density: 0.9),
      bookends: BookendsDna(hasIntro: true, introSec: 3, hasOutro: true, outroSec: 8),
      hook: HookDna(style: 'cold_open', firstShotSec: 1.2),
    );

bool applied(List<MatchDecision> ds, String element) =>
    ds.firstWhere((d) => d.element == element).apply;

String reason(List<MatchDecision> ds, String element) =>
    ds.firstWhere((d) => d.element == element).reason;

void main() {
  group('matchDnaToProject', () {
    test('talking-head طويل: كل شيء تقريبًا يُطبق', () {
      final ds = matchDnaToProject(
        richDna(),
        const ProjectProfile(
            durationSec: 300, hasSpeech: true, speechFraction: 0.8),
      );
      for (final e in [
        'rhythm',
        'captions',
        'punch_ins',
        'music_bed',
        'intro',
        'outro',
        'sfx',
        'color',
        'hook',
      ]) {
        expect(applied(ds, e), isTrue, reason: e);
      }
      expect(applied(ds, 'broll'), isFalse); // إيقاع سريع 2.4s
      expect(reason(ds, 'broll'), isNotEmpty);
    });

    test('قصير بلا كلام: الأغلبية تُتخطى بأسباب', () {
      final ds = matchDnaToProject(
        richDna(),
        const ProjectProfile(durationSec: 20),
      );
      expect(applied(ds, 'captions'), isFalse);
      expect(applied(ds, 'music_bed'), isFalse);
      expect(applied(ds, 'intro'), isFalse);
      expect(applied(ds, 'outro'), isFalse);
      expect(applied(ds, 'broll'), isFalse);
      expect(applied(ds, 'rhythm'), isTrue);
      expect(applied(ds, 'color'), isTrue);
      // كل قرار مرفوض يحمل سببًا معلنًا.
      for (final d in ds) {
        expect(d.reason, isNotEmpty);
      }
    });

    test('طويل بطيء: B-roll يدخل', () {
      const dna = ReferenceDna(
        rhythm: RhythmDna(avgShot: 5.0, cutsPerMin: 10),
      );
      final ds = matchDnaToProject(
        dna,
        const ProjectProfile(durationSec: 200, hasSpeech: true),
      );
      expect(applied(ds, 'broll'), isTrue);
    });

    test('مرجع هادئ: SFX تُتخطى', () {
      const dna = ReferenceDna(
        sfx: SfxDna(eventsPerMin: 0.5),
      );
      final ds = matchDnaToProject(
        dna,
        const ProjectProfile(durationSec: 200, hasSpeech: true),
      );
      expect(applied(ds, 'sfx'), isFalse);
    });

    test('مرجع بلا طبقة/مقدمة: التخطي بأسباب صحيحة', () {
      const dna = ReferenceDna();
      final ds = matchDnaToProject(
        dna,
        const ProjectProfile(durationSec: 300, hasSpeech: true),
      );
      expect(reason(ds, 'music_bed'), contains('بلا طبقة'));
      expect(reason(ds, 'intro'), contains('بلا مقدمة'));
      expect(reason(ds, 'hook'), contains('جملة عادية'));
    });

    test('حركة كاميرا عالية: لا punch-ins', () {
      final ds = matchDnaToProject(
        richDna(),
        const ProjectProfile(
            durationSec: 300, hasSpeech: true, hasCameraMotion: true),
      );
      expect(applied(ds, 'punch_ins'), isFalse);
      expect(reason(ds, 'punch_ins'), contains('الكاميرا'));
    });
  });
}
