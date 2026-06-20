import 'package:flutter/material.dart';
import '../models/pro_color_models.dart';
import '../models/timeline_models.dart';

List<double> liftGammaGainToColorMatrix(LiftGammaGain lgg) {
  final color = HSLColor.fromAHSL(1.0, lgg.hue, lgg.saturation, lgg.luminance).toColor();
  final r = color.red / 255.0 - 0.5;
  final g = color.green / 255.0 - 0.5;
  final b = color.blue / 255.0 - 0.5;
  final intensity = lgg.saturation * 0.3;
  return [
    r * intensity,
    g * intensity,
    b * intensity,
    0, 0,
    r * intensity,
    g * intensity,
    b * intensity,
    0, 0,
    r * intensity,
    g * intensity,
    b * intensity,
    0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> buildCombinedColorMatrix(ColorGradingState basic, ProColorState pro) {
  final b = basic.brightness;
  final c = basic.contrast * pro.contrast;
  final s = basic.saturation;

  final rW = 0.2126 * s + (1.0 - s);
  final gW = 0.7152 * s + (1.0 - s);
  final bW = 0.0722 * s + (1.0 - s);
  final tR = 0.2126 * (1.0 - s);
  final tG = 0.7152 * (1.0 - s);
  final tB = 0.0722 * (1.0 - s);

  final liftHSL = HSLColor.fromAHSL(1.0, pro.lift.hue, pro.lift.saturation, pro.lift.luminance);
  final gammaHSL = HSLColor.fromAHSL(1.0, pro.gamma.hue, pro.gamma.saturation, pro.gamma.luminance);
  final gainHSL = HSLColor.fromAHSL(1.0, pro.gain.hue, pro.gain.saturation, pro.gain.luminance);

  final liftC = liftHSL.toColor();
  final gammaC = gammaHSL.toColor();
  final gainC = gainHSL.toColor();

  final lR = (liftC.red / 255.0 - 0.5) * pro.lift.saturation * 0.25;
  final lG = (liftC.green / 255.0 - 0.5) * pro.lift.saturation * 0.25;
  final lB = (liftC.blue / 255.0 - 0.5) * pro.lift.saturation * 0.25;

  final mR = (gammaC.red / 255.0 - 0.5) * pro.gamma.saturation * 0.15;
  final mG = (gammaC.green / 255.0 - 0.5) * pro.gamma.saturation * 0.15;
  final mB = (gammaC.blue / 255.0 - 0.5) * pro.gamma.saturation * 0.15;

  final hR = (gainC.red / 255.0 - 0.5) * pro.gain.saturation * 0.15;
  final hG = (gainC.green / 255.0 - 0.5) * pro.gain.saturation * 0.15;
  final hB = (gainC.blue / 255.0 - 0.5) * pro.gain.saturation * 0.15;

  final totalR = (lR + mR + hR) * 255.0;
  final totalG = (lG + mG + hG) * 255.0;
  final totalB = (lB + mB + hB) * 255.0;

  final brightnessOffset = (b + pro.offset) * 255.0;

  final clipMul = 1.0 / (1.0 - pro.shadowClip - pro.highlightClip).clamp(0.1, 10.0);

  return [
    c * rW * clipMul, c * tR * clipMul, c * tR * clipMul, 0, totalR + brightnessOffset,
    c * tG * clipMul, c * gW * clipMul, c * tG * clipMul, 0, totalG + brightnessOffset,
    c * tB * clipMul, c * tB * clipMul, c * bW * clipMul, 0, totalB + brightnessOffset,
    0, 0, 0, 1, 0,
  ];
}

String buildFfmpegLutFilter(String lutPath, double intensity) {
  final blend = intensity.clamp(0.0, 1.0);
  return 'lut3d=$lutPath, blend=all_mode=overlay:all_opacity=$blend';
}
