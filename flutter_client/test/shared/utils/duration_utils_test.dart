import 'package:flutter_client/shared/utils/duration_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeProbeDurationSeconds', () {
    test('seconds pass through untouched', () {
      expect(normalizeProbeDurationSeconds(120.0), 120.0);
      expect(normalizeProbeDurationSeconds(0.5), 0.5);
    });

    test('milliseconds-looking values are converted', () {
      // 60 دقيقة بـ ms → 3600 ثانية
      expect(normalizeProbeDurationSeconds(3600000.0), 3600.0);
    });

    test('poisoned huge values are hard-capped at 6h', () {
      expect(normalizeProbeDurationSeconds(1e15), kMaxSingleClipSeconds);
    });

    test('zero and negatives hit the 0.1s floor', () {
      expect(normalizeProbeDurationSeconds(0), 0.1);
      expect(normalizeProbeDurationSeconds(-5), 0.1);
    });

    test('boundary 6h stays seconds, just above converts', () {
      expect(normalizeProbeDurationSeconds(kMaxSingleClipSeconds),
          kMaxSingleClipSeconds);
      expect(normalizeProbeDurationSeconds(kMaxSingleClipSeconds + 1),
          (kMaxSingleClipSeconds + 1) / 1000.0);
    });
  });
}
