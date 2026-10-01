import 'package:flutter_client/mobile_lite/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('liteAnswersToMap (backend contract)', () {
    test('default answers → valid auto-edit body', () {
      final m = liteAnswersToMap(const LiteAnswers());
      expect(m['content_type'], 'auto');
      expect(m['platform'], 'tiktok');
      expect(m['n_clips'], 5);
      expect(m['clip_duration_sec'], 60.0);
      expect(m['caption_theme'], isNull);
      expect(m['music'], isFalse);
      expect(m['broll'], isTrue);
      expect(m['translate_arabic'], isFalse);
      expect(m['custom_instructions'], isNotEmpty);
    });

    test('length tiers map to clip counts', () {
      expect(
          liteAnswersToMap(const LiteAnswers(length: LiteLength.short))['n_clips'],
          3);
      expect(
          liteAnswersToMap(const LiteAnswers(length: LiteLength.long))['n_clips'],
          8);
    });

    test('caption themes use backend names', () {
      expect(
          liteAnswersToMap(const LiteAnswers(captions: LiteCaptions.yellow))['caption_theme'],
          'TikTok Yellow');
      expect(
          liteAnswersToMap(const LiteAnswers(captions: LiteCaptions.neon))['caption_theme'],
          'Neon');
    });

    test('music flag and brief follow answers', () {
      final m = liteAnswersToMap(
          const LiteAnswers(music: true, content: LiteContent.comedy));
      expect(m['music'], isTrue);
      expect(m['custom_instructions'], contains('كوميدي'));
      expect(m['custom_instructions'], contains('موسيقى'));
    });
  });

  group('liteSummaryAr', () {
    test('summarizes the plan in one line', () {
      final s = liteSummaryAr(const LiteAnswers());
      expect(s, contains('5 مقاطع'));
      expect(s, contains('تيك توك'));
    });
  });
}
