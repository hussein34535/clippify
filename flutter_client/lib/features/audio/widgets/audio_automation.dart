import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/audio_mixer.dart';
import '../providers/audio_mixer_provider.dart';

// ─────────────────────────────────────────────
// AutomationPoint
// ─────────────────────────────────────────────
class AutomationPoint {
  double time;
  double value;
  String easing;

  AutomationPoint({
    required this.time,
    required this.value,
    this.easing = 'linear',
  });

  Map<String, dynamic> toJson() => {'time': time, 'value': value, 'easing': easing};

  factory AutomationPoint.fromJson(Map<String, dynamic> json) => AutomationPoint(
        time: (json['time'] as num).toDouble(),
        value: (json['value'] as num).toDouble(),
        easing: json['easing'] as String? ?? 'linear',
      );
}

// ─────────────────────────────────────────────
// EffectParam
// ─────────────────────────────────────────────
class EffectParam {
  final String name;
  final String id;
  final double min;
  final double max;
  final double defaultValue;
  double value;

  EffectParam({
    required this.name,
    required this.id,
    this.min = 0.0,
    this.max = 1.0,
    this.defaultValue = 0.5,
    double? value,
  }) : value = value ?? defaultValue;
}

// ─────────────────────────────────────────────
// EffectDefinition
// ─────────────────────────────────────────────
class EffectDefinition {
  final String id;
  final String name;
  final IconData icon;
  final List<EffectParam> params;

  const EffectDefinition({
    required this.id,
    required this.name,
    required this.icon,
    required this.params,
  });
}

