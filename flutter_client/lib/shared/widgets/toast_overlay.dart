import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/toast_provider.dart';
import '../../core/theme/app_theme.dart';

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
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Column(
                children: toasts.map((t) {
                  Color bgColor;
                  IconData icon;
                  switch (t.type) {
                    case ToastType.success:
                      bgColor = AppColors.secondary;
                      icon = Icons.check_circle_rounded;
                    case ToastType.error:
                      bgColor = Colors.redAccent;
                      icon = Icons.error_rounded;
                    case ToastType.info:
                      bgColor = AppColors.primary;
                      icon = Icons.info_rounded;
                  }
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(t.message, style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Inter')),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }
}
