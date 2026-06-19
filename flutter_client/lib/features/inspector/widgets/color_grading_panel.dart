import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';
import '../../color/color_grading_advanced.dart';

class ColorWheel extends StatefulWidget {
  final double hue;
  final double saturation;
  final ValueChanged<double> onHueChanged;
  final ValueChanged<double> onSaturationChanged;

  const ColorWheel({
    super.key,
    required this.hue,
    required this.saturation,
    required this.onHueChanged,
    required this.onSaturationChanged,
  });

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
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
        size: const Size(120, 120),
        painter: _ColorWheelPainter(hue: widget.hue, saturation: widget.saturation),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  final double hue;
  final double saturation;

  _ColorWheelPainter({required this.hue, required this.saturation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(center.dx, center.dy);

    for (double a = 0; a < 360; a += 1) {
      final rad = a * math.pi / 180;
      final outer = Offset(center.dx + radius * math.cos(rad), center.dy + radius * math.sin(rad));
      final inner = Offset(center.dx + radius * 0.3 * math.cos(rad), center.dy + radius * 0.3 * math.sin(rad));
      canvas.drawLine(inner, outer, Paint()..color = HSLColor.fromAHSL(1.0, a, 1.0, 0.5).toColor()..strokeWidth = 2);
    }

    final selAngle = (hue - 90) * math.pi / 180;
    final selDist = radius * (0.3 + saturation * 0.7);
    final selPos = Offset(center.dx + selDist * math.cos(selAngle), center.dy + selDist * math.sin(selAngle));
    canvas.drawCircle(selPos, 6, Paint()..color = Colors.white);
    canvas.drawCircle(selPos, 4, Paint()..color = HSLColor.fromAHSL(1.0, hue, saturation, 0.5).toColor());
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter old) => old.hue != hue || old.saturation != saturation;
}

class ColorPresets extends StatelessWidget {
  final ColorGradingState currentState;
  final ValueChanged<ColorGradingState> onChanged;

  const ColorPresets({super.key, required this.currentState, required this.onChanged});

