import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/models/pro_color_models.dart';
import '../../core/models/timeline_models.dart';
import '../../core/theme/app_theme.dart';
import 'color_grading_advanced.dart';

class ProColorWheel extends StatefulWidget {
  final String label;
  final LiftGammaGain value;
  final ValueChanged<LiftGammaGain> onChanged;

  const ProColorWheel({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<ProColorWheel> createState() => _ProColorWheelState();
}

class _ProColorWheelState extends State<ProColorWheel> {
  DateTime? _lastTap;

  void _reset() {
    widget.onChanged(const LiftGammaGain());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (_) {
        final now = DateTime.now();
        if (_lastTap != null && now.difference(_lastTap!).inMilliseconds < 500) {
          _reset();
          _lastTap = null;
          return;
        }
        _lastTap = now;
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          SizedBox(
            width: 120,
            height: 120,
            child: GestureDetector(
              onPanUpdate: (details) {
                final box = context.findRenderObject() as RenderBox;
                final local = box.globalToLocal(details.globalPosition);
                final center = Offset(60, 60);
                final dx = local.dx - center.dx;
                final dy = local.dy - center.dy;
                final dist = math.sqrt(dx * dx + dy * dy);
                final maxR = 60.0;
                final sat = (dist / maxR).clamp(0.0, 1.0);
                final angle = math.atan2(dy, dx);
                var hue = (angle * 180 / math.pi + 90) % 360;
                if (hue < 0) hue += 360;
                widget.onChanged(widget.value.copyWith(
                    hue: hue, saturation: sat));
              },
              child: CustomPaint(
                size: const Size(120, 120),
                painter: _ProWheelPainter(value: widget.value),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 120,
            height: 12,
            child: GestureDetector(
              onPanUpdate: (details) {
                final box = context.findRenderObject() as RenderBox;
                final local = box.globalToLocal(details.globalPosition);
                final lum = (1.0 - (local.dy - 140) / 12).clamp(0.0, 1.0);
                widget.onChanged(widget.value.copyWith(luminance: lum));
              },
              child: CustomPaint(
                size: const Size(120, 12),
                painter: _LumBarPainter(
                    luminance: widget.value.luminance,
                    color: HSLColor.fromAHSL(
                            1.0, widget.value.hue, widget.value.saturation, 0.5)
                        .toColor()),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${widget.value.hue.toStringAsFixed(0)}° ${(widget.value.saturation * 100).toInt()}%',
            style: const TextStyle(
                fontSize: 8, color: AppColors.textMuted, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _ProWheelPainter extends CustomPainter {
  final LiftGammaGain value;
  _ProWheelPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(center.dx, center.dy);

    for (double a = 0; a < 360; a += 1) {
      final rad = a * math.pi / 180;
      final outer = Offset(
          center.dx + radius * math.cos(rad),
          center.dy + radius * math.sin(rad));
      final inner = Offset(
          center.dx + radius * 0.3 * math.cos(rad),
          center.dy + radius * 0.3 * math.sin(rad));
      canvas.drawLine(
          inner,
          outer,
          Paint()
            ..color = HSLColor.fromAHSL(1.0, a, 1.0, 0.5).toColor()
            ..strokeWidth = 2);
    }

    final selAngle = (value.hue - 90) * math.pi / 180;
    final selDist = radius * (0.3 + value.saturation * 0.7);
    final selPos = Offset(
        center.dx + selDist * math.cos(selAngle),
        center.dy + selDist * math.sin(selAngle));
    canvas.drawCircle(selPos, 7, Paint()..color = Colors.white);
    canvas.drawCircle(
        selPos,
        5,
        Paint()
          ..color = HSLColor.fromAHSL(
                  1.0, value.hue, value.saturation, 0.5)
              .toColor());
  }

  @override
  bool shouldRepaint(covariant _ProWheelPainter o) =>
      o.value.hue != value.hue || o.value.saturation != value.saturation;
}

class _LumBarPainter extends CustomPainter {
  final double luminance;
  final Color color;
  _LumBarPainter({required this.luminance, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      colors: [Colors.black, color, Colors.white],
    );
    canvas.drawRect(
        rect,
        Paint()
          ..shader = gradient.createShader(rect)
          ..style = PaintingStyle.fill);

    final handleX = luminance * size.width;
    canvas.drawCircle(
        Offset(handleX, size.height / 2), 4, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(handleX, size.height / 2), 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LumBarPainter o) =>
      o.luminance != luminance || o.color != color;
}

class ProColorPanel extends StatefulWidget {
  final ProColorState proColor;
  final ColorGradingState basicColor;
  final ValueChanged<ProColorState> onProChanged;
  final ValueChanged<ColorGradingState> onBasicChanged;
  final VoidCallback? onLoadLut;

  const ProColorPanel({
    super.key,
    required this.proColor,
    required this.basicColor,
    required this.onProChanged,
    required this.onBasicChanged,
    this.onLoadLut,
  });

  @override
  State<ProColorPanel> createState() => _ProColorPanelState();
}

class _ProColorPanelState extends State<ProColorPanel> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lift / Gamma / Gain',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ProColorWheel(
                label: 'Lift',
                value: widget.proColor.lift,
                onChanged: (v) =>
                    widget.onProChanged(widget.proColor.copyWith(lift: v)),
              ),
              ProColorWheel(
                label: 'Gamma',
                value: widget.proColor.gamma,
                onChanged: (v) =>
                    widget.onProChanged(widget.proColor.copyWith(gamma: v)),
              ),
              ProColorWheel(
                label: 'Gain',
                value: widget.proColor.gain,
                onChanged: (v) =>
                    widget.onProChanged(widget.proColor.copyWith(gain: v)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Master',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          _buildSlider('Offset', widget.proColor.offset, -0.5, 0.5, (v) =>
              widget.onProChanged(widget.proColor.copyWith(offset: v))),
          _buildSlider('Contrast', widget.proColor.contrast, 0.0, 3.0, (v) =>
              widget.onProChanged(widget.proColor.copyWith(contrast: v))),
          _buildSlider('Pivot', widget.proColor.pivot, 0.0, 1.0, (v) =>
              widget.onProChanged(widget.proColor.copyWith(pivot: v))),
          _buildSlider('Shadow Clip', widget.proColor.shadowClip, 0.0, 1.0,
              (v) =>
                  widget.onProChanged(widget.proColor.copyWith(shadowClip: v))),
          _buildSlider('Highlight Clip', widget.proColor.highlightClip, 0.0,
              1.0, (v) =>
                  widget.onProChanged(widget.proColor.copyWith(highlightClip: v))),
          const SizedBox(height: 20),
          const Text('3D LUT',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    widget.proColor.lutPath.isEmpty
                        ? 'No LUT loaded'
                        : widget.proColor.lutPath.split('\\').last.split('/').last,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.proColor.lutPath.isEmpty
                          ? AppColors.textMuted
                          : Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.folder_open_rounded,
                    size: 18, color: AppColors.primary),
                onPressed: widget.onLoadLut,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textMuted),
                onPressed: widget.proColor.lutPath.isEmpty
                    ? null
                    : () => widget.onProChanged(
                        widget.proColor.copyWith(lutPath: '')),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (widget.proColor.lutPath.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSlider('Intensity', widget.proColor.lutIntensity, 0.0, 1.0,
                (v) =>
                    widget.onProChanged(widget.proColor.copyWith(lutIntensity: v))),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('HDR',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              SizedBox(
                height: 20,
                child: Switch.adaptive(
                  value: widget.proColor.hdrEnabled,
                  onChanged: (v) => widget
                      .onProChanged(widget.proColor.copyWith(hdrEnabled: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('Scopes',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          const SizedBox(height: 8),
          WaveformScope(waveformData: _demoWaveform),
          const SizedBox(height: 8),
          VectorScope(vectors: _demoVectors),
          const SizedBox(height: 8),
          Histogram(data: _demoHistogram),

        ],
      ),
    );
  }

  Widget _buildSlider(
      String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.divider,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(value.toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textMuted,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  static final List<double> _demoWaveform =
      List.generate(200, (i) => 0.3 + 0.4 * math.sin(i * 0.08) + 0.1 * math.sin(i * 0.3));

  static final List<Offset> _demoVectors =
      List.generate(80, (i) {
    final a = i * 0.4;
    return Offset(
      0.5 * math.cos(a) + (math.Random().nextDouble() - 0.5) * 0.2,
      0.5 * math.sin(a) + (math.Random().nextDouble() - 0.5) * 0.2,
    );
  });

  static final List<List<double>> _demoHistogram = [
    List.generate(256, (i) => 0.3 + 0.5 * math.exp(-((i - 80) * (i - 80)) / 2000)),
    List.generate(256, (i) => 0.3 + 0.5 * math.exp(-((i - 140) * (i - 140)) / 2000)),
    List.generate(256, (i) => 0.3 + 0.5 * math.exp(-((i - 200) * (i - 200)) / 2000)),
  ];
}

class Histogram extends StatelessWidget {
  final List<List<double>> data;

  const Histogram({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: CustomPaint(
        size: const Size(double.infinity, 80),
        painter: _HistogramPainter(data: data),
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final List<List<double>> data;
  _HistogramPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 3) return;
    final colors = [
      Colors.red.withValues(alpha: 0.7),
      Colors.green.withValues(alpha: 0.7),
      Colors.blue.withValues(alpha: 0.7),
    ];

    for (int c = 0; c < 3; c++) {
      final paint = Paint()
        ..color = colors[c]
        ..strokeWidth = 1;
      final path = Path();
      final values = data[c];
      for (int i = 0; i < values.length; i++) {
        final x = i * size.width / values.length;
        final y = (1.0 - values[i].clamp(0.0, 1.0)) * size.height;
        if (i == 0) {
          path.moveTo(x, size.height);
          path.lineTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter o) => o.data != data;
}
