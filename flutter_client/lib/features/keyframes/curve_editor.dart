import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/timeline_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/easing_curves.dart';

class _PropertyConfig {
  final String label;
  final double min;
  final double max;
  final double defaultValue;
  const _PropertyConfig(this.label, this.min, this.max, this.defaultValue);
}

const _propertyConfigs = {
  'position_x': _PropertyConfig('Position X', -500, 500, 0),
  'position_y': _PropertyConfig('Position Y', -500, 500, 0),
  'scale_x': _PropertyConfig('Scale X', 1, 200, 100),
  'scale_y': _PropertyConfig('Scale Y', 1, 200, 100),
  'rotation': _PropertyConfig('Rotation', -180, 180, 0),
  'opacity': _PropertyConfig('Opacity', 0, 100, 100),
};

const _easingPresets = [
  'linear',
  'ease-in',
  'ease-out',
  'ease-in-out',
  'bounce',
  'elastic',
];

const _easingColors = {
  'linear': Color(0xFF8E8E93),
  'ease-in': Color(0xFFFF9F0A),
  'ease-out': Color(0xFF30D158),
  'ease-in-out': Color(0xFF0A84FF),
  'bounce': Color(0xFFFF453A),
  'elastic': Color(0xFFBF5AF2),
};

const double _valueRulerWidth = 44.0;
const double _timeRulerHeight = 22.0;
const double _keyframeSize = 8.0;
const double _handleRadius = 5.0;
const double _padding = 4.0;

class CurveEditorWidget extends StatefulWidget {
  final List<Keyframe> allKeyframes;
  final double clipDuration;
  final ValueChanged<List<Keyframe>> onChanged;
  final String initialProperty;

  const CurveEditorWidget({
    super.key,
    required this.allKeyframes,
    required this.clipDuration,
    required this.onChanged,
    this.initialProperty = 'position_x',
  });

  @override
  State<CurveEditorWidget> createState() => _CurveEditorWidgetState();
}

class _CurveEditorWidgetState extends State<CurveEditorWidget> {
  late List<Keyframe> _keyframes;
  late String _selectedProperty;
  Set<int> _selectedOriginalIndices = {};
  int? _draggingKeyframeOriginalIndex;
  bool _isDragging = false;
  String? _draggingHandle; // 'in' or 'out'
  Offset? _dragStart;
  double _handleOutX = 0.42;
  double _handleOutY = 0.0;
  double _handleInX = 0.58;
  double _handleInY = 1.0;
  final FocusNode _focusNode = FocusNode();
  bool _showCustomBezierEditor = false;
  double _customBezierX1 = 0.42;
  double _customBezierY1 = 0.0;
  double _customBezierX2 = 0.58;
  double _customBezierY2 = 1.0;

  @override
  void initState() {
    super.initState();
    _keyframes = List.from(widget.allKeyframes);
    _selectedProperty = widget.initialProperty;
  }

