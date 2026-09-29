import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../layout/widgets/export_modal.dart';
import '../layout/widgets/settings_modal.dart';
import '../timeline/providers/timeline_provider.dart';
import '../../shared/providers/toast_provider.dart';
import 'palette.dart';

/// أمر واحد داخل لوحة الأوامر (Ctrl+K).
///
/// [action] يستقبل سياق الصفحة الأصلي (وليس سياق الـ overlay) لضمان إمكانية
/// فتح حوارات أخرى بعد إغلاق اللوحة.
class PaletteCommand {
  final String id;
  final String labelAr;
  final IconData icon;
  final String? shortcutHint;

  /// أوامر v1 قد تكون معطّلة مع سبب (يظهر بدل الاختصار).
  final bool enabled;
  final String? disabledReason;
  final void Function(BuildContext ctx) action;

  const PaletteCommand({
    required this.id,
    required this.labelAr,
    required this.icon,
    required this.action,
    this.shortcutHint,
    this.enabled = true,
    this.disabledReason,
  });
}

/// الأوامر الافتراضية المربوطة بأشياء حقيقية عبر [ref].
///
/// تُمرَّر من أي مكان لديه WidgetRef:
/// ```dart
/// showCommandPalette(context, defaultCommands(ref, context));
/// ```
List<PaletteCommand> defaultCommands(WidgetRef ref, BuildContext ctx) {
  return [
    PaletteCommand(
      id: 'undo',
      labelAr: 'تراجع',
      icon: Icons.undo,
      shortcutHint: 'Ctrl+Z',
      action: (_) {
        final notifier = ref.read(timelineProvider.notifier);
        if (!notifier.canUndo) {
          ref.read(toastProvider.notifier).info('لا يوجد ما يمكن التراجع عنه');
          return;
        }
        notifier.undo();
        ref.read(toastProvider.notifier).success('تراجع');
      },
    ),
    PaletteCommand(
      id: 'redo',
      labelAr: 'إعادة',
      icon: Icons.redo,
      shortcutHint: 'Ctrl+Y',
      action: (_) {
        final notifier = ref.read(timelineProvider.notifier);
        if (!notifier.canRedo) {
          ref.read(toastProvider.notifier).info('لا يوجد ما يمكن إعادته');
          return;
        }
        notifier.redo();
        ref.read(toastProvider.notifier).success('إعادة');
      },
    ),
    PaletteCommand(
      id: 'export',
      labelAr: 'تصدير الفيديو',
      icon: Icons.ios_share,
      action: (context) {
        showDialog<ExportSettings>(
          context: context,
          builder: (_) => const ExportModal(),
        );
      },
    ),
    PaletteCommand(
      id: 'settings',
      labelAr: 'الإعدادات',
      icon: Icons.settings_outlined,
      action: (context) {
        showDialog<bool>(
          context: context,
          builder: (_) => const SettingsModal(),
        );
      },
    ),
    PaletteCommand(
      id: 'split',
      labelAr: 'قص عند المؤشر',
      icon: Icons.content_cut,
      shortcutHint: 'Ctrl+S',
      action: (_) {
        final playhead = ref.read(timelineProvider).timeline.playheadSec;
        ref.read(timelineProvider.notifier).splitClipAtPlayhead(playhead);
        ref.read(toastProvider.notifier).success('قص عند المؤشر');
      },
    ),
    // TODO(Squad-D0): اربط بمكتبة الوسائط الحقيقية عند توفر مصدر الفيديو الواحد
    // المستورد (cross-owned: home_screen._pickAndImport) — حالياً v1 معطّل.
    PaletteCommand(
      id: 'auto_edit',
      labelAr: 'مونتاج تلقائي',
      icon: Icons.auto_awesome,
      enabled: false,
      disabledReason: 'اختر فيديو أولاً',
      action: (_) {},
    ),
  ];
}

/// يفتح لوحة الأوامر فوق السياق الحالي. تُستدعى من Ctrl+K تلقائياً عبر
/// [KeyboardShortcutsWidget]، ويمكن استدعاؤها يدوياً من أي زر/قائمة.
Future<void> showCommandPalette(
  BuildContext context,
  List<PaletteCommand> commands,
) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => CommandPaletteOverlay(
      commands: commands,
      originContext: context,
    ),
  );
}
