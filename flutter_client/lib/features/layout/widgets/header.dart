import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/providers/theme_provider.dart';
import '../../ui/edge_ui.dart';

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
  final VoidCallback? onSplit;
  final VoidCallback? onSaveAs;
  final VoidCallback? onCut;
  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onSelectAll;
  final VoidCallback? onFullScreen;

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
    this.onSplit,
    this.onSaveAs,
    this.onCut,
    this.onCopy,
    this.onPaste,
    this.onSelectAll,
    this.onFullScreen,
  });

  List<EdgeMenuEntry> _fileMenu() => [
    EdgeMenuEntry(label: 'New Project', shortcut: 'Ctrl+N', icon: Icons.add_rounded, action: onNewProject),
    EdgeMenuEntry(label: 'Open...', shortcut: 'Ctrl+O', icon: Icons.folder_open_rounded, action: onLoad),
    EdgeMenuEntry(label: 'Save', shortcut: 'Ctrl+S', icon: Icons.save_rounded, action: onSave),
    EdgeMenuEntry(label: 'Save As...', shortcut: 'Ctrl+Shift+S', icon: Icons.save_alt, action: onSaveAs),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Export...', shortcut: 'Ctrl+E', icon: Icons.file_upload_rounded, action: onExport, enabled: !isExporting),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Settings...', shortcut: 'Ctrl+,', icon: Icons.settings_rounded, action: onSettings),
  ];

  List<EdgeMenuEntry> _editMenu() => [
    EdgeMenuEntry(label: 'Undo', shortcut: 'Ctrl+Z', icon: Icons.undo_rounded, action: onUndo),
    EdgeMenuEntry(label: 'Redo', shortcut: 'Ctrl+Y', icon: Icons.redo_rounded, action: onRedo),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Cut', shortcut: 'Ctrl+X', icon: Icons.content_cut_rounded, action: onCut),
    EdgeMenuEntry(label: 'Copy', shortcut: 'Ctrl+C', icon: Icons.copy_rounded, action: onCopy),
    EdgeMenuEntry(label: 'Paste', shortcut: 'Ctrl+V', icon: Icons.content_paste_rounded, action: onPaste),
    const EdgeMenuEntry.divider(),
    EdgeMenuEntry(label: 'Select All', shortcut: 'Ctrl+A', icon: Icons.select_all, action: onSelectAll),
  ];

  List<EdgeMenuEntry> _viewMenu() => [
    EdgeMenuEntry(label: 'Full Screen', shortcut: 'F11', icon: Icons.fullscreen_rounded, action: onFullScreen),
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

    return Container(
      height: height ?? 56,
      decoration: const BoxDecoration(
        color: EdgeTheme.menuBar,
        border: Border(bottom: BorderSide(color: EdgeTheme.divider)),
      ),
      child: Row(
        children: [
          // Wordmark only
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Clippify',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: EdgeTheme.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Menu bar
          Expanded(
            child: Row(
              children: [
                EdgeMenuButton(label: 'File', entries: _fileMenu()),
                EdgeMenuButton(label: 'Edit', entries: _editMenu()),
                EdgeMenuButton(label: 'View', entries: _viewMenu()),
              ],
            ),
          ),

          // Toolbar actions (3 buttons only)
          if (onUndo != null)
            _ToolbarBtn(icon: Icons.undo_rounded, tooltip: 'Undo', onTap: onUndo!),
          if (onRedo != null)
            _ToolbarBtn(icon: Icons.redo_rounded, tooltip: 'Redo', onTap: onRedo!),
          if (onSplit != null)
            _ToolbarBtn(icon: Icons.content_cut_rounded, tooltip: 'Split', onTap: onSplit!),
          const SizedBox(width: 12),

          // Export button (Flat)
          AnimatedOpacity(
            opacity: isExporting ? 0.5 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                color: isExporting ? EdgeTheme.toolbar : accent,
                borderRadius: BorderRadius.circular(6),
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
                          const SizedBox(
                            width: 11,
                            height: 11,
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
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _ToolbarBtn extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
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
            child: Icon(
              widget.icon,
              size: 16,
              color: _hovered ? EdgeTheme.textPrimary : EdgeTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
