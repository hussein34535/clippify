import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../features/command_palette/registry.dart';

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

/// يلفّ الشاشة باختصارات لوحة المفاتيح.
///
/// Ctrl+K مُسجَّل داخلياً ويفتح لوحة الأوامر (command palette) بالأوامر
/// الافتراضية تلقائياً — لا حاجة لأي ربط إضافي من المستهلك. لتخصيصها،
/// مرّر سطراً واحداً:
/// ```dart
/// KeyboardShortcutsWidget(
///   onCommandPalette: () => showCommandPalette(context, myCommands),
///   ...
/// )
/// ```
class KeyboardShortcutsWidget extends ConsumerWidget {
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
  final VoidCallback? onSave;
  final VoidCallback? onSaveAs;
  final VoidCallback? onSettings;
  final VoidCallback? onOpen;
  final VoidCallback? onNew;
  final VoidCallback? onExport;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onSelectAll;
  final VoidCallback? onShowShortcuts;

  /// اختياري: يتجاوز السلوك الافتراضي لـ Ctrl+K.
  final VoidCallback? onCommandPalette;

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
    this.onSave,
    this.onSaveAs,
    this.onSettings,
    this.onOpen,
    this.onNew,
    this.onExport,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onSelectAll,
    this.onShowShortcuts,
    this.onCommandPalette,
  });

  /// هل التركيز الحالي داخل حقل نص؟ — الاختصارات تُكتم أثناء الكتابة حتى
  /// لا يقصّ المستخدم مقطعًا وهو يكتب اسم ملف أو تعليمات.
  static bool isEditingNow() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null ||
        ctx.widget is EditableText;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openPalette() {
      if (onCommandPalette != null) {
        onCommandPalette!();
      } else {
        showCommandPalette(context, defaultCommands(ref, context));
      }
    }

    // المالك الوحيد للاختصارات — كل ردّ يُكتم أثناء الكتابة (عدا اللوحة).
    void fire(VoidCallback cb) {
      if (!isEditingNow()) cb();
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            openPalette,
        if (onPlayPause != null)
          SingleActivator(LogicalKeyboardKey.space): () => fire(onPlayPause!),
        if (onForward != null)
          SingleActivator(LogicalKeyboardKey.arrowRight): () => fire(onForward!),
        if (onRewind != null)
          SingleActivator(LogicalKeyboardKey.arrowLeft): () => fire(onRewind!),
        if (onGoStart != null)
          SingleActivator(LogicalKeyboardKey.home): () => fire(onGoStart!),
        if (onGoEnd != null)
          SingleActivator(LogicalKeyboardKey.end): () => fire(onGoEnd!),
        if (onUndo != null)
          SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => fire(onUndo!),
        if (onRedo != null)
          SingleActivator(LogicalKeyboardKey.keyY, control: true): () => fire(onRedo!),
        if (onDelete != null)
          SingleActivator(LogicalKeyboardKey.delete): () => fire(onDelete!),
        if (onDelete != null)
          SingleActivator(LogicalKeyboardKey.backspace): () => fire(onDelete!),
        if (onSplit != null)
          const SingleActivator(LogicalKeyboardKey.keyS): () => fire(onSplit!),
        if (onSave != null)
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => fire(onSave!),
        if (onSaveAs != null)
          const SingleActivator(LogicalKeyboardKey.keyS, control: true, shift: true): () => fire(onSaveAs!),
        if (onSettings != null)
          const SingleActivator(LogicalKeyboardKey.comma, control: true): () => fire(onSettings!),
        if (onExport != null)
          const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => fire(onExport!),
        if (onOpen != null)
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => fire(onOpen!),
        if (onNew != null)
          const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => fire(onNew!),
        if (onCopy != null)
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => fire(onCopy!),
        if (onCut != null)
          const SingleActivator(LogicalKeyboardKey.keyX, control: true): () => fire(onCut!),
        if (onPaste != null)
          const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => fire(onPaste!),
        if (onSelectAll != null)
          const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => fire(onSelectAll!),
        if (onShowShortcuts != null)
          const SingleActivator(LogicalKeyboardKey.f1): () => fire(onShowShortcuts!),
        if (onAddText != null)
          SingleActivator(LogicalKeyboardKey.keyT): () => fire(onAddText!),
        if (onZoomIn != null)
          SingleActivator(LogicalKeyboardKey.equal, control: true): () => fire(onZoomIn!),
        if (onZoomOut != null)
          SingleActivator(LogicalKeyboardKey.minus, control: true): () => fire(onZoomOut!),
        if (onZoomReset != null)
          SingleActivator(LogicalKeyboardKey.digit0, control: true): () => fire(onZoomReset!),
        if (onFullscreen != null)
          SingleActivator(LogicalKeyboardKey.keyF): () => fire(onFullscreen!),
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
    ShortcutAction(name: 'command_palette', description: 'لوحة الأوامر', key: LogicalKeyboardKey.keyK, ctrl: true),
    ShortcutAction(name: 'delete', description: 'حذف', key: LogicalKeyboardKey.delete),
    ShortcutAction(name: 'split', description: 'قص عند المؤشر', key: LogicalKeyboardKey.keyS),
    ShortcutAction(name: 'save', description: 'حفظ المشروع', key: LogicalKeyboardKey.keyS, ctrl: true),
    ShortcutAction(name: 'save_as', description: 'حفظ باسم', key: LogicalKeyboardKey.keyS, ctrl: true, shift: true),
    ShortcutAction(name: 'export', description: 'تصدير', key: LogicalKeyboardKey.keyE, ctrl: true),
    ShortcutAction(name: 'open', description: 'فتح مشروع', key: LogicalKeyboardKey.keyO, ctrl: true),
    ShortcutAction(name: 'new', description: 'مشروع جديد', key: LogicalKeyboardKey.keyN, ctrl: true),
    ShortcutAction(name: 'copy', description: 'نسخ', key: LogicalKeyboardKey.keyC, ctrl: true),
    ShortcutAction(name: 'cut', description: 'قص', key: LogicalKeyboardKey.keyX, ctrl: true),
    ShortcutAction(name: 'paste', description: 'لصق', key: LogicalKeyboardKey.keyV, ctrl: true),
    ShortcutAction(name: 'select_all', description: 'تحديد الكل', key: LogicalKeyboardKey.keyA, ctrl: true),
    ShortcutAction(name: 'help', description: 'هذه القائمة', key: LogicalKeyboardKey.f1),
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
        // عرض متكيف — 500 الثابتة تفيض في نوافذ الاختبار/الشاشات الضيقة.
        width: (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 500.0),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.keyboard, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'اختصارات لوحة المفاتيح',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ),
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
