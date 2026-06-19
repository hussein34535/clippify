import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

class ShortcutAction {
  final String name;
  final String description;
  final LogicalKeyboardKey key;
  final bool ctrl;
  final bool shift;
  final bool alt;

  const ShortcutAction({
    required this.name,
    required this.description,
    required this.key,
    this.ctrl = false,
    this.shift = false,
    this.alt = false,
  });

  String get label {
    final parts = <String>[];
    if (ctrl) parts.add('Ctrl');
    if (shift) parts.add('Shift');
    if (alt) parts.add('Alt');
    parts.add(_keyLabel(key));
    return parts.join(' + ');
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.delete) return 'Delete';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.home) return 'Home';
    if (key == LogicalKeyboardKey.end) return 'End';
    if (key == LogicalKeyboardKey.keyZ) return 'Z';
    if (key == LogicalKeyboardKey.keyY) return 'Y';
    if (key == LogicalKeyboardKey.keyC) return 'C';
    if (key == LogicalKeyboardKey.keyV) return 'V';
    if (key == LogicalKeyboardKey.keyX) return 'X';
    if (key == LogicalKeyboardKey.keyS) return 'S';
    if (key == LogicalKeyboardKey.keyT) return 'T';
    if (key == LogicalKeyboardKey.keyM) return 'M';
    if (key == LogicalKeyboardKey.keyF) return 'F';
    if (key == LogicalKeyboardKey.keyA) return 'A';
    if (key == LogicalKeyboardKey.keyD) return 'D';
    if (key == LogicalKeyboardKey.minus) return '-';
    if (key == LogicalKeyboardKey.equal) return '+';
    if (key == LogicalKeyboardKey.digit0) return '0';
    return key.keyLabel;
  }
}

class KeyboardShortcutsWidget extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPlayPause;
  final VoidCallback? onForward;
  final VoidCallback? onRewind;
  final VoidCallback? onGoStart;
  final VoidCallback? onGoEnd;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onDelete;
  final VoidCallback? onSplit;
  final VoidCallback? onAddText;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomReset;
  final VoidCallback? onFullscreen;

  const KeyboardShortcutsWidget({
    super.key,
    required this.child,
    this.onPlayPause,
    this.onForward,
    this.onRewind,
    this.onGoStart,
    this.onGoEnd,
    this.onUndo,
    this.onRedo,
    this.onDelete,
    this.onSplit,
    this.onAddText,
    this.onZoomIn,
    this.onZoomOut,
    this.onZoomReset,
    this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        if (onPlayPause != null)
          SingleActivator(LogicalKeyboardKey.space): onPlayPause!,
        if (onForward != null)
          SingleActivator(LogicalKeyboardKey.arrowRight): onForward!,
        if (onRewind != null)
          SingleActivator(LogicalKeyboardKey.arrowLeft): onRewind!,
        if (onGoStart != null)
          SingleActivator(LogicalKeyboardKey.home): onGoStart!,
        if (onGoEnd != null)
          SingleActivator(LogicalKeyboardKey.end): onGoEnd!,
        if (onUndo != null)
          SingleActivator(LogicalKeyboardKey.keyZ, control: true): onUndo!,
        if (onRedo != null)
          SingleActivator(LogicalKeyboardKey.keyY, control: true): onRedo!,
        if (onDelete != null)
          SingleActivator(LogicalKeyboardKey.delete): onDelete!,
        if (onDelete != null)
          SingleActivator(LogicalKeyboardKey.backspace): onDelete!,
        if (onSplit != null)
          SingleActivator(LogicalKeyboardKey.keyS, control: true): onSplit!,
        if (onAddText != null)
          SingleActivator(LogicalKeyboardKey.keyT): onAddText!,
        if (onZoomIn != null)
          SingleActivator(LogicalKeyboardKey.equal, control: true): onZoomIn!,
        if (onZoomOut != null)
          SingleActivator(LogicalKeyboardKey.minus, control: true): onZoomOut!,
        if (onZoomReset != null)
          SingleActivator(LogicalKeyboardKey.digit0, control: true): onZoomReset!,
        if (onFullscreen != null)
          SingleActivator(LogicalKeyboardKey.keyF): onFullscreen!,
      },
      child: Focus(
        autofocus: true,
        child: child,
      ),
    );
  }
}

class ShortcutsDialog extends StatelessWidget {
  const ShortcutsDialog({super.key});

  static const List<ShortcutAction> _items = [
    ShortcutAction(name: 'play_pause', description: 'تشغيل / إيقاف', key: LogicalKeyboardKey.space),
    ShortcutAction(name: 'forward', description: 'تقديم 5 ثوان', key: LogicalKeyboardKey.arrowRight),
    ShortcutAction(name: 'rewind', description: 'إرجاع 5 ثوان', key: LogicalKeyboardKey.arrowLeft),
    ShortcutAction(name: 'go_start', description: 'البداية', key: LogicalKeyboardKey.home),
    ShortcutAction(name: 'go_end', description: 'النهاية', key: LogicalKeyboardKey.end),
    ShortcutAction(name: 'undo', description: 'تراجع', key: LogicalKeyboardKey.keyZ, ctrl: true),
    ShortcutAction(name: 'redo', description: 'إعادة', key: LogicalKeyboardKey.keyY, ctrl: true),
    ShortcutAction(name: 'delete', description: 'حذف', key: LogicalKeyboardKey.delete),
    ShortcutAction(name: 'split', description: 'قص عند المؤشر', key: LogicalKeyboardKey.keyS, ctrl: true),
    ShortcutAction(name: 'zoom_in', description: 'تكبير', key: LogicalKeyboardKey.equal, ctrl: true),
    ShortcutAction(name: 'zoom_out', description: 'تصغير', key: LogicalKeyboardKey.minus, ctrl: true),
    ShortcutAction(name: 'fullscreen', description: 'شاشة كاملة', key: LogicalKeyboardKey.keyF),
    ShortcutAction(name: 'add_text', description: 'إضافة نص', key: LogicalKeyboardKey.keyT),
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'اختصارات لوحة المفاتيح',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(color: AppColors.divider),
                itemBuilder: (context, index) {
                  final action = _items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            action.description,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Text(
                            action.label,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
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
        ),
      ),
    );
  }
}
