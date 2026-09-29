import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
//  iOS Kit — shared Cupertino-inspired building blocks.
//  Every surface in the app composes these instead of raw
//  Material chrome so spacing/radius/motion stay consistent.
// ─────────────────────────────────────────────────────────────

/// Filled / ghost / destructive pill button.
enum IOSButtonStyle { filled, ghost, destructive }

class IOSButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IOSButtonStyle style;
  final IconData? icon;
  final double fontSize;
  final EdgeInsets padding;
  final bool expand;

  const IOSButton({
    super.key,
    required this.label,
    this.onPressed,
    this.style = IOSButtonStyle.filled,
    this.icon,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    this.expand = false,
  });

  @override
  State<IOSButton> createState() => _IOSButtonState();
}

class _IOSButtonState extends State<IOSButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    Color fill;
    Color fg;
    BorderSide side = BorderSide.none;
    switch (widget.style) {
      case IOSButtonStyle.filled:
        fill = AppColors.primary;
        fg = Colors.white;
      case IOSButtonStyle.ghost:
        fill = _hovered ? AppColors.surfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.55);
        fg = AppColors.textPrimary;
        side = const BorderSide(color: AppColors.border, width: 0.5);
      case IOSButtonStyle.destructive:
        fill = AppColors.destructive;
        fg = Colors.white;
    }

    final button = AnimatedOpacity(
      duration: AppTheme.animFast,
      opacity: enabled ? 1.0 : 0.4,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        scale: _pressed ? 0.97 : 1.0,
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          curve: AppTheme.animCurve,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: enabled ? (_hovered ? Color.lerp(fill, Colors.white, 0.08) ?? fill : fill) : AppColors.surfaceOverlay,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.fromBorderSide(side),
            boxShadow: enabled && widget.style != IOSButtonStyle.ghost ? AppShadows.button : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: widget.fontSize + 4, color: fg),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  fontWeight: FontWeight.w600,
                  color: enabled ? fg : AppColors.textMuted,
                  fontFamilyFallback: AppTypography.fallbacks,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: widget.expand ? SizedBox(width: double.infinity, child: Center(widthFactor: 1, child: button)) : button,
      ),
    );
  }
}

/// iOS segmented control (sliding pill selection).
class IOSSegmentedControl<T> extends StatelessWidget {
  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  const IOSSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = 30,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceOverlay.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: segments.entries.map((entry) {
          final isSelected = entry.key == selected;
          return GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: AppTheme.animBase,
              curve: AppTheme.animCurve,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.surfaceElevated : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: isSelected
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4, offset: const Offset(0, 1))]
                    : null,
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                  fontFamilyFallback: AppTypography.fallbacks,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// iOS card surface (16px radius + hairline + soft shadow).
class IOSCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double? radius;
  final VoidCallback? onTap;

  const IOSCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color,
    this.radius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius ?? AppRadius.lg),
        border: Border.all(color: AppColors.border, width: 0.5),
        boxShadow: AppShadows.panel,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: body),
    );
  }
}

/// iOS inset list row (Settings-app style grouped row).
class IOSListTile extends StatefulWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const IOSListTile({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  State<IOSListTile> createState() => _IOSListTileState();
}

class _IOSListTileState extends State<IOSListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered && widget.onTap != null ? AppColors.surfaceVariant.withValues(alpha: 0.6) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Row(
            children: [
              if (widget.icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: (widget.iconColor ?? AppColors.primary).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(widget.icon, size: 15, color: widget.iconColor ?? AppColors.primary),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary, fontFamilyFallback: AppTypography.fallbacks)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(widget.subtitle!,
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontFamilyFallback: AppTypography.fallbacks)),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded status badge (dot + label).
class IOSBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const IOSBadge({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 5, spreadRadius: 0),
            ]),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color, fontFamilyFallback: AppTypography.fallbacks)),
        ],
      ),
    );
  }
}

/// Gradient hero header used on welcome/onboarding surfaces.
class IOSGradientHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final double titleSize;

  const IOSGradientHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.titleSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Container(
            width: 64,
            height: 64,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, size: 32, color: Colors.white),
          ),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AppColors.textPrimary,
            fontFamilyFallback: AppTypography.fallbacks,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamilyFallback: AppTypography.fallbacks),
          ),
        ],
      ],
    );
  }
}

/// CupertinoAlertDialog-style modal with an iOS card feel.
/// Actions: pairs of (label, onPressed, isDefault/destructive).
class IOSDialogAction {
  final String label;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isDefault;

  const IOSDialogAction(this.label, {this.onPressed, this.isDestructive = false, this.isDefault = false});
}

Future<T?> showIOSDialog<T>({
  required BuildContext context,
  required String title,
  String? content,
  Widget? contentWidget,
  List<IOSDialogAction> actions = const [],
  bool barrierDismissible = true,
}) {
  return showCupertinoDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
              fontFamilyFallback: AppTypography.fallbacks)),
      content: contentWidget ??
          (content != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(content,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary,
                          fontFamilyFallback: AppTypography.fallbacks)),
                )
              : null),
      actions: [
        for (final action in actions)
          CupertinoDialogAction(
            isDestructiveAction: action.isDestructive,
            isDefaultAction: action.isDefault,
            onPressed: () {
              Navigator.pop(ctx);
              action.onPressed?.call();
            },
            child: Text(action.label),
          ),
      ],
    ),
  );
}

/// Frosted translucent bar material (iOS navigation-bar vibrancy).
class IOSBlurBar extends StatelessWidget {
  final Widget child;
  final double height;
  final Color tint;
  final Border? border;

  const IOSBlurBar({
    super.key,
    required this.child,
    this.height = 52,
    this.tint = const Color(0xD91C1C1E),
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: tint,
            border: border ?? const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Circular floating icon button (iOS toolbar).
class IOSIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  const IOSIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 30,
  });

  @override
  State<IOSIconButton> createState() => _IOSIconButtonState();
}

class _IOSIconButtonState extends State<IOSIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered && widget.onTap != null ? AppColors.surfaceOverlay : AppColors.surfaceVariant.withValues(alpha: 0.75),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Icon(widget.icon, size: widget.size * 0.5, color: AppColors.textPrimary),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
