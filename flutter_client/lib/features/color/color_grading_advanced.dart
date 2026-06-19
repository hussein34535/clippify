import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class ColorWheelAdvanced extends StatefulWidget {
  final double hue;
  final double saturation;
  final double brightness;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSaturationChanged;
  final ValueChanged<double> onBrightnessChanged;

  const ColorWheelAdvanced({
    super.key,
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.onHueChanged,
    required this.onSaturationChanged,
    required this.onBrightnessChanged,
  });

  @override
  State<ColorWheelAdvanced> createState() => _ColorWheelAdvancedState();
}

class _ColorWheelAdvancedState extends State<ColorWheelAdvanced> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        final box = context.findRenderObject() as RenderBox;
        final local = box.globalToLocal(details.globalPosition);
        final center = Offset(box.size.width / 2, box.size.height / 2);
        final dx = local.dx - center.dx;
        final dy = local.dy - center.dy;
        final dist = math.sqrt(dx * dx + dy * dy);
        final maxR = math.min(center.dx, center.dy);
        final sat = (dist / maxR).clamp(0.0, 1.0);
        final angle = math.atan2(dy, dx);
        var hue = (angle * 180 / math.pi + 90) % 360;
        if (hue < 0) hue += 360;
        widget.onSaturationChanged(sat);
        widget.onHueChanged(hue);
      },
      child: CustomPaint(
        size: const Size(180, 180),
        painter: _ColorWheelAdvancedPainter(
          hue: widget.hue, saturation: widget.saturation, brightness: widget.brightness,
        ),
      ),
    );
  }
}

class _ColorWheelAdvancedPainter extends CustomPainter {
  final double hue; final double saturation; final double brightness;
  _ColorWheelAdvancedPainter({required this.hue, required this.saturation, required this.brightness});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(center.dx, center.dy);
    final outerR = radius;

    // Color ring
    for (double a = 0; a < 360; a += 0.5) {
      final rad = a * math.pi / 180;
      final outer = Offset(center.dx + outerR * math.cos(rad), center.dy + outerR * math.sin(rad));
      final inner = Offset(center.dx + outerR * 0.75 * math.cos(rad), center.dy + outerR * 0.75 * math.sin(rad));
      canvas.drawLine(inner, outer, Paint()
        ..color = HSLColor.fromAHSL(1.0, a, 1.0, 0.5).toColor()
        ..strokeWidth = 3);
    }

    // Inner brightness circle
    for (double s = 0; s <= 1.0; s += 0.01) {
      final r = outerR * 0.75 * s;
      canvas.drawCircle(center, r, Paint()
        ..color = HSLColor.fromAHSL(1.0, hue, s, 0.5).toColor()
        ..strokeWidth = 2);
    }

    // Selection indicator
    final selAngle = (hue - 90) * math.pi / 180;
    final selDist = outerR * 0.88;
    final selPos = Offset(center.dx + selDist * math.cos(selAngle), center.dy + selDist * math.sin(selAngle));
    canvas.drawCircle(selPos, 8, Paint()..color = Colors.white);
    canvas.drawCircle(selPos, 5, Paint()..color = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor());

    // Brightness indicator
    final briPos = Offset(center.dx, center.dy + outerR * 0.75 * (1 - brightness));
    canvas.drawCircle(briPos, 6, Paint()..color = Colors.white);
    final briVal = (brightness * 255).round();
    canvas.drawCircle(briPos, 4, Paint()..color = Color.fromRGBO(briVal, briVal, briVal, 1));
  }

  @override
  bool shouldRepaint(covariant _ColorWheelAdvancedPainter o) =>
    o.hue != hue || o.saturation != saturation || o.brightness != brightness;
}

class ColorCurveEditor extends StatelessWidget {
  final List<Offset> points;
  final Color curveColor;

  const ColorCurveEditor({super.key, required this.points, this.curveColor = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200, height: 200,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: CustomPaint(
        size: const Size(200, 200),
        painter: _CurvePainter(points: points, curveColor: curveColor),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<Offset> points;
  final Color curveColor;

  _CurvePainter({required this.points, required this.curveColor});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    final gridPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (int i = 0; i <= 4; i++) {
      final x = size.width * i / 4;
      final y = size.height * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Diagonal
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1);

    // Curve
    if (points.length >= 2) {
      final curvePaint = Paint()
        ..color = curveColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final x = points[i].dx * size.width;
        final y = (1 - points[i].dy) * size.height;
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(path, curvePaint);

      // Points
      for (final p in points) {
        final x = p.dx * size.width;
        final y = (1 - p.dy) * size.height;
        canvas.drawCircle(Offset(x, y), 5, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = curveColor);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter o) => o.points != points;
}

class WaveformScope extends StatelessWidget {
  final List<double> waveformData;

  const WaveformScope({super.key, required this.waveformData});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200, height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: CustomPaint(
        size: const Size(200, 100),
        painter: _WaveformPainter(data: waveformData),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  _WaveformPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i * size.width / data.length;
      final y = (1 - data[i]) * size.height;
      if (i == 0) path.moveTo(x, size.height / 2);
      path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter o) => o.data != data;
}

class VectorScope extends StatelessWidget {
  final List<Offset> vectors;

  const VectorScope({super.key, required this.vectors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180, height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: CustomPaint(
        size: const Size(180, 180),
        painter: _VectorScopePainter(vectors: vectors),
      ),
    );
  }
}

class _VectorScopePainter extends CustomPainter {
  final List<Offset> vectors;
  _VectorScopePainter({required this.vectors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = AppColors.primary.withValues(alpha: 0.6);
    final radius = math.min(center.dx, center.dy);

    // Target circles
    canvas.drawCircle(center, radius * 0.5, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: 0.1));
    canvas.drawCircle(center, radius, Paint()..style = PaintingStyle.stroke..color = Colors.white.withValues(alpha: 0.1));

    for (final v in vectors) {
      final x = center.dx + v.dx * radius;
      final y = center.dy + v.dy * radius;
      canvas.drawCircle(Offset(x, y), 1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorScopePainter o) => o.vectors != vectors;
}
