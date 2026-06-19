import 'package:flutter/material.dart';
import '../../../core/models/timeline_models.dart';

class TextClipItemWidget extends StatelessWidget {
  final TextClip clip;
  final bool isSelected;
  final double zoomLevel;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final ValueChanged<double> onMove;
  final ValueChanged<double> onResizeLeft;
  final ValueChanged<double> onResizeRight;
  final VoidCallback? onContextMenu;

  const TextClipItemWidget({
    super.key,
    required this.clip,
    required this.isSelected,
    required this.zoomLevel,
    required this.onSelect,
    required this.onEdit,
    required this.onMove,
    required this.onResizeLeft,
    required this.onResizeRight,
    this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final duration = clip.endTime - clip.startTime;
    final width = duration * zoomLevel;

    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onEdit,
      onSecondaryTap: onContextMenu,
      child: Container(
        width: width,
        height: 50,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEC4899), Color(0xFFBE185D)],
          ),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.text_fields, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        const Text(
                          'نص',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${duration.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      clip.text,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontFamily: clip.fontFamily,
                        fontWeight: clip.isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: clip.isItalic ? FontStyle.italic : FontStyle.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            if (isSelected) ...[
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final deltaSec = details.delta.dx / zoomLevel;
                      onResizeLeft(deltaSec);
                    },
                    child: Container(
                      width: 6,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      final deltaSec = details.delta.dx / zoomLevel;
                      onResizeRight(deltaSec);
                    },
                    child: Container(
                      width: 6,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
