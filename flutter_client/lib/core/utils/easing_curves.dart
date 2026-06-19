import 'dart:math' as math;

class CubicBezier {
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  const CubicBezier(this.x1, this.y1, this.x2, this.y2);

  static const CubicBezier linear = CubicBezier(0, 0, 1, 1);
  static const CubicBezier easeIn = CubicBezier(0.42, 0, 1, 1);
  static const CubicBezier easeOut = CubicBezier(0, 0, 0.58, 1);
  static const CubicBezier easeInOut = CubicBezier(0.42, 0, 0.58, 1);

  double evaluate(double t) {
    double guess = t;
    for (int i = 0; i < 10; i++) {
      final x = _sampleCurveX(guess) - t;
      if (x.abs() < 1e-6) break;
      final dx = _sampleCurveDerivativeX(guess);
      if (dx.abs() < 1e-6) break;
      guess -= x / dx;
    }
    guess = guess.clamp(0.0, 1.0);
    return _sampleCurveY(guess);
  }

  double _sampleCurveX(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * x1 +
        3.0 * (1.0 - t) * t * t * x2 +
        t * t * t;
  }

  double _sampleCurveY(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * y1 +
        3.0 * (1.0 - t) * t * t * y2 +
        t * t * t;
  }

  double _sampleCurveDerivativeX(double t) {
    return 3.0 * (1.0 - t) * (1.0 - t) * x1 +
        6.0 * (1.0 - t) * t * (x2 - x1) +
        3.0 * t * t * (1.0 - x2);
  }
}

double evaluateWithEasing(double t, String easing) {
  switch (easing) {
    case 'ease-in':
      return CubicBezier.easeIn.evaluate(t);
    case 'ease-out':
      return CubicBezier.easeOut.evaluate(t);
    case 'ease-in-out':
      return CubicBezier.easeInOut.evaluate(t);
    case 'bounce':
      return _bounce(t);
    case 'elastic':
      return _elastic(t);
    case 'linear':
    default:
      return t;
  }
}

CubicBezier easingToBezier(String easing) {
  switch (easing) {
    case 'ease-in':
      return CubicBezier.easeIn;
    case 'ease-out':
      return CubicBezier.easeOut;
    case 'ease-in-out':
      return CubicBezier.easeInOut;
    case 'linear':
    default:
      return CubicBezier.linear;
  }
}

double _bounce(double t) {
  if (t < 1 / 2.75) return 7.5625 * t * t;
  if (t < 2 / 2.75) return 7.5625 * (t -= 1.5 / 2.75) * t + 0.75;
  if (t < 2.5 / 2.75) return 7.5625 * (t -= 2.25 / 2.75) * t + 0.9375;
  return 7.5625 * (t -= 2.625 / 2.75) * t + 0.984375;
}

double _elastic(double t) {
  if (t == 0 || t == 1) return t;
  return math.pow(2, -10 * t) * math.sin((t - 0.075) * (2 * math.pi) / 0.3) + 1;
}
