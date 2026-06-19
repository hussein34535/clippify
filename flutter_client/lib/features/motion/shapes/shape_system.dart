import 'dart:math' as math;
import 'package:flutter/material.dart';

abstract class ShapeLayer {
  final String id;
  final Offset position;
  final double rotation;
  final double opacity;
  final Color color;
  final bool visible;

  ShapeLayer({
    required this.id,
    this.position = Offset.zero,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.color = Colors.white,
    this.visible = true,
  });

  void render(Canvas canvas, Size size, double time);
}

class RectangleShape extends ShapeLayer {
  final double width;
  final double height;
  final double cornerRadius;

  RectangleShape({
    required super.id,
    super.position,
    super.color,
    this.width = 100,
    this.height = 100,
    this.cornerRadius = 0,
    super.rotation,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size size, double time) {
    if (!visible) return;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation * math.pi / 180);
    final paint = Paint()..color = color.withValues(alpha: opacity);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-width / 2, -height / 2, width, height),
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(rrect, paint);
    canvas.restore();
  }
}

class EllipseShape extends ShapeLayer {
  final double radiusX;
  final double radiusY;

  EllipseShape({
    required super.id,
    super.position,
    super.color,
    this.radiusX = 50,
    this.radiusY = 50,
    super.rotation,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size size, double time) {
    if (!visible) return;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation * math.pi / 180);
    final paint = Paint()..color = color.withValues(alpha: opacity);
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: radiusX * 2, height: radiusY * 2), paint);
    canvas.restore();
  }
}

class PolygonShape extends ShapeLayer {
  final int sides;
  final double radius;

  PolygonShape({
    required super.id,
    super.position,
    super.color,
    this.sides = 6,
    this.radius = 50,
    super.rotation,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size size, double time) {
    if (!visible) return;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation * math.pi / 180);
    final paint = Paint()..color = color.withValues(alpha: opacity);
    final path = Path();
    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = radius * math.cos(angle);
      final y = radius * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }
}

class StarShape extends ShapeLayer {
  final int points;
  final double outerRadius;
  final double innerRadius;

  StarShape({
    required super.id,
    super.position,
    super.color,
    this.points = 5,
    this.outerRadius = 50,
    this.innerRadius = 25,
    super.rotation,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size size, double time) {
    if (!visible) return;
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation * math.pi / 180);
    final paint = Paint()..color = color.withValues(alpha: opacity);
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i % 2 == 0 ? outerRadius : innerRadius;
      final x = r * math.cos(angle);
      final y = r * math.sin(angle);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    path.close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }
}

class LineShape extends ShapeLayer {
  final Offset endPoint;
  final double strokeWidth;

  LineShape({
    required super.id,
    super.position,
    super.color,
    required this.endPoint,
    this.strokeWidth = 2,
    super.rotation,
    super.opacity,
  });

  @override
  void render(Canvas canvas, Size size, double time) {
    if (!visible) return;
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawLine(position, endPoint, paint);
  }
}

class ShapeRenderer extends CustomPainter {
  final List<ShapeLayer> shapes;
  final double time;

  ShapeRenderer({required this.shapes, required this.time});

  @override
  void paint(Canvas canvas, Size size) {
    for (final shape in shapes) {
      shape.render(canvas, size, time);
    }
  }

  @override
  bool shouldRepaint(covariant ShapeRenderer oldDelegate) =>
      oldDelegate.time != time || oldDelegate.shapes != shapes;
}

class ShapeLayerWidget extends StatelessWidget {
  final List<ShapeLayer> shapes;
  final double time;

  const ShapeLayerWidget({
    super.key,
    required this.shapes,
    this.time = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ShapeRenderer(shapes: shapes, time: time),
      size: Size.infinite,
    );
  }
}
