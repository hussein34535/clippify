import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/theme/app_theme.dart';

class KeyframeEditor extends StatefulWidget {
  final List<Keyframe> keyframes;
  final String property;
  final double clipDuration;
  final ValueChanged<List<Keyframe>> onChanged;

  const KeyframeEditor({
    super.key,
    required this.keyframes,
    required this.property,
    required this.clipDuration,
    required this.onChanged,
  });

  @override
  State<KeyframeEditor> createState() => _KeyframeEditorState();
}

class _KeyframeEditorState extends State<KeyframeEditor> {
  late List<Keyframe> _keyframes;

  @override
  void initState() {
    super.initState();
    _keyframes = List.from(widget.keyframes);
  }

  @override
  void didUpdateWidget(covariant KeyframeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _keyframes = List.from(widget.keyframes);
  }

  void _addKeyframe(double time) {
    final newKf = Keyframe(
      time: time.clamp(0.0, widget.clipDuration),
      property: widget.property,
      value: 0.0,
      easing: 'linear',
    );
    setState(() {
      _keyframes.add(newKf);
      _keyframes.sort((a, b) => a.time.compareTo(b.time));
    });
    widget.onChanged(List.from(_keyframes));
  }

  void _removeKeyframe(int index) {
    setState(() => _keyframes.removeAt(index));
    widget.onChanged(List.from(_keyframes));
  }

  void _updateKeyframe(int index, double newTime) {
    setState(() {
      _keyframes[index] = Keyframe(
        time: newTime.clamp(0.0, widget.clipDuration),
        property: widget.property,
        value: _keyframes[index].value,
        easing: _keyframes[index].easing,
      );
      _keyframes.sort((a, b) => a.time.compareTo(b.time));
    });
    widget.onChanged(List.from(_keyframes));
  }

  void _setEasing(int index, String easing) {
    setState(() {
      _keyframes[index] = Keyframe(
        time: _keyframes[index].time,
        property: widget.property,
        value: _keyframes[index].value,
        easing: easing,
      );
    });
    widget.onChanged(List.from(_keyframes));
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
                  'Keyframes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_keyframes.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _addKeyframe(0),
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
            height: 60,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    final time = (details.localPosition.dx / constraints.maxWidth) * widget.clipDuration;
                    _addKeyframe(time);
                  },
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 60),
                    painter: _KeyframeTimelinePainter(
                      keyframes: _keyframes,
                      duration: widget.clipDuration,
                      property: widget.property,
                    ),
                  ),
                );
              },
            ),
          ),
          if (_keyframes.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Divider(color: AppColors.divider, height: 1),
            ),
            SizedBox(
              height: 80,
              child: ListView.builder(
                itemCount: _keyframes.length,
                itemBuilder: (context, index) {
                  final kf = _keyframes[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _removeKeyframe(index),
                          child: const Icon(Icons.remove_circle_outline, size: 14, color: Colors.redAccent),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 50,
                          child: Text(
                            '${kf.time.toStringAsFixed(1)}s',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 20,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                              ),
                              child: Slider(
                                value: kf.time,
                                min: 0,
                                max: widget.clipDuration,
                                onChanged: (val) => _updateKeyframe(index, val),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 70,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: kf.easing,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 'linear', child: Text('Linear', style: TextStyle(fontSize: 9))),
                                DropdownMenuItem(value: 'ease-in', child: Text('Ease In', style: TextStyle(fontSize: 9))),
                                DropdownMenuItem(value: 'ease-out', child: Text('Ease Out', style: TextStyle(fontSize: 9))),
                                DropdownMenuItem(value: 'ease-in-out', child: Text('Ease InOut', style: TextStyle(fontSize: 9))),
                                DropdownMenuItem(value: 'bounce', child: Text('Bounce', style: TextStyle(fontSize: 9))),
                              ],
                              onChanged: (val) {
                                if (val != null) _setEasing(index, val);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyframeTimelinePainter extends CustomPainter {
  final List<Keyframe> keyframes;
  final double duration;
  final String property;

  _KeyframeTimelinePainter({
    required this.keyframes,
    required this.duration,
    required this.property,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (keyframes.isEmpty) return;

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF1E1F24),
    );

    // Draw grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;
    for (double t = 0; t <= duration; t += 0.5) {
      final x = (t / duration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // Draw connection lines between keyframes
    if (keyframes.length > 1) {
      final linePaint = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int i = 0; i < keyframes.length; i++) {
        final x = (keyframes[i].time / duration) * size.width;
        final y = size.height - (i.toDouble() / (keyframes.length - 1)) * (size.height - 16) - 8;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Draw keyframe diamonds
    for (int i = 0; i < keyframes.length; i++) {
      final kf = keyframes[i];
      final x = (kf.time / duration) * size.width;
      final centerY = size.height / 2;

      final diamondPaint = Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.fill;
      final path = Path();
      path.moveTo(x, centerY - 6);
      path.lineTo(x + 4, centerY);
      path.lineTo(x, centerY + 6);
      path.lineTo(x - 4, centerY);
      path.close();
      canvas.drawPath(path, diamondPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KeyframeTimelinePainter oldDelegate) {
    return oldDelegate.keyframes != keyframes ||
        oldDelegate.duration != duration;
  }
}
