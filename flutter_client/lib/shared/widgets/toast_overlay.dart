import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/toast_provider.dart';
import '../../core/theme/app_theme.dart';

/// iOS-style floating toast: frosted card pinned to the top,
/// 14px continuous corners, colored status icon.
class ToastOverlay extends ConsumerWidget {
  final Widget child;
  const ToastOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toasts = ref.watch(toastProvider);
    return Stack(
      children: [
        child,
        if (toasts.isNotEmpty)
          Positioned(
            top: 14,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Column(
                children: [
                  for (final t in toasts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ToastCard(message: t.message, type: t.type),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  final String message;
  final ToastType type;
  const _ToastCard({required this.message, required this.type});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (type) {
      ToastType.success => (AppColors.secondary, Icons.check_circle_rounded),
      ToastType.error => (AppColors.destructive, Icons.cancel_rounded),
      ToastType.info => (AppColors.primary, Icons.info_rounded),
    };

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.symmetric(horizontal: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.toast),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AnimatedContainer(
              duration: AppTheme.animBase,
              curve: AppTheme.animCurve,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xE6222225),
                borderRadius: BorderRadius.circular(AppRadius.toast),
                border: Border.all(color: AppColors.border, width: 0.5),
                boxShadow: AppShadows.modal,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: color, size: 18),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          fontFamilyFallback: AppTypography.fallbacks),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