  static final List<Map<String, dynamic>> _presets = [
    {'name': 'طبيعي', 'brightness': 0.0, 'contrast': 1.0, 'saturation': 1.0, 'temperature': 0.0, 'icon': Icons.check_circle_outline},
    {'name': 'سينمائي', 'brightness': -0.05, 'contrast': 1.3, 'saturation': 0.7, 'temperature': -10, 'icon': Icons.movie_outlined},
    {'name': 'فينتج', 'brightness': 0.05, 'contrast': 1.1, 'saturation': 0.5, 'temperature': 15, 'icon': Icons.colorize},
    {'name': 'نيون', 'brightness': 0.0, 'contrast': 1.5, 'saturation': 1.8, 'temperature': -20, 'icon': Icons.sunny},
    {'name': 'أبيض وأسود', 'brightness': 0.0, 'contrast': 1.2, 'saturation': 0.0, 'temperature': 0.0, 'icon': Icons.blur_on},
    {'name': 'دافيء', 'brightness': 0.03, 'contrast': 1.1, 'saturation': 1.2, 'temperature': 30, 'icon': Icons.whatshot},
    {'name': 'بارد', 'brightness': 0.02, 'contrast': 1.0, 'saturation': 0.9, 'temperature': -30, 'icon': Icons.ac_unit},
    {'name': 'درامي', 'brightness': -0.1, 'contrast': 1.6, 'saturation': 0.6, 'temperature': -5, 'icon': Icons.thunderstorm},
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((p) => _PresetButton(preset: p, onTap: onChanged)).toList(),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final Map<String, dynamic> preset;
  final ValueChanged<ColorGradingState> onTap;

  const _PresetButton({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(ColorGradingState(
        brightness: preset['brightness'] as double,
        contrast: preset['contrast'] as double,
        saturation: preset['saturation'] as double,
        temperature: preset['temperature'] as double,
      )),
      child: Container(
        width: 75,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(preset['icon'] as IconData, size: 22, color: AppColors.primary),
            const SizedBox(height: 4),
            Text(preset['name'] as String, style: const TextStyle(fontSize: 9, color: Colors.white), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class ColorGradingPanel extends StatefulWidget {
  final VideoClip clip;
  final ValueChanged<ColorGradingState> onChanged;

  const ColorGradingPanel({super.key, required this.clip, required this.onChanged});

  @override
  State<ColorGradingPanel> createState() => _ColorGradingPanelState();
}

class _ColorGradingPanelState extends State<ColorGradingPanel> {
  bool _isAdvanced = false;

  @override
  Widget build(BuildContext context) {
    if (!_isAdvanced) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('عجلة الألوان', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
              TextButton.icon(
                onPressed: () => setState(() => _isAdvanced = true),
                icon: const Icon(Icons.tune_rounded, size: 14),
                label: const Text('متقدم', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: ColorWheel(
              hue: widget.clip.colorGrading.temperature > 0 ? 30.0 : 210.0,
              saturation: widget.clip.colorGrading.saturation.clamp(0.0, 1.0),
              onHueChanged: (h) {
                final temp = (h > 180 ? h - 360 : h) / 3;
                widget.onChanged(widget.clip.colorGrading.copyWith(temperature: temp.clamp(-100.0, 100.0)));
              },
              onSaturationChanged: (s) =>
                  widget.onChanged(widget.clip.colorGrading.copyWith(saturation: s * 3)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('إعدادات جاهزة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          ColorPresets(currentState: widget.clip.colorGrading, onChanged: widget.onChanged),
          const SizedBox(height: 24),
          const Text('تحكم يدوي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),
          _buildSlider('السطوع', widget.clip.colorGrading.brightness, -1.0, 1.0,
              (v) => widget.onChanged(widget.clip.colorGrading.copyWith(brightness: v))),
          _buildSlider('التباين', widget.clip.colorGrading.contrast, 0.5, 2.0,
              (v) => widget.onChanged(widget.clip.colorGrading.copyWith(contrast: v))),
          _buildSlider('التشبع', widget.clip.colorGrading.saturation, 0.0, 3.0,
              (v) => widget.onChanged(widget.clip.colorGrading.copyWith(saturation: v))),
          _buildSlider('حرارة اللون', widget.clip.colorGrading.temperature, -100.0, 100.0,
              (v) => widget.onChanged(widget.clip.colorGrading.copyWith(temperature: v))),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('التحكم المتقدم', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            TextButton.icon(
              onPressed: () => setState(() => _isAdvanced = false),
              icon: const Icon(Icons.palette_rounded, size: 14),
              label: const Text('بسيط', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: ColorWheelAdvanced(
            hue: widget.clip.colorGrading.temperature > 0 ? 30.0 : 210.0,
            saturation: widget.clip.colorGrading.saturation.clamp(0.0, 1.0),
            brightness: ((widget.clip.colorGrading.brightness + 1.0) / 2.0).clamp(0.0, 1.0),
            onHueChanged: (h) {
              final temp = (h > 180 ? h - 360 : h) / 3;
              widget.onChanged(widget.clip.colorGrading.copyWith(temperature: temp.clamp(-100.0, 100.0)));
            },
            onSaturationChanged: (s) =>
                widget.onChanged(widget.clip.colorGrading.copyWith(saturation: s * 3)),
            onBrightnessChanged: (b) =>
                widget.onChanged(widget.clip.colorGrading.copyWith(brightness: b * 2 - 1)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('منحنيات RGB', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  ColorCurveEditor(
                    points: const [Offset(0, 0), Offset(0.25, 0.25), Offset(0.5, 0.5), Offset(0.75, 0.75), Offset(1, 1)],
                    curveColor: Colors.white,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('نطاق الموجة', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  WaveformScope(waveformData: List.generate(200, (i) => 0.5 + 0.3 * math.sin(i * 0.1))),
                  const SizedBox(height: 12),
                  const Text('مخطط متجه', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  VectorScope(vectors: List.generate(50, (i) => Offset(
                    (math.Random().nextDouble() - 0.5) * 0.8,
                    (math.Random().nextDouble() - 0.5) * 0.8,
                  ))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('إعدادات جاهزة', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        ColorPresets(currentState: widget.clip.colorGrading, onChanged: widget.onChanged),
        const SizedBox(height: 24),
        const Text('تحكم يدوي', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        _buildSlider('السطوع', widget.clip.colorGrading.brightness, -1.0, 1.0,
            (v) => widget.onChanged(widget.clip.colorGrading.copyWith(brightness: v))),
        _buildSlider('التباين', widget.clip.colorGrading.contrast, 0.5, 2.0,
            (v) => widget.onChanged(widget.clip.colorGrading.copyWith(contrast: v))),
        _buildSlider('التشبع', widget.clip.colorGrading.saturation, 0.0, 3.0,
            (v) => widget.onChanged(widget.clip.colorGrading.copyWith(saturation: v))),
        _buildSlider('حرارة اللون', widget.clip.colorGrading.temperature, -100.0, 100.0,
            (v) => widget.onChanged(widget.clip.colorGrading.copyWith(temperature: v))),
      ],
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                width: 40,
                child: Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace')),
              ),
              Expanded(
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  activeColor: AppColors.primary,
                  inactiveColor: AppColors.divider,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
