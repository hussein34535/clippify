import 'package:flutter_client/mobile_lite/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liteAnswersToMap', () {
    test('defaults request one 45-second Short Auto clip', () {
      final map = liteAnswersToMap(const LiteAnswers());

      expect(map['mode'], 'short_auto');
      expect(map['n_clips'], 1);
      expect(map['clip_duration_sec'], 45.0);
      expect(map['platform'], 'tiktok');
      expect(map['content_type'], 'auto');
      expect(map['caption_theme'], isNull);
      expect(map['music'], isFalse);
      expect(map['broll'], isTrue);
      expect(map['translate_arabic'], isFalse);
      expect(map['custom_instructions'], contains('مقطع واحد'));
      expect(map['custom_instructions'], contains('45 ثانية'));
    });

    test('each duration requests a single clip', () {
      const durations = {
        LiteLength.short: 30.0,
        LiteLength.medium: 45.0,
        LiteLength.long: 60.0,
      };

      for (final entry in durations.entries) {
        final answers = const LiteAnswers().copyWith(length: entry.key);
        final map = liteAnswersToMap(answers);

        expect(map['mode'], 'short_auto');
        expect(map['n_clips'], 1);
        expect(map['clip_duration_sec'], entry.value);
      }
    });

    test('AI direction delegates the creative choices', () {
      final map = liteAnswersToMap(
        const LiteAnswers(director: LiteDirector.ai),
      );
      expect(map['short_director'], 'ai');
      expect(map.containsKey('creative_style'), isFalse);
      expect(map.containsKey('creative_music'), isFalse);
      expect(map.containsKey('creative_effects'), isFalse);
      final local = liteAnswersToMap(
        const LiteAnswers(director: LiteDirector.local),
      );
      expect(local['short_director'], 'local');
      expect(local['creative_style'], 'auto');
    });

    test('platforms use their backend names', () {
      const platforms = {
        LitePlatform.reels: 'reels',
        LitePlatform.tiktok: 'tiktok',
        LitePlatform.shorts: 'shorts',
      };

      for (final entry in platforms.entries) {
        final answers = const LiteAnswers().copyWith(platform: entry.key);
        expect(liteAnswersToMap(answers)['platform'], entry.value);
      }
    });

    test('caption themes use backend names', () {
      expect(
        liteAnswersToMap(
          const LiteAnswers(captions: LiteCaptions.yellow),
        )['caption_theme'],
        'TikTok Yellow',
      );
      expect(
        liteAnswersToMap(
          const LiteAnswers(captions: LiteCaptions.neon),
        )['caption_theme'],
        'Neon',
      );
    });

    test('music flag and brief follow answers', () {
      final map = liteAnswersToMap(
        const LiteAnswers(music: true, content: LiteContent.comedy),
      );

      expect(map['music'], isTrue);
      expect(map['custom_instructions'], contains('كوميدي'));
      expect(map['custom_instructions'], contains('موسيقى'));
    });
  });

  test('Arabic summary reflects the single clip, platform and duration', () {
    final summary = liteSummaryAr(
      const LiteAnswers(platform: LitePlatform.reels, length: LiteLength.short),
    );

    expect(summary, contains('مقطع واحد'));
    expect(summary, contains('ريلز'));
    expect(summary, contains('30 ثانية'));
  });
}
