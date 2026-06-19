import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';

class SpeedRampEditor extends StatefulWidget {
  final SpeedRamp speedRamp;
  final double clipDuration;
  final ValueChanged<SpeedRamp> onChanged;

  const SpeedRampEditor({
    super.key,
    required this.speedRamp,
    required this.clipDuration,
    required this.onChanged,
  });

  @override
  State<SpeedRampEditor> createState() => _SpeedRampEditorState();
}

class _SpeedRampEditorState extends State<SpeedRampEditor> {
  late List<SpeedPoint> _points;

  @override
  void initState() {
    super.initState();
    _points = List.from(widget.speedRamp.points);
  }

  void _addPoint() {
    final time = widget.clipDuration * 0.5;
    setState(() {
      _points.add(SpeedPoint(time: time, speed: 1.0));
      _points.sort((a, b) => a.time.compareTo(b.time));
    });
    widget.onChanged(SpeedRamp(points: List.from(_points)));
  }

  void _removePoint(int index) {
    setState(() => _points.removeAt(index));
    widget.onChanged(SpeedRamp(points: List.from(_points)));
  }

  void _updatePoint(int index, double time, double speed) {
    setState(() {
      _points[index] = SpeedPoint(
        time: time.clamp(0.0, widget.clipDuration),
        speed: speed.clamp(0.1, 10.0),
      );
      _points.sort((a, b) => a.time.compareTo(b.time));
    });
    widget.onChanged(SpeedRamp(points: List.from(_points)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                const Text(
                  'Speed Ramp',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('${_points.length} pts', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addPoint,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.add, size: 14, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 80,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final time = (details.localPosition.dx / constraints.maxWidth) * widget.clipDuration;
                    final speed = 1.0 + (1.0 - details.localPosition.dy / constraints.maxHeight) * 4.0;
                    _addPointAt(time, speed.clamp(0.1, 10.0));
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 80),
                    painter: _SpeedRampPainter(
                      points: _points,
                      duration: widget.clipDuration,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_points.isNotEmpty) ...[
            const Divider(color: AppColors.divider, height: 1),
            SizedBox(
              height: 100,
              child: ListView.builder(
                itemCount: _points.length,
                itemBuilder: (context, index) {
                  final pt = _points[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _removePoint(index),
                          child: const Icon(Icons.remove_circle_outline, size: 14, color: Colors.redAccent),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 40,
                          child: Text('${pt.time.toStringAsFixed(1)}s', style: const TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            ),
                            child: Slider(
                              value: pt.time,
                              min: 0,
                              max: widget.clipDuration,
                              onChanged: (val) => _updatePoint(index, val, pt.speed),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 50,
                          child: Text('${pt.speed.toStringAsFixed(1)}x', style: const TextStyle(color: AppColors.primary, fontSize: 10)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (_points.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'انقر على الرسم البياني لإضافة نقطة سرعة',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addPointAt(double time, double speed) {
    setState(() {
      _points.add(SpeedPoint(time: time.clamp(0.0, widget.clipDuration), speed: speed.clamp(0.1, 10.0)));
      _points.sort((a, b) => a.time.compareTo(b.time));
    });
    widget.onChanged(SpeedRamp(points: List.from(_points)));
  }
}

class _SpeedRampPainter extends CustomPainter {
  final List<SpeedPoint> points;
  final double duration;

  _SpeedRampPainter({required this.points, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF1E1F24));

    // Grid lines
    final gridPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (double t = 0; t <= duration; t += 1.0) {
      final x = (t / duration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Speed line
    if (points.isEmpty) {
      final centerY = size.height / 2;
      final linePaint = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), linePaint);
      return;
    }

    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = (points[i].time / (duration > 0 ? duration : 1)) * size.width;
      final y = size.height - ((points[i].speed - 0.1) / 9.9) * size.height;
      if (i == 0) {
        path.moveTo(x, y.clamp(0, size.height));
      } else {
        path.lineTo(x, y.clamp(0, size.height));
      }
    }
    canvas.drawPath(path, linePaint);

    // Points
    for (final pt in points) {
      final x = (pt.time / (duration > 0 ? duration : 1)) * size.width;
      final y = size.height - ((pt.speed - 0.1) / 9.9) * size.height;
      canvas.drawCircle(Offset(x, y.clamp(0, size.height)), 5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y.clamp(0, size.height)), 4, Paint()..color = AppColors.primary);
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedRampPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.duration != duration;
}
