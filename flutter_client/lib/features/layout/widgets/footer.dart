import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class FooterWidget extends StatelessWidget {
  final bool isBackendConnected;
  final bool isExporting;
  final double exportProgress;
  final String exportStatus;
  final String? statusMessage;

  const FooterWidget({
    super.key,
    this.isBackendConnected = true,
    this.isExporting = false,
    this.exportProgress = 0.0,
    this.exportStatus = '',
    this.statusMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: isBackendConnected ? Colors.greenAccent : Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isBackendConnected ? 'Backend connected (Port: 8000)' : 'Backend disconnected',
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontFamily: 'Inter'),
          ),
          if (statusMessage != null) ...[
            const SizedBox(width: 12),
            Text(statusMessage!, style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamily: 'Inter')),
          ],
          const Spacer(),
          if (isExporting)
            Text(
              'Exporting: $exportStatus (${(exportProgress * 100).toInt()}%)',
              style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
            ),
        ],
      ),
    );
  }
}
