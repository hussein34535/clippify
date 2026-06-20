import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../ui/edge_ui.dart';

const _workspacePresets = <(String, String, String)>[
  ('editing', 'Editing', 'Focus on timeline'),
  ('color', 'Color', 'Focus on color grading'),
  ('audio', 'Audio', 'Focus on audio'),
  ('effects', 'Effects', 'Focus on effects'),
  ('minimal', 'Minimal', 'Minimum panels'),
];

const _themePresets = <String>[
  'ClipAI Dark',
  'ClipAI Light',
  'Midnight',
  'Sunset',
  'Forest',
  'Ocean',
];

class HeaderWidget extends ConsumerWidget {
  final VoidCallback? onExport;
  final VoidCallback? onSettings;
  final VoidCallback? onThemeToggle;
  final VoidCallback? onSave;
  final VoidCallback? onLoad;
  final VoidCallback? onReset;
  final VoidCallback? onAddText;
  final VoidCallback? onNewProject;
  final VoidCallback? onShowShortcuts;
  final VoidCallback? onShowPlugins;
  final VoidCallback? onShowCollaboration;
  final VoidCallback? onCapture;
  final IconData themeIcon;
  final bool isExporting;
  final bool collaborationEnabled;
  final void Function(String id)? onWorkspacePreset;
  final void Function(String name)? onThemePresetSelected;
  final VoidCallback? onSecondScreen;
  final String? currentWorkspaceId;
  final bool secondScreenEnabled;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onSplit;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onSnap;

  const HeaderWidget({
    super.key,
    this.onExport,
    this.onSettings,
    this.onThemeToggle,
    this.onSave,
    this.onLoad,
    this.onReset,
    this.onAddText,
    this.onNewProject,
    this.onShowShortcuts,
    this.onShowPlugins,
    this.onShowCollaboration,
    this.onCapture,
    this.themeIcon = Icons.dark_mode_rounded,
    this.isExporting = false,
    this.collaborationEnabled = false,
    this.onWorkspacePreset,
    this.onThemePresetSelected,
    this.onSecondScreen,
    this.currentWorkspaceId,
    this.secondScreenEnabled = false,
    this.onUndo,
    this.onRedo,
    this.onSplit,
    this.onZoomIn,
    this.onZoomOut,
    this.onSnap,
  });