// ─────────────────────────────────────────────
// AVAILABLE EFFECTS
// ─────────────────────────────────────────────
final List<EffectDefinition> availableEffects = [
  EffectDefinition(
    id: 'eq',
    name: 'EQ',
    icon: Icons.tune_rounded,
    params: [
      EffectParam(name: 'Bass', id: 'bass', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Mid', id: 'mid', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Treble', id: 'treble', min: 0, max: 1, defaultValue: 0.5),
    ],
  ),
  EffectDefinition(
    id: 'compressor',
    name: 'Compressor',
    icon: Icons.compress_rounded,
    params: [
      EffectParam(name: 'Threshold', id: 'threshold', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Ratio', id: 'ratio', min: 1, max: 20, defaultValue: 4),
      EffectParam(name: 'Attack', id: 'attack', min: 0, max: 0.1, defaultValue: 0.002),
      EffectParam(name: 'Release', id: 'release', min: 0, max: 1, defaultValue: 0.1),
    ],
  ),
  EffectDefinition(
    id: 'reverb',
    name: 'Reverb',
    icon: Icons.waves_rounded,
    params: [
      EffectParam(name: 'Decay', id: 'decay', min: 0, max: 1, defaultValue: 0.3),
      EffectParam(name: 'Size', id: 'size', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Damping', id: 'damping', min: 0, max: 1, defaultValue: 0.5),
    ],
  ),
  EffectDefinition(
    id: 'delay',
    name: 'Delay',
    icon: Icons.timer_rounded,
    params: [
      EffectParam(name: 'Time', id: 'time', min: 0.01, max: 1, defaultValue: 0.2),
      EffectParam(name: 'Feedback', id: 'feedback', min: 0, max: 1, defaultValue: 0.3),
      EffectParam(name: 'Stereo', id: 'stereo', min: 0, max: 1, defaultValue: 0.5),
    ],
  ),
  EffectDefinition(
    id: 'distortion',
    name: 'Distortion',
    icon: Icons.waves_rounded,
    params: [
      EffectParam(name: 'Drive', id: 'drive', min: 1, max: 10, defaultValue: 2),
      EffectParam(name: 'Tone', id: 'tone', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Output', id: 'output', min: 0, max: 1, defaultValue: 0.7),
    ],
  ),
  EffectDefinition(
    id: 'chorus',
    name: 'Chorus',
    icon: Icons.multitrack_audio_rounded,
    params: [
      EffectParam(name: 'Rate', id: 'rate', min: 0.1, max: 5, defaultValue: 1),
      EffectParam(name: 'Depth', id: 'depth', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Mix', id: 'mix', min: 0, max: 1, defaultValue: 0.5),
    ],
  ),
  EffectDefinition(
    id: 'flanger',
    name: 'Flanger',
    icon: Icons.auto_fix_high_rounded,
    params: [
      EffectParam(name: 'Rate', id: 'rate', min: 0.1, max: 5, defaultValue: 0.5),
      EffectParam(name: 'Depth', id: 'depth', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Feedback', id: 'feedback', min: 0, max: 1, defaultValue: 0.3),
    ],
  ),
  EffectDefinition(
    id: 'phaser',
    name: 'Phaser',
    icon: Icons.history_rounded,
    params: [
      EffectParam(name: 'Rate', id: 'rate', min: 0.1, max: 5, defaultValue: 0.5),
      EffectParam(name: 'Depth', id: 'depth', min: 0, max: 1, defaultValue: 0.5),
      EffectParam(name: 'Stages', id: 'stages', min: 2, max: 12, defaultValue: 6),
    ],
  ),
  EffectDefinition(
    id: 'tremolo',
    name: 'Tremolo',
    icon: Icons.blur_on_rounded,
    params: [
      EffectParam(name: 'Rate', id: 'rate', min: 0.1, max: 10, defaultValue: 2),
      EffectParam(name: 'Depth', id: 'depth', min: 0, max: 1, defaultValue: 0.7),
      EffectParam(name: 'Shape', id: 'shape', min: 0, max: 1, defaultValue: 0.5),
    ],
  ),
  EffectDefinition(
    id: 'auto_pan',
    name: 'AutoPan',
    icon: Icons.swap_horiz_rounded,
    params: [
      EffectParam(name: 'Rate', id: 'rate', min: 0.1, max: 5, defaultValue: 0.5),
      EffectParam(name: 'Depth', id: 'depth', min: 0, max: 1, defaultValue: 1),
      EffectParam(name: 'Phase', id: 'phase', min: -180, max: 180, defaultValue: 90),
    ],
  ),
];

// ─────────────────────────────────────────────
// 1. AUTOMATION LANE
// ─────────────────────────────────────────────
class AutomationLane extends StatefulWidget {
  final String parameterName;
  final String parameterId;
  final double parameterMin;
  final double parameterMax;
  final double currentValue;
  final List<AutomationPoint> points;
  final ValueChanged<List<AutomationPoint>> onPointsChanged;
  final double clipDuration;
  final Color curveColor;

  const AutomationLane({
    super.key,
    required this.parameterName,
    required this.parameterId,
    this.parameterMin = 0.0,
    this.parameterMax = 1.0,
    required this.currentValue,
    required this.points,
    required this.onPointsChanged,
    required this.clipDuration,
    this.curveColor = AppColors.primary,
  });

  @override
  State<AutomationLane> createState() => _AutomationLaneState();
}

class _AutomationLaneState extends State<AutomationLane> {
  final GlobalKey _canvasKey = GlobalKey();
  Offset? _rubberStart;
  Offset? _rubberEnd;
  Set<int> _selectedIndices = {};
  int? _draggingIndex;
  bool _isDragging = false;
  Offset? _dragStartPos;
  Offset _dragOffset = Offset.zero;
  int? _hoveredIndex;

  List<AutomationPoint> get _points => widget.points;
  double get _duration => widget.clipDuration > 0 ? widget.clipDuration : 10.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 4),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: GestureDetector(
              onDoubleTapDown: (d) => _addPointAt(d.localPosition),
              onDoubleTap: () {},
              onPanStart: (d) => _onPanStart(d.localPosition),
              onPanUpdate: (d) => _onPanUpdate(d.localPosition),
              onPanEnd: (_) => _onPanEnd(),
              onLongPressStart: (d) => _onRightClick(d.localPosition),
              child: Consumer(
                builder: (context, ref, _) {
                  return LayoutBuilder(builder: (context, constraints) {
                    return GestureDetector(
                      onSecondaryTapDown: (d) => _showContextMenu(d.localPosition, constraints),
                      child: Container(
                        key: _canvasKey,
                        color: Colors.transparent,
                        child: CustomPaint(
                          size: Size(constraints.maxWidth, 120),
                          painter: _AutomationCurvePainter(
                            points: _points,
                            duration: _duration,
                            selectedIndices: _selectedIndices,
                            parameterMin: widget.parameterMin,
                            parameterMax: widget.parameterMax,
                            curveColor: widget.curveColor,
                            hoveredIndex: _hoveredIndex,
                            rubberRect: _rubberStart != null && _rubberEnd != null
                                ? Rect.fromPoints(_rubberStart!, _rubberEnd!)
                                : null,
                            dragOffset: _isDragging && _draggingIndex != null ? _dragOffset : Offset.zero,
                            draggingIndex: _draggingIndex,
                          ),
                        ),
                      ),
                    );
                  });
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final valRange = widget.parameterMax - widget.parameterMin;
    final normalized = valRange > 0
        ? ((widget.currentValue - widget.parameterMin) / valRange * 100).clamp(0, 100)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Row(
        children: [
          Text(
            widget.parameterName,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const Spacer(),
          Text(
            '${normalized.toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  void _addPointAt(Offset pos) {
    final size = _getCanvasSize();
    if (size <= 0) return;
    final time = (pos.dx / size).clamp(0.0, 1.0) * _duration;
    final value = widget.parameterMin +
        (1.0 - pos.dy / 120.0) * (widget.parameterMax - widget.parameterMin);
    final updated = List<AutomationPoint>.from(_points)
      ..add(AutomationPoint(time: time, value: value.clamp(widget.parameterMin, widget.parameterMax)));
    updated.sort((a, b) => a.time.compareTo(b.time));
    widget.onPointsChanged(updated);
  }

  void _onPanStart(Offset pos) {
    final hitIndex = _hitTestPoint(pos);
    if (hitIndex != null) {
      _draggingIndex = hitIndex;
      _isDragging = true;
      _dragStartPos = pos;
      _dragOffset = Offset.zero;
      if (!_selectedIndices.contains(hitIndex)) {
        _selectedIndices = {hitIndex};
      }
      setState(() {});
    } else {
      _rubberStart = pos;
      _rubberEnd = pos;
      _selectedIndices = {};
      setState(() {});
    }
  }

  void _onPanUpdate(Offset pos) {
    if (_isDragging && _draggingIndex != null) {
      final size = _getCanvasSize();
      if (size <= 0) return;
      final dx = pos.dx - (_dragStartPos?.dx ?? pos.dx);
      final dy = pos.dy - (_dragStartPos?.dy ?? pos.dy);
      _dragOffset = Offset(dx, dy);
      for (final idx in _selectedIndices) {
        if (idx >= 0 && idx < _points.length) {
          final newTime = (_points[idx].time + dx / size * _duration).clamp(0.0, _duration);
          final newValue = (_points[idx].value - dy / 120.0 * (widget.parameterMax - widget.parameterMin))
              .clamp(widget.parameterMin, widget.parameterMax);
          _points[idx].time = newTime;
          _points[idx].value = newValue;
        }
      }
      _points.sort((a, b) => a.time.compareTo(b.time));
      widget.onPointsChanged(List.from(_points));
      setState(() {});
    } else {
      _rubberEnd = pos;
      _checkRubberSelection();
      setState(() {});
    }
  }

  void _onPanEnd() {
    if (_isDragging) {
      _isDragging = false;
      _draggingIndex = null;
      _dragOffset = Offset.zero;
      _dragStartPos = null;
    } else {
      if (_rubberStart != null && _rubberEnd != null) {
        final rect = Rect.fromPoints(_rubberStart!, _rubberEnd!);
        final size = _getCanvasSize();
        if (size > 0) {
          _selectedIndices = {};
          for (int i = 0; i < _points.length; i++) {
            final px = (_points[i].time / _duration) * size;
            final py = 120 - ((_points[i].value - widget.parameterMin) /
                (widget.parameterMax - widget.parameterMin) * 120);
            if (rect.contains(Offset(px, py))) {
              _selectedIndices = {..._selectedIndices, i};
            }
          }
        }
      }
      _rubberStart = null;
      _rubberEnd = null;
      setState(() {});
    }
  }

  void _onRightClick(Offset pos) {
    final hitIndex = _hitTestPoint(pos);
    if (hitIndex != null) {
      _selectedIndices = {hitIndex};
      setState(() {});
      _showContextMenu(pos, BoxConstraints(maxWidth: 500, maxHeight: 500));
    }
  }

  void _showContextMenu(Offset localPos, BoxConstraints constraints) {
    final RenderBox? renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final globalPos = renderBox.localToGlobal(localPos);
    final hitIndex = _hitTestPoint(localPos);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy, globalPos.dx + 1, globalPos.dy + 1),
      color: AppColors.surfaceVariant,
      items: [
        if (hitIndex == null)
          PopupMenuItem(
            value: 'add',
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 8),
                const Text('Add Keypoint', style: TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        if (hitIndex != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.remove_circle_outline, size: 14, color: AppColors.destructive),
                const SizedBox(width: 8),
                const Text('Delete Keypoint', style: TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        if (hitIndex != null)
          PopupMenuItem(
            value: 'delete_all',
            child: Row(
              children: [
                Icon(Icons.delete_sweep_outlined, size: 14, color: AppColors.destructive),
                const SizedBox(width: 8),
                const Text('Delete All Keypoints', style: TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (value == 'add') {
        _addPointAt(localPos);
      } else if (value == 'delete' && hitIndex != null) {
        _deletePoints({hitIndex});
      } else if (value == 'delete_all') {
        widget.onPointsChanged([]);
      }
    });
  }

  void _deletePoints(Set<int> indices) {
    final sorted = indices.toList()..sort((a, b) => b.compareTo(a));
    final updated = List<AutomationPoint>.from(_points);
    for (final i in sorted) {
      if (i >= 0 && i < updated.length) updated.removeAt(i);
    }
    _selectedIndices = {};
    widget.onPointsChanged(updated);
    setState(() {});
  }

  void _checkRubberSelection() {
    if (_rubberStart == null || _rubberEnd == null) return;
    final rect = Rect.fromPoints(_rubberStart!, _rubberEnd!);
    final size = _getCanvasSize();
    if (size <= 0) return;
    _selectedIndices = {};
    for (int i = 0; i < _points.length; i++) {
      final px = (_points[i].time / _duration) * size;
      final py = 120 - ((_points[i].value - widget.parameterMin) /
          (widget.parameterMax - widget.parameterMin) * 120);
      if (rect.contains(Offset(px, py))) {
        _selectedIndices = {..._selectedIndices, i};
      }
    }
  }

  int? _hitTestPoint(Offset pos) {
    const hitRadius = 10.0;
    final size = _getCanvasSize();
    if (size <= 0) return null;
    for (int i = _points.length - 1; i >= 0; i--) {
      final px = (_points[i].time / _duration) * size;
      final py = 120 - ((_points[i].value - widget.parameterMin) /
          (widget.parameterMax - widget.parameterMin) * 120);
      if ((pos - Offset(px, py)).distance <= hitRadius) {
        return i;
      }
    }
    return null;
  }

  double _getCanvasSize() {
    final renderBox = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size.width ?? 200;
  }
}

class _AutomationCurvePainter extends CustomPainter {
  final List<AutomationPoint> points;
  final double duration;
  final Set<int> selectedIndices;
  final double parameterMin;
  final double parameterMax;
  final Color curveColor;
  final int? hoveredIndex;
  final Rect? rubberRect;
  final Offset? dragOffset;
  final int? draggingIndex;

  _AutomationCurvePainter({
    required this.points,
    required this.duration,
    required this.selectedIndices,
    required this.parameterMin,
    required this.parameterMax,
    required this.curveColor,
    this.hoveredIndex,
    this.rubberRect,
    this.dragOffset,
    this.draggingIndex,
  });

  double get _range => parameterMax - parameterMin;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (w <= 0 || h <= 0) return;

    if (points.isEmpty) {
      _drawFlatLine(canvas, size);
      return;
    }

    _drawCurve(canvas, size);
    _drawPoints(canvas, size);
    _drawRubberBand(canvas);
    _drawGridLines(canvas, size);
  }

  void _drawGridLines(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 0.5;

    for (double v = 0; v <= 1.0; v += 0.25) {
      final y = size.height * (1 - v);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  void _drawFlatLine(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = curveColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), paint);

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [curveColor.withValues(alpha: 0.15), curveColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, midY - 1, size.width, size.height - midY));
    canvas.drawRect(Rect.fromLTWH(0, midY, size.width, size.height - midY), fillPaint);
  }

  void _drawCurve(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = curveColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint();

    final path = Path();
    Path? fillPath;

    final sorted = List<AutomationPoint>.from(points)..sort((a, b) => a.time.compareTo(b.time));

    double xToPos(double t) => (t / duration).clamp(0.0, 1.0) * size.width;
    double yToPos(double v) => size.height - ((v - parameterMin) / _range) * size.height;

    if (sorted.isEmpty) return;

    fillPath = Path();
    fillPath.moveTo(xToPos(sorted.first.time), size.height);
    fillPath.lineTo(xToPos(sorted.first.time), yToPos(sorted.first.value));

    for (int i = 0; i < sorted.length; i++) {
      final x = xToPos(sorted[i].time);
      final y = yToPos(sorted[i].value);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = xToPos(sorted[i - 1].time);
        final prevY = yToPos(sorted[i - 1].value);
        final ctrlX = (prevX + x) / 2;
        path.quadraticBezierTo(ctrlX, prevY, x, y);
      }

      if (fillPath != null) {
        fillPath.lineTo(x, y);
      }
    }

    if (fillPath != null && sorted.isNotEmpty) {
      fillPath.lineTo(xToPos(sorted.last.time), size.height);
      fillPath.close();
      fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [curveColor.withValues(alpha: 0.2), curveColor.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, fillPaint);
    }

    canvas.drawPath(path, paint);
  }

  void _drawPoints(Canvas canvas, Size size) {
    double xToPos(double t) => (t / duration).clamp(0.0, 1.0) * size.width;
    double yToPos(double v) => size.height - ((v - parameterMin) / _range) * size.height;

    for (int i = 0; i < points.length; i++) {
      final x = xToPos(points[i].time);
      final y = yToPos(points[i].value);
      final isSelected = selectedIndices.contains(i);
      final isDragged = i == draggingIndex;

      final fillPaint = Paint()
        ..color = isSelected ? Colors.white : curveColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), isDragged ? 6.0 : (isSelected ? 5.0 : 4.0), fillPaint);

      if (isSelected) {
        final borderPaint = Paint()
          ..color = curveColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(Offset(x, y), 7, borderPaint);
      }
    }
  }

  void _drawRubberBand(Canvas canvas) {
    if (rubberRect == null) return;
    final rect = rubberRect!;
    final fillPaint = Paint()
      ..color = curveColor.withValues(alpha: 0.08);
    final borderPaint = Paint()
      ..color = curveColor.withValues(alpha: 0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, fillPaint);
    canvas.drawRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _AutomationCurvePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────
// 2. AUDIO EFFECTS RACK
// ─────────────────────────────────────────────
class AudioEffectsRack extends StatefulWidget {
  final List<Map<String, dynamic>> effectChain;
  final ValueChanged<List<Map<String, dynamic>>> onEffectChainChanged;
  final double? clipDuration;

  const AudioEffectsRack({
    super.key,
    required this.effectChain,
    required this.onEffectChainChanged,
    this.clipDuration,
  });

  @override
  State<AudioEffectsRack> createState() => _AudioEffectsRackState();
}

class _AudioEffectsRackState extends State<AudioEffectsRack> {
  final Set<int> _expandedIndices = {};

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Effects Rack', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            Text('${widget.effectChain.length} effects', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
            const SizedBox(width: 8),
            _buildAddButton(),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.effectChain.isEmpty)
          _buildEmptyState()
        else
          ...List.generate(widget.effectChain.length, (i) => _buildEffectItem(i)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.tune_rounded, size: 28, color: AppColors.textMuted),
          const SizedBox(height: 8),
          Text('No effects added', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text('Tap + to add audio effects', style: TextStyle(fontSize: 10, color: AppColors.textDisabled)),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _showAddEffectMenu(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 12, color: Colors.white),
              const SizedBox(width: 2),
              Text('Add', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEffectMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add Effect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              const Divider(color: AppColors.divider),
              const SizedBox(height: 4),
              ...availableEffects.map((effect) {
                final alreadyAdded = widget.effectChain.any((e) => e['id'] == effect.id);
                return Opacity(
                  opacity: alreadyAdded ? 0.4 : 1.0,
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(effect.icon, size: 16, color: AppColors.primary),
                    ),
                    title: Text(effect.name, style: const TextStyle(fontSize: 13, color: Colors.white)),
                    subtitle: Text('${effect.params.length} params', style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    trailing: alreadyAdded
                        ? const Icon(Icons.check_rounded, size: 16, color: AppColors.secondary)
                        : null,
                    onTap: alreadyAdded
                        ? null
                        : () {
                            Navigator.of(ctx).pop();
                            _addEffect(effect);
                          },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _addEffect(EffectDefinition def) {
    final params = <String, dynamic>{};
    for (final p in def.params) {
      params[p.id] = p.defaultValue;
    }
    final entry = <String, dynamic>{
      'id': def.id,
      'name': def.name,
      'enabled': true,
      'mix': 1.0,
      'params': params,
    };
    final updated = List<Map<String, dynamic>>.from(widget.effectChain)..add(entry);
    widget.onEffectChainChanged(updated);
  }

  Widget _buildEffectItem(int index) {
    final effect = widget.effectChain[index];
    final def = availableEffects.where((e) => e.id == effect['id']).firstOrNull;
    final isExpanded = _expandedIndices.contains(index);
    final isEnabled = effect['enabled'] as bool? ?? true;
    final mix = (effect['mix'] as num?)?.toDouble() ?? 1.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: isEnabled ? AppColors.card : AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isEnabled ? AppColors.border : AppColors.borderSubtle),
        ),
        child: Column(
          children: [
            _buildEffectHeader(index, def, isEnabled, isExpanded, mix),
            if (isExpanded && def != null) _buildEffectParams(index, def, effect),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectHeader(int index, EffectDefinition? def, bool isEnabled, bool isExpanded, double mix) {
    final effect = widget.effectChain[index];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              final updated = List<Map<String, dynamic>>.from(widget.effectChain);
              updated[index] = Map<String, dynamic>.from(updated[index])
                ..['enabled'] = !isEnabled;
              widget.onEffectChainChanged(updated);
            },
            child: Container(
              width: 18, height: 18,
              decoration: BoxDecoration(
                color: isEnabled ? AppColors.primary : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: isEnabled
                  ? const Icon(Icons.power_settings_new_rounded, size: 11, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(def?.icon ?? Icons.tune_rounded, size: 12, color: AppColors.primary),
          ),
          const SizedBox(width: 6),
          Text(
            effect['name'] as String? ?? 'Unknown',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isEnabled ? Colors.white : AppColors.textDisabled,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 50,
            child: Text(
              '${(mix * 100).round()}%',
              style: const TextStyle(fontSize: 9, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedIndices.remove(index);
                } else {
                  _expandedIndices.add(index);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _removeEffect(index),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 14, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectParams(int index, EffectDefinition def, Map<String, dynamic> effect) {
    final params = effect['params'] as Map<String, dynamic>? ?? {};
    final mix = (effect['mix'] as num?)?.toDouble() ?? 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.divider, height: 8),
          for (final param in def.params) _buildParamSlider(index, param, params),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Wet/Dry', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                  ),
                  child: Slider(
                    value: mix,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      final updated = List<Map<String, dynamic>>.from(widget.effectChain);
                      updated[index] = Map<String, dynamic>.from(updated[index])..['mix'] = v;
                      widget.onEffectChainChanged(updated);
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: Text('${(mix * 100).round()}%', style: const TextStyle(fontSize: 8, color: AppColors.textMuted, fontFamily: 'monospace')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParamSlider(int effectIndex, EffectParam param, Map<String, dynamic> params) {
    final value = (params[param.id] as num?)?.toDouble() ?? param.defaultValue;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(param.name, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: value.clamp(param.min, param.max),
                min: param.min,
                max: param.max,
                onChanged: (v) {
                  final updated = List<Map<String, dynamic>>.from(widget.effectChain);
                  final updatedEffect = Map<String, dynamic>.from(updated[effectIndex]);
                  final updatedParams = Map<String, dynamic>.from(updatedEffect['params'] as Map<String, dynamic>? ?? {});
                  updatedParams[param.id] = v;
                  updatedEffect['params'] = updatedParams;
                  updated[effectIndex] = updatedEffect;
                  widget.onEffectChainChanged(updated);
                },
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(value.toStringAsFixed(2), style: const TextStyle(fontSize: 8, color: AppColors.textMuted, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _removeEffect(int index) {
    final updated = List<Map<String, dynamic>>.from(widget.effectChain)..removeAt(index);
    setState(() {
      _expandedIndices.remove(index);
      final temp = <int>{};
      for (final e in _expandedIndices) {
        if (e < index) temp.add(e);
        else if (e > index) temp.add(e - 1);
      }
      _expandedIndices
        ..clear()
        ..addAll(temp);
    });
    widget.onEffectChainChanged(updated);
  }
}

// ─────────────────────────────────────────────
// 3. SIDECHAIN COMPRESSOR
// ─────────────────────────────────────────────
class SidechainCompressor extends StatefulWidget {
  final double? sourceTrack;
  final double threshold;
  final double ratio;
  final double attack;
  final double release;
  final double makeupGain;
  final ValueChanged<double?> onSourceTrackChanged;
  final ValueChanged<double> onThresholdChanged;
  final ValueChanged<double> onRatioChanged;
  final ValueChanged<double> onAttackChanged;
  final ValueChanged<double> onReleaseChanged;
  final ValueChanged<double> onMakeupGainChanged;
  final double gainReduction;

  const SidechainCompressor({
    super.key,
    this.sourceTrack,
    required this.threshold,
    required this.ratio,
    required this.attack,
    required this.release,
    required this.makeupGain,
    required this.onSourceTrackChanged,
    required this.onThresholdChanged,
    required this.onRatioChanged,
    required this.onAttackChanged,
    required this.onReleaseChanged,
    required this.onMakeupGainChanged,
    this.gainReduction = 0.0,
  });

  @override
  State<SidechainCompressor> createState() => _SidechainCompressorState();
}

class _SidechainCompressorState extends State<SidechainCompressor> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.link_rounded, size: 13, color: AppColors.warning),
            ),
            const SizedBox(width: 8),
            const Text('Sidechain Compressor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        _buildSourceSelector(),
        const SizedBox(height: 8),
        _buildSlider('Threshold', widget.threshold, 0, 1, widget.onThresholdChanged, 'dB'),
        _buildSlider('Ratio', widget.ratio, 1, 20, widget.onRatioChanged, ':1'),
        _buildSlider('Attack', widget.attack, 0, 0.1, widget.onAttackChanged, 's'),
        _buildSlider('Release', widget.release, 0, 1, widget.onReleaseChanged, 's'),
        _buildSlider('Makeup', widget.makeupGain, 0, 24, widget.onMakeupGainChanged, 'dB'),
        const SizedBox(height: 8),
        _buildGainReductionMeter(),
      ],
    );
  }

  Widget _buildSourceSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Text('Source:', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<double?>(
                value: widget.sourceTrack,
                isExpanded: true,
                dropdownColor: AppColors.surfaceVariant,
                style: const TextStyle(fontSize: 11, color: Colors.white),
                hint: const Text('None', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (Off)', style: TextStyle(fontSize: 11))),
                  for (int i = 0; i < 4; i++)
                    DropdownMenuItem(
                      value: i.toDouble(),
                      child: Text('Track ${i + 1}', style: TextStyle(fontSize: 11)),
                    ),
                ],
                onChanged: widget.onSourceTrackChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 55,
            child: Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${value.toStringAsFixed(value > 10 ? 0 : 2)}$unit',
              style: const TextStyle(fontSize: 8, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGainReductionMeter() {
    final gr = widget.gainReduction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Gain Reduction', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            const Spacer(),
            Text('-${(gr * 24).round()} dB', style: const TextStyle(fontSize: 9, color: AppColors.destructive, fontFamily: 'monospace')),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: (gr * 100).round(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          gr > 0.7 ? AppColors.warning : AppColors.secondary,
                          gr > 0.7 ? AppColors.destructive : AppColors.warning,
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: (100 - (gr * 100).round()).clamp(0, 100),
                  child: Container(color: Colors.transparent),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// 4. AUDIO MIXER PRO
// ─────────────────────────────────────────────
class AudioMixerPro extends ConsumerStatefulWidget {
  final List<String> trackIds;
  final List<String> trackNames;

  const AudioMixerPro({
    super.key,
    required this.trackIds,
    required this.trackNames,
  });

  @override
  ConsumerState<AudioMixerPro> createState() => _AudioMixerProState();
}

class _AudioMixerProState extends ConsumerState<AudioMixerPro> {
  @override
  void initState() {
    super.initState();
    final mixer = ref.read(audioMixerProvider.notifier);
    for (int i = 0; i < widget.trackIds.length; i++) {
      mixer.addChannel(widget.trackIds[i]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mixerState = ref.watch(audioMixerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Icon(Icons.tune_rounded, size: 13, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Text('Mixer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < widget.trackIds.length; i++)
                  _buildChannelStrip(widget.trackIds[i], widget.trackNames[i], mixerState),
                _buildMasterStrip(mixerState),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChannelStrip(String trackId, String trackName, AudioMixerState mixerState) {
    final ch = mixerState.channels[trackId] ?? const ChannelState();
    final isAudible = mixerState.isAudible(trackId);

    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildStripHeader(trackName, trackId, ch),
          const Divider(color: AppColors.divider, height: 1),
          _buildVuMeter(ch.vuLevel),
          const SizedBox(height: 4),
          _buildVolumeFader(trackId, ch),
          const SizedBox(height: 4),
          _buildPanKnob(trackId, ch),
          const SizedBox(height: 2),
          _buildAutomationSelector(trackId, ch),
        ],
      ),
    );
  }

  Widget _buildStripHeader(String name, String trackId, ChannelState ch) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSmallButton(
                icon: Icons.volume_off_rounded,
                isActive: ch.mute,
                activeColor: AppColors.destructive,
                size: 12,
                onTap: () => ref.read(audioMixerProvider.notifier).toggleMute(trackId),
              ),
              const SizedBox(width: 4),
              _buildSmallButton(
                icon: Icons.headphones_rounded,
                isActive: ch.solo,
                activeColor: AppColors.warning,
                size: 12,
                onTap: () => ref.read(audioMixerProvider.notifier).toggleSolo(trackId),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            name,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20, height: 16,
        decoration: BoxDecoration(
          color: isActive ? activeColor.withValues(alpha: 0.2) : AppColors.background,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isActive ? activeColor : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: size,
          color: isActive ? activeColor : AppColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildVuMeter(double level) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: VUMeter(level: level, isVertical: false),
    );
  }

  Widget _buildVolumeFader(String trackId, ChannelState ch) {
    return GestureDetector(
      onVerticalDragUpdate: (d) {
        final delta = -d.delta.dy / 100;
        final newVol = (ch.volume + delta).clamp(0.0, 4.0);
        ref.read(audioMixerProvider.notifier).setVolume(trackId, newVol);
      },
      child: Container(
        height: 80,
        width: 40,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          children: [
            const SizedBox(height: 2),
            Text(
              ch.volume > 1.0 ? '+${((ch.volume - 1) * 20).round()}' : '${((ch.volume) * 20 - 20).round()}',
              style: const TextStyle(fontSize: 8, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: (ch.volume / 4.0 * 70).clamp(4.0, 70.0),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: ch.volume > 1.0
                            ? [AppColors.destructive, AppColors.warning]
                            : ch.volume > 0.7
                                ? [AppColors.warning, AppColors.secondary]
                                : [AppColors.primary, AppColors.primary.withValues(alpha: 0.5)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            Transform.rotate(
              angle: math.pi,
              child: Icon(Icons.chevron_left_rounded, size: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanKnob(String trackId, ChannelState ch) {
    final panText = ch.pan < -0.3 ? 'L${((-ch.pan * 100).round()).toString().padLeft(2, '0')}'
        : ch.pan > 0.3 ? 'R${((ch.pan * 100).round()).toString().padLeft(2, '0')}'
        : 'C';
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        final newPan = (ch.pan + d.delta.dx / 100).clamp(-1.0, 1.0);
        ref.read(audioMixerProvider.notifier).setPan(trackId, newPan);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.6,
                  colors: [
                    ch.pan.abs() > 0.7 ? AppColors.primary : AppColors.surfaceVariant,
                    AppColors.surfaceVariant,
                  ],
                ),
              ),
              child: Center(
                child: Text(
                  panText,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: ch.pan.abs() > 0.7 ? Colors.white : AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text('PAN', style: TextStyle(fontSize: 7, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomationSelector(String trackId, ChannelState ch) {
    final labels = ['Read', 'Write', 'Touch', 'Latch'];
    final modes = AutomationMode.values;
    final currentIdx = modes.indexOf(ch.automationMode);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () {
              final prev = ((currentIdx - 1) % modes.length).clamp(0, modes.length - 1);
              ref.read(audioMixerProvider.notifier).setAutomationMode(trackId, modes[prev]);
            },
            child: const Icon(Icons.chevron_left_rounded, size: 10, color: AppColors.textMuted),
          ),
          const SizedBox(width: 2),
          Text(
            labels[currentIdx],
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.bold,
              color: ch.automationMode == AutomationMode.write
                  ? AppColors.destructive
                  : ch.automationMode == AutomationMode.touch
                      ? AppColors.warning
                      : ch.automationMode == AutomationMode.latch
                          ? AppColors.primary
                          : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () {
              final next = (currentIdx + 1) % modes.length;
              ref.read(audioMixerProvider.notifier).setAutomationMode(trackId, modes[next]);
            },
            child: const Icon(Icons.chevron_right_rounded, size: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterStrip(AudioMixerState mixerState) {
    return Container(
      width: 72,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
            ),
            child: const Center(
              child: Text(
                'MASTER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          const Divider(color: AppColors.divider, height: 1),
          _buildVuMeter(mixerState.masterVuLevel),
          const SizedBox(height: 4),
          GestureDetector(
            onVerticalDragUpdate: (d) {
              final delta = -d.delta.dy / 100;
              final newVol = (mixerState.masterVolume + delta).clamp(0.0, 4.0);
              ref.read(audioMixerProvider.notifier).setMasterVolume(newVol);
            },
            child: Container(
              height: 80,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 0.5),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  Text(
                    mixerState.masterVolume > 1.0
                        ? '+${((mixerState.masterVolume - 1) * 20).round()}'
                        : '${((mixerState.masterVolume) * 20 - 20).round()}',
                    style: const TextStyle(fontSize: 8, color: AppColors.primary, fontFamily: 'monospace'),
                  ),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: (mixerState.masterVolume / 4.0 * 70).clamp(4.0, 70.0),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF0A84FF), Color(0xFF0070F3)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.rotate(
                    angle: math.pi,
                    child: Icon(Icons.chevron_left_rounded, size: 10, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
