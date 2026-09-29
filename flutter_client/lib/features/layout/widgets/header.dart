import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/backend/auth_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../ui/edge_ui.dart';
import 'account_sheet.dart';

/// نقطة اختبار للنقطة الخضراء (متصل بحساب) على زر الحساب.
const Key kAccountBadgeDotKey = ValueKey('account_badge_dot');

const _workspacePresets = <(String, String, String)>[
  ('editing', 'Editing', 'Focus on timeline'),
  ('color', 'Color', 'Focus on color grading'),
  ('audio', 'Audio', 'Focus on audio'),
  ('effects', 'Effects', 'Focus on effects'),
  ('minimal', 'Minimal', 'Minimum panels'),
];

class HeaderWidget extends ConsumerWidget {
  final double? height;
  final VoidCallback? onExport;
  final VoidCallback? onSettings;
  final VoidCallback? onSave;
  final VoidCallback? onLoad;
  final VoidCallback? onNewProject;
  final bool isExporting;
  final void Function(String id)? onWorkspacePreset;
  final String? currentWorkspaceId;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSaveAs;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onSelectAll;
  final VoidCallback? onFullScreen;
  final Widget? statusBadge;

  const HeaderWidget({
    super.key,
    this.height,
    this.onExport,
    this.onSettings,
    this.onSave,
    this.onLoad,
    this.onNewProject,
    this.isExporting = false,
    this.onWorkspacePreset,
    this.currentWorkspaceId,
    this.onUndo,
    this.onRedo,
    this.onSaveAs,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onSelectAll,
    this.onFullScreen,
    this.statusBadge,
  });

  List<EdgeMenuEntry> _fileMenu() => [
    EdgeMenuEntry(label: 'مشروع جديد', shortcut: 'Ctrl+N', icon: Icons.add_rounded, action: onNewProject),
    EdgeMenuEntry(label: 'فتح...', shortcut: 'Ctrl+O', icon: Icons.folder_open_rounded, action: onLoad),
    EdgeMenuEntry(label: 'حفظ', shortcut: 'Ctrl+S', icon: Icons.save_rounded, action: onSave),
    EdgeMenuEntry(label: 'حفظ باسم...', shortcut: 'Ctrl+Shift+S', icon: Icons.save_alt, action: onSaveAs),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'تصدير...', shortcut: 'Ctrl+E', icon: Icons.file_upload_rounded, action: onExport, enabled: !isExporting && onExport != null),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'الإعدادات...', shortcut: 'Ctrl+,', icon: Icons.settings_rounded, action: onSettings),
  ];

  List<EdgeMenuEntry> _editMenu() => [
    EdgeMenuEntry(label: 'تراجع', shortcut: 'Ctrl+Z', icon: Icons.undo_rounded, action: onUndo),
    EdgeMenuEntry(label: 'إعادة', shortcut: 'Ctrl+Y', icon: Icons.redo_rounded, action: onRedo),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'قص', shortcut: 'Ctrl+X', icon: Icons.content_cut_rounded, action: onCut),
    EdgeMenuEntry(label: 'نسخ', shortcut: 'Ctrl+C', icon: Icons.copy_rounded, action: onCopy),
    EdgeMenuEntry(label: 'لصق', shortcut: 'Ctrl+V', icon: Icons.content_paste_rounded, action: onPaste),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'تحديد الكل', shortcut: 'Ctrl+A', icon: Icons.select_all, action: onSelectAll),
  ];

  List<EdgeMenuEntry> _viewMenu() => [
    EdgeMenuEntry(label: 'ملء الشاشة', shortcut: 'F11', icon: Icons.fullscreen_rounded, action: onFullScreen),
    const EdgeMenuEntry.divider(),
    ..._workspacePresets.map((p) => EdgeMenuEntry(
      label: p.$2,
      shortcut: p.$1 == currentWorkspaceId ? '✓' : null,
      icon: p.$1 == currentWorkspaceId ? Icons.check_rounded : Icons.circle_outlined,
      action: () => onWorkspacePreset?.call(p.$1),
    )),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(appPrefsProvider).accentColor;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height ?? 52,
          decoration: const BoxDecoration(
            color: Color(0xCC161618),
            border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              // Wordmark
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Clippify',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: EdgeTheme.textPrimary,
                    letterSpacing: -0.3,
                    fontFamilyFallback: AppTypography.fallbacks,
                  ),
                ),
              ),
              if (statusBadge != null) ...[
                statusBadge!,
                const SizedBox(width: 12),
              ],
              const SizedBox(width: 8),

              // Menu bar
              Expanded(
                child: Row(
                  children: [
                    EdgeMenuButton(label: 'ملف', entries: _fileMenu()),
                    EdgeMenuButton(label: 'تحرير', entries: _editMenu()),
                    EdgeMenuButton(label: 'عرض', entries: _viewMenu()),
                  ],
                ),
              ),

              // Account button
              const _AccountButton(),
              const SizedBox(width: 4),

              // Toolbar actions (stay mounted when disabled to avoid layout jumps)
              _ToolbarBtn(icon: Icons.undo_rounded, tooltip: 'تراجع', onTap: onUndo),
              _ToolbarBtn(icon: Icons.redo_rounded, tooltip: 'إعادة', onTap: onRedo),
              const SizedBox(width: 12),

              // Export pill
              AnimatedOpacity(
                opacity: (isExporting || onExport == null) ? 0.5 : 1.0,
                duration: AppTheme.animBase,
                child: Container(
                  decoration: BoxDecoration(
                    color: (isExporting || onExport == null) ? EdgeTheme.surfaceElevated : accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: isExporting ? null : AppShadows.button,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: isExporting ? null : onExport,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isExporting)
                              const SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                              )
                            else
                              const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
                            const SizedBox(width: 6),
                            const Text('تصدير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, fontFamilyFallback: AppTypography.fallbacks)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  const _ToolbarBtn({required this.icon, required this.tooltip, this.onTap});

  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

const Color _kAccountDotGreen = Color(0xFF30D158);

/// زر الحساب — نسخة طبق الأصل من [_ToolbarBtn] بصرياً مع نقطة خضراء
/// عند تسجيل الدخول (تشاهد authStateProvider داخلياً بدون كسر توقيع الهيدر).
class _AccountButton extends ConsumerStatefulWidget {
  const _AccountButton();

  @override
  ConsumerState<_AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends ConsumerState<_AccountButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final authenticated = ref.watch(
      authStateProvider.select((s) => s.status == AuthStatus.authenticated),
    );

    return Tooltip(
      message: 'حسابي',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: () => showAccountSheet(context, ref),
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hovered ? EdgeTheme.surfaceOverlay : EdgeTheme.surfaceElevated.withValues(alpha: 0.75),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.account_circle_rounded,
                  size: 16,
                  color: _hovered ? EdgeTheme.textPrimary : EdgeTheme.textSecondary,
                ),
                if (authenticated)
                  Positioned(
                    key: kAccountBadgeDotKey,
                    top: 1,
                    right: 1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: _kAccountDotGreen,
                        shape: BoxShape.circle,
                        border: Border.all(color: EdgeTheme.menuBar, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarBtnState extends State<_ToolbarBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppTheme.animFast,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovered && enabled ? EdgeTheme.surfaceOverlay : Colors.transparent,
              ),
              child: Icon(
                widget.icon,
                size: 16,
                color: _hovered && enabled ? EdgeTheme.textPrimary : EdgeTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
