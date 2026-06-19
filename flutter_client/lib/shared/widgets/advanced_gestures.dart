import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SelectionBox extends StatelessWidget {
  final Rect? selectionRect;
  final Color color;
  final double borderWidth;

  const SelectionBox({
    super.key,
    this.selectionRect,
    this.color = AppColors.primary,
    this.borderWidth = 1.5,
  });

  @override
  Widget build(BuildContext context) {
    if (selectionRect == null) return const SizedBox.shrink();
    return Positioned(
      left: selectionRect!.left,
      top: selectionRect!.top,
      width: selectionRect!.width,
      height: selectionRect!.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: color, width: borderWidth),
          color: color.withValues(alpha: 0.1),
        ),
      ),
    );
  }
}

class DragSelectionHandler extends StatefulWidget {
  final Widget child;
  final void Function(Rect selection)? onSelectionEnd;
  final bool enabled;

  const DragSelectionHandler({
    super.key,
    required this.child,
    this.onSelectionEnd,
    this.enabled = true,
  });

  @override
  State<DragSelectionHandler> createState() => _DragSelectionHandlerState();
}

class _DragSelectionHandlerState extends State<DragSelectionHandler> {
  Offset? _dragStart;
  Offset? _dragCurrent;
  Rect? _selectionRect;

  void _onPanStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _dragStart = details.localPosition;
    _dragCurrent = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragStart == null) return;
    _dragCurrent = details.localPosition;
    setState(() {
      _selectionRect = Rect.fromPoints(_dragStart!, _dragCurrent!);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_selectionRect != null && widget.onSelectionEnd != null) {
      widget.onSelectionEnd!(_selectionRect!);
    }
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
      _selectionRect = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: widget.enabled ? _onPanStart : null,
      onPanUpdate: widget.enabled ? _onPanUpdate : null,
      onPanEnd: widget.enabled ? _onPanEnd : null,
      child: Stack(
        children: [
          widget.child,
          if (_selectionRect != null)
            SelectionBox(selectionRect: _selectionRect),
        ],
      ),
    );
  }
}

class SnapGuide extends StatelessWidget {
  final double? position; // in pixels
  final double height;
  final Color color;

  const SnapGuide({
    super.key,
    this.position,
    required this.height,
    this.color = const Color(0xFFF59E0B),
  });

  @override
  Widget build(BuildContext context) {
    if (position == null) return const SizedBox.shrink();
    return Positioned(
      left: position!,
      top: 0,
      height: height,
      child: Container(
        width: 1.5,
        decoration: BoxDecoration(
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