  List<EdgeMenuEntry> _fileMenu() => [
    EdgeMenuEntry(label: 'New Project', shortcut: 'Ctrl+N', icon: Icons.add_rounded, action: onNewProject),
    EdgeMenuEntry(label: 'Open...', shortcut: 'Ctrl+O', icon: Icons.folder_open_rounded, action: onLoad),
    EdgeMenuEntry(label: 'Save', shortcut: 'Ctrl+S', icon: Icons.save_rounded, action: onSave),
    EdgeMenuEntry(label: 'Save As...', shortcut: 'Ctrl+Shift+S', icon: Icons.save_alt),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Export...', shortcut: 'Ctrl+E', icon: Icons.file_upload_rounded, action: onExport, enabled: !isExporting),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Settings...', shortcut: 'Ctrl+,', icon: Icons.settings_rounded, action: onSettings),
  ];

  List<EdgeMenuEntry> _editMenu() => [
    EdgeMenuEntry(label: 'Undo', shortcut: 'Ctrl+Z', icon: Icons.undo_rounded, action: onUndo),
    EdgeMenuEntry(label: 'Redo', shortcut: 'Ctrl+Y', icon: Icons.redo_rounded, action: onRedo),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Cut', shortcut: 'Ctrl+X', icon: Icons.content_cut_rounded),
    EdgeMenuEntry(label: 'Copy', shortcut: 'Ctrl+C', icon: Icons.copy_rounded),
    EdgeMenuEntry(label: 'Paste', shortcut: 'Ctrl+V', icon: Icons.content_paste_rounded),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Select All', shortcut: 'Ctrl+A', icon: Icons.select_all),
  ];

  List<EdgeMenuEntry> _clipMenu() => [
    EdgeMenuEntry(label: 'Split', shortcut: 'Ctrl+S', icon: Icons.content_cut_rounded, action: onSplit),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Delete', shortcut: 'Delete', icon: Icons.delete_rounded),
    EdgeMenuEntry(label: 'Speed/Duration...', shortcut: 'Ctrl+R', icon: Icons.speed_rounded),
    EdgeMenuEntry(label: 'Nest', shortcut: 'Ctrl+G', icon: Icons.group_work_rounded),
  ];

  List<EdgeMenuEntry> _timelineMenu() => [
    EdgeMenuEntry(label: 'Add Track', shortcut: 'Ctrl+T', icon: Icons.add_circle_outline_rounded),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Zoom In', shortcut: 'Ctrl+=', icon: Icons.zoom_in_rounded, action: onZoomIn),
    EdgeMenuEntry(label: 'Zoom Out', shortcut: 'Ctrl+-', icon: Icons.zoom_out_rounded, action: onZoomOut),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Toggle Snap', shortcut: 'N', icon: Icons.bolt_rounded, action: onSnap),
  ];

  List<EdgeMenuEntry> _viewMenu() => [
    EdgeMenuEntry(label: 'Full Screen', shortcut: 'F11', icon: Icons.fullscreen_rounded),
    EdgeMenuEntry(label: 'Second Display', icon: Icons.monitor_rounded, action: onSecondScreen),
    const EdgeMenuEntry.divider(),
    ..._workspacePresets.map((p) => EdgeMenuEntry(
      label: p.$2,
      shortcut: p.$1 == currentWorkspaceId ? '✓' : null,
      icon: p.$1 == currentWorkspaceId ? Icons.check_rounded : Icons.circle_outlined,
      action: () => onWorkspacePreset?.call(p.$1),
    )),
    const EdgeMenuEntry.divider(),
    ..._themePresets.map((t) => EdgeMenuEntry(
      label: t,
      action: () => onThemePresetSelected?.call(t),
    )),
  ];

  List<EdgeMenuEntry> _helpMenu() => [
    EdgeMenuEntry(label: 'Keyboard Shortcuts...', shortcut: '?', icon: Icons.keyboard_rounded, action: onShowShortcuts),
    EdgeMenuEntry(label: 'Plugins...', icon: Icons.extension_rounded, action: onShowPlugins),
    EdgeMenuEntry(label: 'Recording...', shortcut: 'Ctrl+R', icon: Icons.fiber_manual_record_rounded, action: onCapture),
    EdgeMenuEntry(label: 'Collaboration...', icon: Icons.groups_rounded, action: onShowCollaboration),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'About ClipAI Pro', icon: Icons.info_outline_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = ref.watch(appPrefsProvider).accentColor;

    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: EdgeTheme.menuBar,
        border: Border(bottom: BorderSide(color: EdgeTheme.divider)),
      ),
      child: Row(
        children: [
          // Logo + App name
          Container(
            width: 28, height: 28,
            margin: const EdgeInsets.only(left: 12, right: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: accent.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
          ),
          Text(
            'ClipAI Pro',
            style: TextStyle(
              fontFamily: 'Outfit', fontSize: 15, fontWeight: FontWeight.w700,
              color: EdgeTheme.textPrimary, letterSpacing: -0.3,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Text('Beta', style: TextStyle(fontSize: 9, color: accent, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          const SizedBox(width: 16),

          // Menu bar
          Expanded(
            child: Row(
              children: [
                EdgeMenuButton(label: 'File', entries: _fileMenu()),
                EdgeMenuButton(label: 'Edit', entries: _editMenu()),
                EdgeMenuButton(label: 'Clip', entries: _clipMenu()),
                EdgeMenuButton(label: 'Timeline', entries: _timelineMenu()),
                EdgeMenuButton(label: 'View', entries: _viewMenu()),
                EdgeMenuButton(label: 'Help', entries: _helpMenu()),
              ],
            ),
          ),

          // Toolbar actions
          if (onUndo != null)
            _ToolbarBtn(icon: Icons.undo_rounded, tooltip: 'Undo', onTap: onUndo!),
          if (onRedo != null)
            _ToolbarBtn(icon: Icons.redo_rounded, tooltip: 'Redo', onTap: onRedo!),
          if (onSplit != null)
            _ToolbarBtn(icon: Icons.content_cut_rounded, tooltip: 'Split', onTap: onSplit!),
          if (onCapture != null)
            _ToolbarBtn(icon: Icons.fiber_manual_record_rounded, tooltip: 'Record', onTap: onCapture!),
          _ToolbarBtn(
            icon: Icons.cleaning_services_rounded, tooltip: 'Clear Cache',
            onTap: () async {
              final res = await ApiClient().clearCache();
              switch (res) {
                case Success(data: final data):
                  ref.read(toastProvider.notifier).info(data['message'] ?? 'Cache cleared');
                case Failure(message: final msg):
                  ref.read(toastProvider.notifier).error('Cache clear failed: $msg');
              }
            },
          ),
          if (onSettings != null)
            _ToolbarBtn(icon: Icons.settings_rounded, tooltip: 'Settings', onTap: onSettings!),
          const SizedBox(width: 4),

          // Export button
          AnimatedOpacity(
            opacity: isExporting ? 0.5 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                color: isExporting ? EdgeTheme.toolbar : accent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isExporting ? null : [
                  BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isExporting ? null : onExport,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isExporting)
                          const SizedBox(width: 11, height: 11,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
                          )
                        else
                          const Icon(Icons.upload_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        const Text('Export', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Inter')),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ToolbarBtn extends StatefulWidget {
  final IconData icon; final String tooltip; final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.tooltip, required this.onTap});
  @override
  State<_ToolbarBtn> createState() => _ToolbarBtnState();
}

class _ToolbarBtnState extends State<_ToolbarBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _hovered ? EdgeTheme.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(widget.icon, size: 16,
              color: _hovered ? EdgeTheme.textPrimary : EdgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
