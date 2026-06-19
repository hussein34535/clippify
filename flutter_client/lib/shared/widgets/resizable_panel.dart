import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum ResizeSide { left, right, bottom }

class ResizablePanel extends StatefulWidget {
  final Widget child;
  final double initialSize;
  final double minSize;
  final double maxSize;
  final ResizeSide side;
  final ValueChanged<double> onResize;

  const ResizablePanel({
    super.key,
    required this.child,
    required this.initialSize,
    this.minSize = 180,
    this.maxSize = 600,
    this.side = ResizeSide.right,
    required this.onResize,
  });

  @override
  State<ResizablePanel> createState() => _ResizablePanelState();
}

class _ResizablePanelState extends State<ResizablePanel> {
  late double _size;

  @override
  void initState() {
    super.initState();
    _size = widget.initialSize;
  }

  @override
  void didUpdateWidget(covariant ResizablePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSize != widget.initialSize) {
      _size = widget.initialSize;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.side == ResizeSide.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isHorizontal = !isVertical;

        final maxAvail = isHorizontal
            ? (constraints.maxWidth.isFinite ? constraints.maxWidth : widget.maxSize)
            : (constraints.maxHeight.isFinite ? constraints.maxHeight : widget.maxSize);
        final hi = maxAvail < widget.minSize ? widget.minSize + 20 : maxAvail;
        final effectiveSize = _size.clamp(widget.minSize, hi);
        if (isHorizontal) {
          return SizedBox(
            width: effectiveSize,
            child: Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.side == ResizeSide.right) _buildHandle(isVertical),
                Expanded(child: widget.child),
                if (widget.side == ResizeSide.left) _buildHandle(isVertical),
              ],
            ),
          );
        } else {
          return SizedBox(
            height: effectiveSize,
            child: Column(
              children: [
                if (widget.side == ResizeSide.bottom) _buildHandle(isVertical),
                Expanded(child: widget.child),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildHandle(bool isVertical) {
    return _ResizeHandle(
      isVertical: isVertical,
      side: widget.side,
      onDragUpdate: (details) {
        if (isVertical) {
          final delta = widget.side == ResizeSide.bottom
              ? -details.delta.dy
              : details.delta.dy;
          setState(() {
            _size = (_size + delta).clamp(widget.minSize, widget.maxSize);
          });
          widget.onResize(_size);
        } else {
          final delta = widget.side == ResizeSide.right
              ? -details.delta.dx
              : details.delta.dx;
          setState(() {
            _size = (_size + delta).clamp(widget.minSize, widget.maxSize);
          });
          widget.onResize(_size);
        }
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Resize Handle – Apple-style thin divider
// ─────────────────────────────────────────────
class _ResizeHandle extends StatefulWidget {
  final bool isVertical;
  final ResizeSide side;
  final ValueChanged<DragUpdateDetails> onDragUpdate;

  const _ResizeHandle({
    required this.isVertical,
    required this.side,
    required this.onDragUpdate,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _isHovered  = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.isVertical;
    final active     = _isHovered || _isDragging;

    final lineColor = active
        ? AppColors.primary
        : AppColors.borderSubtle;
    final bgColor = active
        ? AppColors.primary.withValues(alpha: 0.06)
        : Colors.transparent;

    return MouseRegion(
      cursor: isVertical
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit:  (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onHorizontalDragStart:  isVertical ? null : (_) => setState(() => _isDragging = true),
        onHorizontalDragEnd:    isVertical ? null : (_) => setState(() => _isDragging = false),
        onHorizontalDragCancel: isVertical ? null : ()  => setState(() => _isDragging = false),
        onHorizontalDragUpdate: isVertical ? null : widget.onDragUpdate,

        onVerticalDragStart:  isVertical ? (_) => setState(() => _isDragging = true) : null,
        onVerticalDragEnd:    isVertical ? (_) => setState(() => _isDragging = false) : null,
        onVerticalDragCancel: isVertical ? ()  => setState(() => _isDragging = false) : null,
        onVerticalDragUpdate: isVertical ? widget.onDragUpdate : null,

        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // Fixed dimensions – no infinity
          width:  isVertical ? double.infinity : 5,
          height: isVertical ? 5 : double.infinity,
          color: bgColor,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width:  isVertical ? 36.0 : 1.0,  // pill on vertical, thin line on horizontal
            height: isVertical ? 1.0  : double.infinity,
            decoration: BoxDecoration(
              color: lineColor,
              borderRadius: isVertical
                  ? BorderRadius.circular(1)
                  : null,
              boxShadow: active
                  ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.4), blurRadius: 4)]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