  @override
  void didUpdateWidget(covariant CurveEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _keyframes = List.from(widget.allKeyframes);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  _PropertyConfig get _config => _propertyConfigs[_selectedProperty] ?? const _PropertyConfig('Value', -500, 500, 0);

  List<Keyframe> get _propertyKeyframes {
    return _keyframes.where((k) => k.property == _selectedProperty).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  List<int> get _propertyOriginalIndices {
    final result = <int>[];
    for (int i = 0; i < _keyframes.length; i++) {
      if (_keyframes[i].property == _selectedProperty) {
        result.add(i);
      }
    }
    return result;
  }

  int? _originalIndexForPropertyIndex(int propIdx) {
    final indices = _propertyOriginalIndices;
    if (propIdx < 0 || propIdx >= indices.length) return null;
    return indices[propIdx];
  }

  int? _propertyIndexForOriginal(int origIdx) {
    final indices = _propertyOriginalIndices;
    return indices.indexOf(origIdx);
  }

  void _emitChange() {
    widget.onChanged(List.from(_keyframes));
  }

  double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return _config.defaultValue;
  }

  Keyframe _makeKeyframe(double time, double value, {String? easing, int? copyFrom}) {
    if (copyFrom != null) {
      final orig = _keyframes[copyFrom];
      return Keyframe(
        time: time,
        property: _selectedProperty,
        value: value,
        easing: easing ?? orig.easing,
        bezierInX: orig.bezierInX,
        bezierInY: orig.bezierInY,
        bezierOutX: orig.bezierOutX,
        bezierOutY: orig.bezierOutY,
      );
    }
    return Keyframe(
      time: time,
      property: _selectedProperty,
      value: value,
      easing: easing ?? 'linear',
    );
  }

  // --- Easing Helpers ---

  void _getBezierControls(String easing, {double? customOutX, double? customOutY, double? customInX, double? customInY}) {
    if (easing == 'custom' && customOutX != null) {
      _handleOutX = customOutX;
      _handleOutY = customOutY ?? 0.0;
      _handleInX = customInX ?? 0.58;
      _handleInY = customInY ?? 1.0;
      return;
    }
    switch (easing) {
      case 'ease-in':
        _handleOutX = 0.42; _handleOutY = 0.0; _handleInX = 1.0; _handleInY = 1.0;
      case 'ease-out':
        _handleOutX = 0.0; _handleOutY = 0.0; _handleInX = 0.58; _handleInY = 1.0;
      case 'ease-in-out':
        _handleOutX = 0.42; _handleOutY = 0.0; _handleInX = 0.58; _handleInY = 1.0;
      case 'bounce':
        _handleOutX = 0.33; _handleOutY = 0.33; _handleInX = 0.67; _handleInY = 0.67;
      case 'elastic':
        _handleOutX = 0.25; _handleOutY = 0.25; _handleInX = 0.75; _handleInY = 0.75;
      default:
        _handleOutX = 0.33; _handleOutY = 0.33; _handleInX = 0.67; _handleInY = 0.67;
    }
  }

  void _applyEasingPresetToSelected(String easing) {
    if (_selectedOriginalIndices.isEmpty) return;
    setState(() {
      for (final origIdx in _selectedOriginalIndices) {
        _keyframes[origIdx] = Keyframe(
          time: _keyframes[origIdx].time,
          property: _keyframes[origIdx].property,
          value: _keyframes[origIdx].value,
          easing: easing,
        );
      }
    });
    _emitChange();
  }

  // --- Graph Coordinate Helpers ---

  Rect _graphRect(Size size) {
    return Rect.fromLTWH(
      _valueRulerWidth + _padding,
      _padding,
      size.width - _valueRulerWidth - _padding * 2,
      size.height - _timeRulerHeight - _padding * 2,
    );
  }

  double _timeToX(double time, Rect graphRect) {
    final dur = widget.clipDuration > 0 ? widget.clipDuration : 1.0;
    return graphRect.left + (time / dur) * graphRect.width;
  }

  double _xToTime(double x, Rect graphRect) {
    final dur = widget.clipDuration > 0 ? widget.clipDuration : 1.0;
    return ((x - graphRect.left) / graphRect.width) * dur;
  }

  double _valueToY(double value, Rect graphRect) {
    final range = _config.max - _config.min;
    final normalized = (value - _config.min) / range;
    return graphRect.bottom - normalized * graphRect.height;
  }

  double _yToValue(double y, Rect graphRect) {
    final range = _config.max - _config.min;
    final normalized = (graphRect.bottom - y) / graphRect.height;
    return _config.min + normalized * range;
  }

  // --- Hit Testing ---

  int? _hitKeyframe(Offset pos, Rect graphRect) {
    final kfs = _propertyKeyframes;
    for (int i = kfs.length - 1; i >= 0; i--) {
      final kf = kfs[i];
      final dx = pos.dx - _timeToX(kf.time, graphRect);
      final dy = pos.dy - _valueToY(_toDouble(kf.value), graphRect);
      if (dx.abs() < 6 && dy.abs() < 6) return i;
    }
    return null;
  }

  String? _hitHandle(Offset pos, Rect graphRect, int propIdx) {
    final kfs = _propertyKeyframes;
    if (propIdx < 0 || propIdx >= kfs.length) return null;
    final kf = kfs[propIdx];
    final origIdx = _originalIndexForPropertyIndex(propIdx);
    if (origIdx == null) return null;
    if (!_selectedOriginalIndices.contains(origIdx)) return null;

    double hx, hy;

    // Outgoing handle
    if (propIdx < kfs.length - 1) {
      final next = kfs[propIdx + 1];
      final dt = next.time - kf.time;
      final dv = _toDouble(next.value) - _toDouble(kf.value);
      final bx = _keyframes[origIdx].bezierOutX ?? _handleOutX;
      final by = _keyframes[origIdx].bezierOutY ?? _handleOutY;
      hx = _timeToX(kf.time + bx * dt, graphRect);
      hy = _valueToY(_toDouble(kf.value) + by * dv, graphRect);
      if ((pos - Offset(hx, hy)).distance < 8) return 'out';
    }

    // Incoming handle
    if (propIdx > 0) {
      final prev = kfs[propIdx - 1];
      final dt = kf.time - prev.time;
      final dv = _toDouble(kf.value) - _toDouble(prev.value);
      final bx = _keyframes[origIdx].bezierInX ?? _handleInX;
      final by = _keyframes[origIdx].bezierInY ?? _handleInY;
      hx = _timeToX(prev.time + bx * dt, graphRect);
      hy = _valueToY(_toDouble(prev.value) + by * dv, graphRect);
      if ((pos - Offset(hx, hy)).distance < 8) return 'in';
    }

    return null;
  }

  Offset _getHandleScreenPos(int propIdx, String which, Rect graphRect) {
    final kfs = _propertyKeyframes;
    if (propIdx < 0 || propIdx >= kfs.length) return Offset.zero;
    final kf = kfs[propIdx];
    final origIdx = _originalIndexForPropertyIndex(propIdx);
    if (origIdx == null) return Offset.zero;

    if (which == 'out' && propIdx < kfs.length - 1) {
      final next = kfs[propIdx + 1];
      final dt = next.time - kf.time;
      final dv = _toDouble(next.value) - _toDouble(kf.value);
      final bx = _keyframes[origIdx].bezierOutX ?? _handleOutX;
      final by = _keyframes[origIdx].bezierOutY ?? _handleOutY;
      return Offset(
        _timeToX(kf.time + bx * dt, graphRect),
        _valueToY(_toDouble(kf.value) + by * dv, graphRect),
      );
    }

    if (which == 'in' && propIdx > 0) {
      final prev = kfs[propIdx - 1];
      final dt = kf.time - prev.time;
      final dv = _toDouble(kf.value) - _toDouble(prev.value);
      final bx = _keyframes[origIdx].bezierInX ?? _handleInX;
      final by = _keyframes[origIdx].bezierInY ?? _handleInY;
      return Offset(
        _timeToX(prev.time + bx * dt, graphRect),
        _valueToY(_toDouble(prev.value) + by * dv, graphRect),
      );
    }

    return Offset.zero;
  }

  // --- Gesture Handling ---

  void _handleTapDown(TapDownDetails details, Rect graphRect) {
    final pos = details.localPosition;
    final hit = _hitKeyframe(pos, graphRect);
    final isShift = HardwareKeyboard.instance.logicalKeysPressed.any(
      (k) => k == LogicalKeyboardKey.shiftLeft || k == LogicalKeyboardKey.shiftRight,
    );

    setState(() {
      final propIndices = _propertyOriginalIndices;
      if (hit != null) {
        final origIdx = _originalIndexForPropertyIndex(hit);
        if (origIdx != null) {
          if (isShift) {
            if (_selectedOriginalIndices.contains(origIdx)) {
              _selectedOriginalIndices.remove(origIdx);
            } else {
              _selectedOriginalIndices.add(origIdx);
            }
          } else {
            _selectedOriginalIndices = {origIdx};
          }
        }
      } else {
        if (!isShift) _selectedOriginalIndices = {};
      }
    });
  }

  void _handlePanStart(DragStartDetails details, Rect graphRect) {
    final pos = details.localPosition;
    final hit = _hitKeyframe(pos, graphRect);
    final origIdx = hit != null ? _originalIndexForPropertyIndex(hit) : null;

    final handleHit = hit != null ? _hitHandle(pos, graphRect, hit) : null;

    if (handleHit != null && origIdx != null) {
      _draggingHandle = handleHit;
      _draggingKeyframeOriginalIndex = origIdx;
      _isDragging = true;
      _dragStart = pos;
      return;
    }

    if (origIdx != null) {
      if (!_selectedOriginalIndices.contains(origIdx)) {
        _selectedOriginalIndices = {origIdx};
      }
      _draggingKeyframeOriginalIndex = origIdx;
      _isDragging = true;
      _dragStart = pos;
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, Rect graphRect) {
    if (!_isDragging || _draggingKeyframeOriginalIndex == null) return;
    final origIdx = _draggingKeyframeOriginalIndex!;

    if (_draggingHandle != null) {
      _handleHandleDrag(details, graphRect, origIdx);
      return;
    }

    setState(() {
      final time = _xToTime(details.localPosition.dx, graphRect).clamp(0.0, widget.clipDuration);
      final value = _yToValue(details.localPosition.dy, graphRect).clamp(_config.min, _config.max);

      for (final idx in _selectedOriginalIndices) {
        if (idx >= 0 && idx < _keyframes.length) {
          _keyframes[idx] = Keyframe(
            time: idx == origIdx ? time : _keyframes[idx].time,
            property: _selectedProperty,
            value: (idx == origIdx || !_selectedOriginalIndices.contains(origIdx)) ? value : _keyframes[idx].value,
            easing: _keyframes[idx].easing,
            bezierInX: _keyframes[idx].bezierInX,
            bezierInY: _keyframes[idx].bezierInY,
            bezierOutX: _keyframes[idx].bezierOutX,
            bezierOutY: _keyframes[idx].bezierOutY,
          );
        }
      }

      if (_selectedOriginalIndices.contains(origIdx)) {
        _keyframes[origIdx] = Keyframe(
          time: time,
          property: _selectedProperty,
          value: value,
          easing: _keyframes[origIdx].easing,
          bezierInX: _keyframes[origIdx].bezierInX,
          bezierInY: _keyframes[origIdx].bezierInY,
          bezierOutX: _keyframes[origIdx].bezierOutX,
          bezierOutY: _keyframes[origIdx].bezierOutY,
        );
      }
    });
  }

  void _handleHandleDrag(DragUpdateDetails details, Rect graphRect, int origIdx) {
    final propIdx = _propertyIndexForOriginal(origIdx);
    if (propIdx == null) return;
    final kfs = _propertyKeyframes;
    final kf = kfs[propIdx];

    final time = _xToTime(details.localPosition.dx, graphRect).clamp(0.0, widget.clipDuration);
    final value = _yToValue(details.localPosition.dy, graphRect).clamp(_config.min, _config.max);

    if (_draggingHandle == 'out' && propIdx < kfs.length - 1) {
      final next = kfs[propIdx + 1];
      final dt = next.time - kf.time;
      final dv = _toDouble(next.value) - _toDouble(kf.value);
      if (dt == 0 || dv == 0) return;
      final bx = (time - kf.time) / dt;
      final by = (value - _toDouble(kf.value)) / dv;
      setState(() {
        _keyframes[origIdx] = Keyframe(
          time: kf.time,
          property: _selectedProperty,
          value: kf.value,
          easing: 'custom',
          bezierOutX: bx.clamp(0.0, 1.0),
          bezierOutY: by.clamp(0.0, 1.0),
          bezierInX: _keyframes[origIdx].bezierInX,
          bezierInY: _keyframes[origIdx].bezierInY,
        );
      });
    } else if (_draggingHandle == 'in' && propIdx > 0) {
      final prev = kfs[propIdx - 1];
      final dt = kf.time - prev.time;
      final dv = _toDouble(kf.value) - _toDouble(prev.value);
      if (dt == 0 || dv == 0) return;
      final bx = (time - prev.time) / dt;
      final by = (value - _toDouble(prev.value)) / dv;
      setState(() {
        _keyframes[origIdx] = Keyframe(
          time: kf.time,
          property: _selectedProperty,
          value: kf.value,
          easing: 'custom',
          bezierInX: bx.clamp(0.0, 1.0),
          bezierInY: by.clamp(0.0, 1.0),
          bezierOutX: _keyframes[origIdx].bezierOutX,
          bezierOutY: _keyframes[origIdx].bezierOutY,
        );
      });
    }
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isDragging) {
      _isDragging = false;
      _draggingKeyframeOriginalIndex = null;
      _draggingHandle = null;
      _emitChange();
    }
  }

  void _handleSecondaryTap(Offset pos, Rect graphRect) {
    if (!graphRect.contains(pos)) return;
    final time = _xToTime(pos.dx, graphRect).clamp(0.0, widget.clipDuration);
    final value = _yToValue(pos.dy, graphRect).clamp(_config.min, _config.max);

    // Check if tapping near a curve segment between keyframes
    final kfs = _propertyKeyframes;
    final segmentIdx = _findNearestSegment(pos, graphRect);
    final insertTime = segmentIdx != null ? _snapTimeBetween(kfs[segmentIdx!].time, kfs[segmentIdx + 1].time, pos, graphRect) : time;

    setState(() {
      _keyframes.add(_makeKeyframe(insertTime, value));
      _keyframes.sort((a, b) {
        final cmp = a.time.compareTo(b.time);
        if (cmp != 0) return cmp;
        return a.property.compareTo(b.property);
      });
      _selectedOriginalIndices = {_keyframes.length - 1};
    });
    _emitChange();
  }

  int? _findNearestSegment(Offset pos, Rect graphRect) {
    final kfs = _propertyKeyframes;
    if (kfs.length < 2) return null;
    double minDist = double.infinity;
    int? nearest;
    for (int i = 0; i < kfs.length - 1; i++) {
      for (double t = 0; t <= 1.0; t += 0.05) {
        final x = _timeToX(kfs[i].time + t * (kfs[i + 1].time - kfs[i].time), graphRect);
        final val = _toDouble(kfs[i].value) + t * (_toDouble(kfs[i + 1].value) - _toDouble(kfs[i].value));
        final y = _valueToY(val, graphRect);
        final dist = (pos - Offset(x, y)).distance;
        if (dist < minDist) {
          minDist = dist;
          nearest = i;
        }
      }
    }
    if (minDist < 20) return nearest;
    return null;
  }

  double _snapTimeBetween(double t1, double t2, Offset pos, Rect graphRect) {
    final dur = widget.clipDuration > 0 ? widget.clipDuration : 1.0;
    final time = _xToTime(pos.dx, graphRect);
    return time.clamp(t1, t2);
  }

  void _deleteSelected() {
    if (_selectedOriginalIndices.isEmpty) return;
    setState(() {
      final toRemove = _selectedOriginalIndices.toList()..sort((a, b) => b.compareTo(a));
      for (final idx in toRemove) {
        if (idx >= 0 && idx < _keyframes.length) {
          _keyframes.removeAt(idx);
        }
      }
      _selectedOriginalIndices = {};
    });
    _emitChange();
  }

  void _addKeyframeAtPlayhead() {
    final kfs = _propertyKeyframes;
    if (kfs.isEmpty) {
      setState(() {
        _keyframes.add(_makeKeyframe(0, _config.defaultValue));
        _selectedOriginalIndices = {_keyframes.length - 1};
      });
      _emitChange();
      return;
    }
    final lastTime = kfs.last.time;
    final time = (lastTime + 0.5).clamp(0.0, widget.clipDuration);
    final value = kfs.length == 1 ? _toDouble(kfs.first.value) : _toDouble(kfs.last.value);
    setState(() {
      _keyframes.add(_makeKeyframe(time, value));
      _keyframes.sort((a, b) {
        final cmp = a.time.compareTo(b.time);
        if (cmp != 0) return cmp;
        return a.property.compareTo(b.property);
      });
      _selectedOriginalIndices = {_keyframes.length - 1};
    });
    _emitChange();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.delete ||
             event.logicalKey == LogicalKeyboardKey.backspace)) {
          _deleteSelected();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildGraph(),
            if (_selectedOriginalIndices.length == 1) _buildKeyframeInfo(),
            if (_selectedOriginalIndices.isNotEmpty) _buildEasingPresets(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          const Icon(Icons.timeline_rounded, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          const Text('Graph Editor', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          SizedBox(
            width: 120,
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedProperty,
                  isDense: true,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  dropdownColor: AppColors.surfaceVariant,
                  items: _propertyConfigs.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value.label, style: const TextStyle(fontSize: 10)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedProperty = val);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: 24,
            child: TextButton.icon(
              onPressed: _addKeyframeAtPlayhead,
              icon: const Icon(Icons.add, size: 12),
              label: const Text('Add', style: TextStyle(fontSize: 9)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                foregroundColor: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGraph() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 180,
          width: constraints.maxWidth,
          child: ClipRect(
            child: GestureDetector(
              onTapDown: (details) {
                final graphRect = _graphRect(constraints.biggest);
                _handleTapDown(details, graphRect);
              },
              onPanStart: (details) {
                final graphRect = _graphRect(constraints.biggest);
                _handlePanStart(details, graphRect);
              },
              onPanUpdate: (details) {
                final graphRect = _graphRect(constraints.biggest);
                _handlePanUpdate(details, graphRect);
              },
              onPanEnd: _handlePanEnd,
              onSecondaryTapDown: (details) {
                final graphRect = _graphRect(constraints.biggest);
                _handleSecondaryTap(details.localPosition, graphRect);
              },
              child: CustomPaint(
                size: constraints.biggest,
                painter: _GraphPainter(
                  keyframes: _keyframes,
                  property: _selectedProperty,
                  clipDuration: widget.clipDuration,
                  config: _config,
                  selectedOriginalIndices: _selectedOriginalIndices,
                  handleOutX: _handleOutX,
                  handleOutY: _handleOutY,
                  handleInX: _handleInX,
                  handleInY: _handleInY,
                  propertyOriginalIndices: _propertyOriginalIndices,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildKeyframeInfo() {
    final origIdx = _selectedOriginalIndices.first;
    if (origIdx < 0 || origIdx >= _keyframes.length) return const SizedBox.shrink();
    final kf = _keyframes[origIdx];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Text('t=${kf.time.toStringAsFixed(2)}s', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          Text('v=${_toDouble(kf.value).toStringAsFixed(1)}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 12),
          Text('ease=${kf.easing}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                _showCustomBezierEditor = !_showCustomBezierEditor;
                if (_showCustomBezierEditor) {
                  _customBezierX1 = kf.bezierOutX ?? _handleOutX;
                  _customBezierY1 = kf.bezierOutY ?? _handleOutY;
                  _customBezierX2 = kf.bezierInX ?? _handleInX;
                  _customBezierY2 = kf.bezierInY ?? _handleInY;
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('Bezier', style: TextStyle(color: AppColors.primary, fontSize: 9)),
            ),
          ),
          if (_showCustomBezierEditor) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() {
                  _keyframes[origIdx] = Keyframe(
                    time: kf.time,
                    property: kf.property,
                    value: kf.value,
                    easing: 'custom',
                    bezierOutX: _customBezierX1,
                    bezierOutY: _customBezierY1,
                    bezierInX: _customBezierX2,
                    bezierInY: _customBezierY2,
                  );
                  _showCustomBezierEditor = false;
                });
                _emitChange();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('Apply', style: TextStyle(color: AppColors.secondary, fontSize: 9)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEasingPresets() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Easing Presets', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          const SizedBox(height: 4),
          Row(
            children: _easingPresets.map((easing) {
              final color = _easingColors[easing] ?? AppColors.primary;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => _applyEasingPresetToSelected(easing),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      easing.replaceAll('-', ' '),
                      style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          if (_showCustomBezierEditor) ...[
            const SizedBox(height: 6),
            _buildCustomBezierEditor(),
          ],
        ],
      ),
    );
  }

  Widget _buildCustomBezierEditor() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Out:', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              const SizedBox(width: 4),
              _buildBezierSlider('X1', _customBezierX1, (v) => _customBezierX1 = v),
              const SizedBox(width: 8),
              _buildBezierSlider('Y1', _customBezierY1, (v) => _customBezierY1 = v),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('In:', style: TextStyle(color: AppColors.textSecondary, fontSize: 9)),
              const SizedBox(width: 4),
              _buildBezierSlider('X2', _customBezierX2, (v) => _customBezierX2 = v),
              const SizedBox(width: 8),
              _buildBezierSlider('Y2', _customBezierY2, (v) => _customBezierY2 = v),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBezierSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 8)),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceVariant,
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: value,
              min: 0.0,
              max: 1.0,
              onChanged: (v) => setState(() => onChanged(v)),
            ),
          ),
        ),
        SizedBox(
          width: 24,
          child: Text(value.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 8)),
        ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<Keyframe> keyframes;
  final String property;
  final double clipDuration;
  final _PropertyConfig config;
  final Set<int> selectedOriginalIndices;
  final double handleOutX;
  final double handleOutY;
  final double handleInX;
  final double handleInY;
  final List<int> propertyOriginalIndices;

  _GraphPainter({
    required this.keyframes,
    required this.property,
    required this.clipDuration,
    required this.config,
    required this.selectedOriginalIndices,
    required this.handleOutX,
    required this.handleOutY,
    required this.handleInX,
    required this.handleInY,
    required this.propertyOriginalIndices,
  });

  List<Keyframe> get _propertyKeyframes {
    return keyframes.where((k) => k.property == property).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return config.defaultValue;
  }

  Rect _graphRect(Size size) {
    return Rect.fromLTWH(
      _valueRulerWidth + _padding,
      _padding,
      size.width - _valueRulerWidth - _padding * 2,
      size.height - _timeRulerHeight - _padding * 2,
    );
  }

  double _timeToX(double time, Rect gr) {
    final dur = clipDuration > 0 ? clipDuration : 1.0;
    return gr.left + (time / dur) * gr.width;
  }

  double _valueToY(double value, Rect gr) {
    final range = config.max - config.min;
    return gr.bottom - ((value - config.min) / range) * gr.height;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gr = _graphRect(size);
    final kfs = _propertyKeyframes;
    final dur = clipDuration > 0 ? clipDuration : 1.0;

    // Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF1A1A1E));

    // ─── Grid ───
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;

    // Vertical grid lines (every 1 second)
    for (double t = 0; t <= dur; t += 1.0) {
      final x = _timeToX(t, gr);
      canvas.drawLine(Offset(x, gr.top), Offset(x, gr.bottom), gridPaint);
    }

    // Sub-second vertical lines (every 0.5s)
    final subGridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.5;
    for (double t = 0.5; t <= dur; t += 1.0) {
      final x = _timeToX(t, gr);
      canvas.drawLine(Offset(x, gr.top), Offset(x, gr.bottom), subGridPaint);
    }

    // Horizontal grid lines
    final range = config.max - config.min;
    final ySteps = _computeYSteps(range);
    for (double v = config.min; v <= config.max; v += ySteps) {
      final y = _valueToY(v, gr);
      canvas.drawLine(Offset(gr.left, y), Offset(gr.right, y), gridPaint);
    }

    // ─── Curves between keyframes ───
    if (kfs.length >= 2) {
      final curvePaint = Paint()
        ..color = AppColors.primary.withValues(alpha: 0.7)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < kfs.length - 1; i++) {
        final a = kfs[i];
        final b = kfs[i + 1];
        final aVal = _toDouble(a.value);
        final bVal = _toDouble(b.value);
        final bezier = easingToBezier(a.easing);

        final outX = a.bezierOutX ?? (a.easing == 'custom' ? 0.5 : bezier.x1);
        final outY = a.bezierOutY ?? (a.easing == 'custom' ? 0.5 : bezier.y1);
        final inX = a.bezierInX ?? (a.easing == 'custom' ? 0.5 : bezier.x2);
        final inY = a.bezierInY ?? (a.easing == 'custom' ? 0.5 : bezier.y2);

        // Draw cubic bezier directly between keyframes
        final path = Path();
        final steps = 40;
        for (int s = 0; s <= steps; s++) {
          final t = s / steps;
          final bx = _cubicBezierX(t, outX, inX);
          final by = _cubicBezierY(t, outY, inY);
          final time = a.time + bx * (b.time - a.time);
          final value = aVal + by * (bVal - aVal);
          final px = _timeToX(time, gr);
          final py = _valueToY(value, gr);
          if (s == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        canvas.drawPath(path, curvePaint);

        // Second curve for non-linear easings (e.g., bounce, elastic)
        if (a.easing == 'bounce' || a.easing == 'elastic') {
          final overlayPaint = Paint()
            ..color = _easingColor(a.easing).withValues(alpha: 0.4)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke;

          final overlayPath = Path();
          for (int s = 0; s <= steps; s++) {
            final t = s / steps;
            final eased = evaluateWithEasing(t, a.easing);
            final time = a.time + t * (b.time - a.time);
            final value = aVal + eased * (bVal - aVal);
            final px = _timeToX(time, gr);
            final py = _valueToY(value, gr);
            if (s == 0) overlayPath.moveTo(px, py);
            else overlayPath.lineTo(px, py);
          }
          canvas.drawPath(overlayPath, overlayPaint);
        }
      }
    }

    // ─── Easing Handles for selected keyframe ───
    if (selectedOriginalIndices.length == 1) {
      final origIdx = selectedOriginalIndices.first;
      final propIdx = propertyOriginalIndices.indexOf(origIdx);
      if (propIdx >= 0 && propIdx < kfs.length) {
        final kf = kfs[propIdx];
        if (selectedOriginalIndices.contains(origIdx)) {
          final kfX = _timeToX(kf.time, gr);
          final kfY = _valueToY(_toDouble(kf.value), gr);

          // Outgoing handle
          if (propIdx < kfs.length - 1) {
            final next = kfs[propIdx + 1];
            final dt = next.time - kf.time;
            final dv = _toDouble(next.value) - _toDouble(kf.value);
            final bezier = easingToBezier(kf.easing);
            final bx = kf.bezierOutX ?? (kf.easing == 'custom' ? 0.5 : bezier.x1);
            final by = kf.bezierOutY ?? (kf.easing == 'custom' ? 0.5 : bezier.y1);
            final hx = _timeToX(kf.time + bx * dt, gr);
            final hy = _valueToY(_toDouble(kf.value) + by * dv, gr);

            final handlePaint = Paint()
              ..color = Colors.white.withValues(alpha: 0.5)
              ..strokeWidth = 1.0;
            canvas.drawLine(Offset(kfX, kfY), Offset(hx, hy), handlePaint);
            canvas.drawCircle(Offset(hx, hy), _handleRadius, Paint()..color = Colors.white.withValues(alpha: 0.4));
            canvas.drawCircle(Offset(hx, hy), _handleRadius - 1, Paint()..color = const Color(0xFF333333));
          }

          // Incoming handle
          if (propIdx > 0) {
            final prev = kfs[propIdx - 1];
            final dt = kf.time - prev.time;
            final dv = _toDouble(kf.value) - _toDouble(prev.value);
            final bezier = easingToBezier(prev.easing);
            final bx = kf.bezierInX ?? (prev.easing == 'custom' ? 0.5 : bezier.x2);
            final by = kf.bezierInY ?? (prev.easing == 'custom' ? 0.5 : bezier.y2);
            final hx = _timeToX(prev.time + bx * dt, gr);
            final hy = _valueToY(_toDouble(prev.value) + by * dv, gr);

            final handlePaint = Paint()
              ..color = Colors.white.withValues(alpha: 0.5)
              ..strokeWidth = 1.0;
            canvas.drawLine(Offset(kfX, kfY), Offset(hx, hy), handlePaint);
            canvas.drawCircle(Offset(hx, hy), _handleRadius, Paint()..color = Colors.white.withValues(alpha: 0.4));
            canvas.drawCircle(Offset(hx, hy), _handleRadius - 1, Paint()..color = const Color(0xFF333333));
          }
        }
      }
    }

    // ─── Keyframe Diamonds ───
    for (int i = 0; i < kfs.length; i++) {
      final kf = kfs[i];
      final origIdx = _findOriginalIndex(kf);
      final isSelected = origIdx != null && selectedOriginalIndices.contains(origIdx);
      final x = _timeToX(kf.time, gr);
      final y = _valueToY(_toDouble(kf.value), gr);

      final color = isSelected ? AppColors.primary : const Color(0xFFBF5AF2);
      final fillColor = isSelected ? AppColors.primary : const Color(0xFF2C2C30);
      final borderColor = isSelected ? AppColors.primary : const Color(0xFF8E8E93);

      if (isSelected) {
        // Glow
        canvas.drawCircle(Offset(x, y), _keyframeSize + 4, Paint()
          ..color = AppColors.primary.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      }

      // Diamond
      final diamond = Path()
        ..moveTo(x, y - _keyframeSize)
        ..lineTo(x + _keyframeSize * 0.7, y)
        ..lineTo(x, y + _keyframeSize)
        ..lineTo(x - _keyframeSize * 0.7, y)
        ..close();

      canvas.drawPath(diamond, Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill);
      canvas.drawPath(diamond, Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    // ─── Value Ruler ───
    _drawValueRuler(canvas, size, gr);

    // ─── Time Ruler ───
    _drawTimeRuler(canvas, size, gr, dur);
  }

  void _drawValueRuler(Canvas canvas, Size size, Rect gr) {
    final range = config.max - config.min;
    final ySteps = _computeYSteps(range);

    for (double v = config.min; v <= config.max + 0.001; v += ySteps) {
      final y = _valueToY(v, gr);
      if (y < gr.top - 10 || y > gr.bottom + 10) continue;

      // Tick mark
      canvas.drawLine(
        Offset(gr.left - 3, y),
        Offset(gr.left, y),
        Paint()..color = Colors.white.withValues(alpha: 0.3)..strokeWidth = 0.5,
      );

      // Label
      final label = _formatValue(v);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: _valueRulerWidth - 4);
      textPainter.paint(canvas, Offset(_valueRulerWidth - textPainter.width - 4, y - textPainter.height / 2));
    }
  }

  void _drawTimeRuler(Canvas canvas, Size size, Rect gr, double dur) {
    final rulerY = gr.bottom;
    final rulerH = _timeRulerHeight;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(gr.left, rulerY, gr.width, rulerH),
      Paint()..color = const Color(0xFF151518),
    );

    // Tick marks and labels
    for (double t = 0; t <= dur + 0.001; t += 1.0) {
      final x = _timeToX(t, gr);

      canvas.drawLine(
        Offset(x, rulerY),
        Offset(x, rulerY + 6),
        Paint()..color = Colors.white.withValues(alpha: 0.4)..strokeWidth = 0.5,
      );

      // Sub-ticks
      if (t < dur) {
        for (double sub = 0.25; sub < 1.0; sub += 0.25) {
          final sx = _timeToX(t + sub, gr);
          canvas.drawLine(
            Offset(sx, rulerY),
            Offset(sx, rulerY + 3),
            Paint()..color = Colors.white.withValues(alpha: 0.15)..strokeWidth = 0.5,
          );
        }
      }

      final label = '${t.toInt()}s';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, rulerY + 8));
    }
  }

  String _formatValue(double v) {
    if (v.abs() >= 100) return v.toInt().toString();
    if (v.abs() >= 10) return v.toStringAsFixed(1);
    return v.toStringAsFixed(2);
  }

  double _computeYSteps(double range) {
    if (range <= 2) return 0.25;
    if (range <= 10) return 1.0;
    if (range <= 50) return 5.0;
    if (range <= 100) return 10.0;
    if (range <= 200) return 25.0;
    if (range <= 500) return 50.0;
    if (range <= 1000) return 100.0;
    return 250.0;
  }

  int? _findOriginalIndex(Keyframe kf) {
    for (int i = 0; i < keyframes.length; i++) {
      if (keyframes[i] == kf) return i;
    }
    // Fallback: match by position and value
    for (int i = 0; i < keyframes.length; i++) {
      if (keyframes[i].time == kf.time &&
          keyframes[i].property == kf.property &&
          keyframes[i].value == kf.value) {
        return i;
      }
    }
    return null;
  }

  Color _easingColor(String easing) {
    return _easingColors[easing] ?? AppColors.primary;
  }

  double _cubicBezierX(double t, double x1, double x2) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * x1 +
        3.0 * (1.0 - t) * t * t * x2 +
        t * t * t;
  }

  double _cubicBezierY(double t, double y1, double y2) {
    return 3.0 * (1.0 - t) * (1.0 - t) * t * y1 +
        3.0 * (1.0 - t) * t * t * y2 +
        t * t * t;
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.keyframes != keyframes ||
        oldDelegate.property != property ||
        oldDelegate.clipDuration != clipDuration ||
        oldDelegate.selectedOriginalIndices != selectedOriginalIndices ||
        oldDelegate.config != config;
  }
}
