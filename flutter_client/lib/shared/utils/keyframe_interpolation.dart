import 'dart:math' as math;
import '../../../core/models/timeline_models.dart';

/// Enhanced easing types for keyframe interpolation
enum EasingType {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  bounce,
  elastic,
  bezier,
}

/// KeyframeAnimationEngine: Interpolates values between keyframes
class KeyframeAnimationEngine {
  /// Get the interpolated value at a given time for a specific property
  static double interpolate(
      List<Keyframe> keyframes, String property, double time) {
    final sorted = _getSorted(keyframes, property);
    if (sorted.isEmpty) return 0.0;
    if (sorted.length == 1) return _toDouble(sorted.first.value);
    if (time <= sorted.first.time) return _toDouble(sorted.first.value);
    if (time >= sorted.last.time) return _toDouble(sorted.last.value);

    for (int i = 0; i < sorted.length - 1; i++) {
      if (time >= sorted[i].time && time <= sorted[i + 1].time) {
        final t = (time - sorted[i].time) /
            (sorted[i + 1].time - sorted[i].time);
        final eased = _applyEasing(t, sorted[i].easing);
        final a = _toDouble(sorted[i].value);
        final b = _toDouble(sorted[i + 1].value);
        return a + (b - a) * eased;
      }
    }
    return _toDouble(sorted.last.value);
  }

  /// Get the interpolated Vector2D at a given time
  static Vector2D interpolateVector2D(
      List<Keyframe> keyframes, String property, double time) {
    final xFrames = keyframes
        .where((k) => k.property == '${property}_x')
        .toList();
    final yFrames = keyframes
        .where((k) => k.property == '${property}_y')
        .toList();
    return Vector2D(
      x: interpolate(xFrames, '${property}_x', time),
      y: interpolate(yFrames, '${property}_y', time),
    );
  }

  static List<Keyframe> _getSorted(
      List<Keyframe> keyframes, String property) {
    final filtered =
        keyframes.where((k) => k.property == property).toList();
    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return 0.0;
  }

  static double _applyEasing(double t, String easing) {
    switch (easing) {
      case 'ease-in':
        return t * t;
      case 'ease-out':
        return t * (2 - t);
      case 'ease-in-out':
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
      case 'bounce':
        return _bounce(t);
      case 'elastic':
        return _elastic(t);
      default:
        return t; // linear
    }
  }

  static double _bounce(double t) {
    if (t < 1 / 2.75) return 7.5625 * t * t;
    if (t < 2 / 2.75) return 7.5625 * (t -= 1.5 / 2.75) * t + 0.75;
    if (t < 2.5 / 2.75) return 7.5625 * (t -= 2.25 / 2.75) * t + 0.9375;
    return 7.5625 * (t -= 2.625 / 2.75) * t + 0.984375;
  }

  static double _elastic(double t) {
    if (t == 0 || t == 1) return t;
    return math.pow(2, -10 * t) *
            math.sin((t - 0.075) * (2 * math.pi) / 0.3) +
        1;
  }
}

/// Stores animation state for a clip during playback
class ClipAnimationState {
  final String clipId;
  final List<Keyframe> keyframes;
  double _currentTime = 0.0;

  ClipAnimationState({
    required this.clipId,
    required this.keyframes,
  });

  double get currentTime => _currentTime;

  void update(double playheadSec, double clipStart) {
    _currentTime = playheadSec - clipStart;
  }

  double getValue(String property) {
    return KeyframeAnimationEngine.interpolate(keyframes, property, _currentTime);
  }

  Vector2D getVector2D(String property) {
    return KeyframeAnimationEngine.interpolateVector2D(keyframes, property, _currentTime);
  }

  bool get hasKeyframes => keyframes.isNotEmpty;
}
