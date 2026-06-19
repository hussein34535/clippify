import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/core/models/timeline_models.dart';
import 'package:flutter_client/shared/utils/keyframe_interpolation.dart';

void main() {
  group('KeyframeAnimationEngine', () {
    test('empty keyframes returns 0.0', () {
      expect(KeyframeAnimationEngine.interpolate([], 'x', 5), 0.0);
    });

    test('single keyframe returns its value', () {
      final kfs = [Keyframe(time: 0, property: 'x', value: 42.0)];
      expect(KeyframeAnimationEngine.interpolate(kfs, 'x', 5), 42.0);
    });

    test('before first keyframe returns first value', () {
      final kfs = [
        Keyframe(time: 5, property: 'x', value: 10.0),
        Keyframe(time: 10, property: 'x', value: 20.0),
      ];
      expect(KeyframeAnimationEngine.interpolate(kfs, 'x', 0), 10.0);
    });

    test('after last keyframe returns last value', () {
      final kfs = [
        Keyframe(time: 0, property: 'x', value: 10.0),
        Keyframe(time: 5, property: 'x', value: 20.0),
      ];
      expect(KeyframeAnimationEngine.interpolate(kfs, 'x', 10), 20.0);
    });

    test('linear interpolation at midpoint', () {
      final kfs = [
        Keyframe(time: 0, property: 'x', value: 0.0),
        Keyframe(time: 10, property: 'x', value: 100.0),
      ];
      expect(KeyframeAnimationEngine.interpolate(kfs, 'x', 5), closeTo(50.0, 0.01));
    });

    test('filters by property', () {
      final kfs = [
        Keyframe(time: 0, property: 'x', value: 0.0),
        Keyframe(time: 10, property: 'x', value: 100.0),
        Keyframe(time: 0, property: 'y', value: 50.0),
        Keyframe(time: 10, property: 'y', value: 150.0),
      ];
      expect(KeyframeAnimationEngine.interpolate(kfs, 'x', 5), closeTo(50.0, 0.01));
      expect(KeyframeAnimationEngine.interpolate(kfs, 'y', 5), closeTo(100.0, 0.01));
    });

    test('ease-in produces smaller value at start', () {
      final linear = KeyframeAnimationEngine.interpolate(
        [Keyframe(time: 0, property: 'x', value: 0.0), Keyframe(time: 10, property: 'x', value: 100.0)],
        'x', 2);
      final easeIn = KeyframeAnimationEngine.interpolate(
        [Keyframe(time: 0, property: 'x', value: 0.0, easing: 'ease-in'), Keyframe(time: 10, property: 'x', value: 100.0)],
        'x', 2);
      expect(easeIn, lessThan(linear));
    });

    test('ease-out produces larger value at start', () {
      final linear = KeyframeAnimationEngine.interpolate(
        [Keyframe(time: 0, property: 'x', value: 0.0), Keyframe(time: 10, property: 'x', value: 100.0)],
        'x', 2);
      final easeOut = KeyframeAnimationEngine.interpolate(
        [Keyframe(time: 0, property: 'x', value: 0.0, easing: 'ease-out'), Keyframe(time: 10, property: 'x', value: 100.0)],
        'x', 2);
      expect(easeOut, greaterThan(linear));
    });

    test('interpolateVector2D works across two properties', () {
      final kfs = [
        Keyframe(time: 0, property: 'position_x', value: 0.0),
        Keyframe(time: 10, property: 'position_x', value: 100.0),
        Keyframe(time: 0, property: 'position_y', value: 50.0),
        Keyframe(time: 10, property: 'position_y', value: 150.0),
      ];
      final result = KeyframeAnimationEngine.interpolateVector2D(kfs, 'position', 5);
      expect(result.x, closeTo(50.0, 0.01));
      expect(result.y, closeTo(100.0, 0.01));
    });
  });
}
