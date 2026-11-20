import 'dart:math' as math;

import 'package:flutter/material.dart';

class ReelArt extends StatelessWidget {
  const ReelArt({super.key});

  @override
  Widget build(BuildContext context) => const ExcludeSemantics(
    child: AspectRatio(
      aspectRatio: 1.75,
      child: ClipRRect(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        child: RepaintBoundary(child: CustomPaint(painter: _ReelArtPainter())),
      ),
    ),
  );
}

class _ReelArtPainter extends CustomPainter {
  const _ReelArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF282034), Color(0xFF151320)],
        ).createShader(bounds),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = size.shortestSide / 210;
    canvas.scale(scale);
    final grid = Paint()
      ..color = const Color(0xFF3F354D)
      ..strokeWidth = 0.8;
    for (var column = -260; column <= 260; column += 18) {
      canvas.drawLine(
        Offset(column.toDouble(), -115),
        Offset(column.toDouble(), 115),
        grid,
      );
    }
    for (var row = -108; row <= 108; row += 18) {
      canvas.drawLine(
        Offset(-260, row.toDouble()),
        Offset(260, row.toDouble()),
        grid,
      );
    }
    _frame(canvas, const Offset(-94, 0), -0.16, const Color(0xFF282137));
    _frame(canvas, const Offset(94, 0), 0.16, const Color(0xFF302841));

    const poster = Rect.fromLTWH(-51, -89, 102, 178);
    final rounded = RRect.fromRectAndRadius(poster, const Radius.circular(9));
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRect(
      poster,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF3F295D), Color(0xFF7855A7), Color(0xFFF1B9B6)],
        ).createShader(poster),
    );
    final filament = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x18FFF0FB), Color(0xDDFCF0FB), Color(0x88714B9C)],
      ).createShader(poster);
    canvas.save();
    canvas.rotate(-0.56);
    for (var ring = 0; ring < 24; ring++) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(8 + ring * 0.82, -1 + ring * 1.48),
          width: 25.0 + ring * 4.3,
          height: 41.0 + ring * 5.6,
        ),
        filament,
      );
    }
    canvas.restore();
    canvas.drawRect(
      const Rect.fromLTRB(-51, 57, 51, 89),
      Paint()..color = const Color(0xAB1F172D),
    );
    final wave = Paint()
      ..color = const Color(0xFFF6E3FF)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;
    for (var sample = 0; sample < 23; sample++) {
      final x = -40.0 + sample * 3.65;
      final amplitude =
          1.4 + 8 * (math.sin(sample * 1.2) * math.cos(sample * .32)).abs();
      canvas.drawLine(
        Offset(x, 72 - amplitude),
        Offset(x, 72 + amplitude),
        wave,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFFDFCAFA),
    );
    canvas.restore();
  }

  void _frame(Canvas canvas, Offset offset, double rotation, Color color) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(rotation);
    final frame = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-42, -66, 84, 132),
      const Radius.circular(8),
    );
    canvas.drawRRect(frame, Paint()..color = color);
    canvas.drawRRect(
      frame,
      Paint()
        ..color = const Color(0xFF6B587E)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke,
    );
    final detail = Paint()..color = const Color(0xFF61516F);
    canvas.drawRect(const Rect.fromLTWH(-26, 33, 52, 1), detail);
    canvas.drawRect(const Rect.fromLTWH(-26, 42, 33, 1), detail);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ReelArtPainter oldDelegate) => false;
}
