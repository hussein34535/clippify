import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ShaderManager {
  static final ShaderManager _instance = ShaderManager._internal();
  factory ShaderManager() => _instance;
  ShaderManager._internal();

  Future<void> loadAll() async {
    debugPrint('[ShaderManager] Shader system ready. Effects use ColorFilter.matrix instead.');
  }
}

class BrightnessContrastEffect extends StatelessWidget {
  final Widget child;
  final double brightness;
  final double contrast;

  const BrightnessContrastEffect({
    super.key,
    required this.child,
    this.brightness = 0.0,
    this.contrast = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final b = brightness * 255.0;
    final c = contrast;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        c, 0, 0, 0, b,
        0, c, 0, 0, b,
        0, 0, c, 0, b,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}

class SaturationEffect extends StatelessWidget {
  final Widget child;
  final double saturation;

  const SaturationEffect({
    super.key,
    required this.child,
    this.saturation = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final s = saturation;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
        0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}

class VignetteEffect extends StatelessWidget {
  final Widget child;
  final double intensity;
  final double radius;

  const VignetteEffect({
    super.key,
    required this.child,
    this.intensity = 0.5,
    this.radius = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: intensity),
                ],
                stops: [radius, 1.0],
                center: Alignment.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SepiaEffect extends StatelessWidget {
  final Widget child;
  final double intensity;

  const SepiaEffect({super.key, required this.child, this.intensity = 1.0});

  @override
  Widget build(BuildContext context) {
    final i = intensity;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        0.393 + 0.607 * (1 - i), 0.769 - 0.769 * (1 - i), 0.189 - 0.189 * (1 - i), 0, 0,
        0.349 - 0.349 * (1 - i), 0.686 + 0.314 * (1 - i), 0.168 - 0.168 * (1 - i), 0, 0,
        0.272 - 0.272 * (1 - i), 0.534 - 0.534 * (1 - i), 0.131 + 0.869 * (1 - i), 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}

class InvertEffect extends StatelessWidget {
  final Widget child;
  const InvertEffect({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}

class PixelateEffect extends StatelessWidget {
  final Widget child;
  final int blockSize;

  const PixelateEffect({super.key, required this.child, this.blockSize = 8});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: blockSize / 4.0, sigmaY: blockSize / 4.0),
      child: child,
    );
  }
}

class BlurEffect extends StatelessWidget {
  final Widget child;
  final double sigma;
  const BlurEffect({super.key, required this.child, this.sigma = 5.0});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

class SharpenEffect extends StatelessWidget {
  final Widget child;
  final double intensity;

  const SharpenEffect({super.key, required this.child, this.intensity = 0.5});

  @override
  Widget build(BuildContext context) {
    final i = (intensity * 2).clamp(0.0, 1.0);
    return ColorFiltered(
      colorFilter: ColorFilter.matrix([
        1 + i, -i / 4, -i / 4, 0, 0,
        -i / 4, 1 + i, -i / 4, 0, 0,
        -i / 4, -i / 4, 1 + i, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: child,
    );
  }
}

