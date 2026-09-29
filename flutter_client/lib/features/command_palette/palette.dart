import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import 'registry.dart';

class CommandPaletteOverlay extends StatefulWidget {
  final List<PaletteCommand> commands;

  /// سياق الصفحة التي فُتحت منها اللوحة؛ تُمرَّر لأوامر الأوامر بعد الإغلاق.
  final BuildContext originContext;

  const CommandPaletteOverlay({
    super.key,
    required this.commands,
    required this.originContext,
  });

  @override
  State<CommandPaletteOverlay> createState() => _CommandPaletteOverlayState();
}

class _CommandPaletteOverlayState extends State<CommandPaletteOverlay> {
  static const int _maxVisible = 8;
  static const double _rowHeight = 48;

  String _query = '';
  int _selectedIndex = 0;

  List<PaletteCommand> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.commands;
    return widget.commands
        .where((c) => c.labelAr.toLowerCase().contains(q))
        .toList();
  }

  void _runSelected() {
    final filtered = _filtered;
    if (_selectedIndex < 0 || _selectedIndex >= filtered.length) return;
    final cmd = filtered[_selectedIndex];
    if (!cmd.enabled) return;
    Navigator.of(context).pop();
    cmd.action(widget.originContext);
  }

  void _move(int delta) {
    final max = _filtered.length - 1;
    if (max < 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(0, max);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final visibleCount = filtered.length > _maxVisible
        ? _maxVisible
        : filtered.length;
    if (_selectedIndex >= filtered.length) _selectedIndex = 0;

    return Dialog(
      backgroundColor: AppColors.surface,
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 80, left: 16, right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: CallbackShortcuts(
                bindings: <ShortcutActivator, VoidCallback>{
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(-1),
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1),
                  const SingleActivator(LogicalKeyboardKey.enter): _runSelected,
                  const SingleActivator(LogicalKeyboardKey.numpadEnter):
                      _runSelected,
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(context).pop(),
                },
                child: Focus(
                  autofocus: true,
                  child: TextField(
                    autofocus: true,
                    cursorColor: AppColors.primary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontFamily: 'Outfit',
                    ),
                    decoration: const InputDecoration(
                      hintText: 'اكتب أمراً…',
                      hintStyle: TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'Outfit',
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.textSecondary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                        _selectedIndex = 0;
                      });
                    },
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            if (filtered.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا نتائج',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontFamily: 'Outfit',
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: visibleCount,
                  itemBuilder: (context, index) =>
                      _buildRow(filtered[index], index),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(PaletteCommand cmd, int index) {
    final selected = index == _selectedIndex;
    return SizedBox(
      key: ValueKey('palette_row_${cmd.id}_$index'),
      height: _rowHeight,
      child: InkWell(
        onTap: () {
          if (!cmd.enabled) return;
          Navigator.of(context).pop();
          cmd.action(widget.originContext);
        },
        hoverColor: AppColors.surfaceVariant,
        child: Container(
          key: selected ? ValueKey('palette_selected_$index') : null,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                selected ? AppColors.primary.withOpacity(0.15) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                cmd.icon,
                size: 20,
                color: cmd.enabled ? Colors.white : AppColors.textDisabled,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cmd.labelAr,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cmd.enabled
                        ? Colors.white
                        : AppColors.textDisabled,
                    fontSize: 14,
                    fontFamily: 'Outfit',
                  ),
                ),
              ),
              Text(
                cmd.enabled ? (cmd.shortcutHint ?? '') : cmd.disabledReason!,
                style: TextStyle(
                  color: cmd.enabled
                      ? AppColors.primary
                      : AppColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: cmd.enabled ? 'monospace' : 'Outfit',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
