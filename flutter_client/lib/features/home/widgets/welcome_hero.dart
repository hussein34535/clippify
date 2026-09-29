import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_kit.dart';

/// iOS-style welcome hero shown in the viewer when the project is
/// still empty. Fully local — never blocks on backend availability.
class WelcomeHero extends StatelessWidget {
  final VoidCallback onImportVideo;
  final VoidCallback onOpenProject;
  final List<RecentProject> recentProjects;
  final ValueChanged<String> onOpenRecent;

  const WelcomeHero({
    super.key,
    required this.onImportVideo,
    required this.onOpenProject,
    required this.recentProjects,
    required this.onOpenRecent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const IOSGradientHeader(
                title: 'Clippify Studio',
                subtitle: 'محرر فيديو احترافي — ابدأ مشروعك القادم',
                icon: Icons.movie_filter_rounded,
              ),
              const SizedBox(height: AppSpacing.xl),
              _ImportButton(label: 'استيراد فيديو', icon: Icons.add_rounded, onPressed: onImportVideo),
              const SizedBox(height: AppSpacing.sm),
              IOSButton(
                label: 'فتح مشروع',
                icon: Icons.folder_open_rounded,
                style: IOSButtonStyle.ghost,
                onPressed: onOpenProject,
              ),
              if (recentProjects.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                const Text('مشاريع حديثة',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6,
                        color: AppColors.textMuted, fontFamilyFallback: AppTypography.fallbacks)),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final project in recentProjects.take(6))
                      _RecentProjectCard(project: project, onOpen: () => onOpenRecent(project.path)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RecentProject {
  final String name;
  final String path;
  const RecentProject({required this.name, required this.path});
}

class _ImportButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _ImportButton({required this.label, required this.icon, required this.onPressed});

  @override
  State<_ImportButton> createState() => _ImportButtonState();
}

class _ImportButtonState extends State<_ImportButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          scale: _pressed ? 0.97 : 1.0,
          child: AnimatedContainer(
            duration: AppTheme.animFast,
            curve: AppTheme.animCurve,
            width: 280,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: _hovered ? const Color(0xFF2492FF) : AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: _hovered ? 0.5 : 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text(widget.label,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white,
                        fontFamilyFallback: AppTypography.fallbacks)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentProjectCard extends StatefulWidget {
  final RecentProject project;
  final VoidCallback onOpen;
  const _RecentProjectCard({required this.project, required this.onOpen});

  @override
  State<_RecentProjectCard> createState() => _RecentProjectCardState();
}

class _RecentProjectCardState extends State<_RecentProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: AnimatedContainer(
          duration: AppTheme.animFast,
          curve: AppTheme.animCurve,
          width: 170,
          padding: const EdgeInsets.all(AppSpacing.md),
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border, width: 0.5),
            boxShadow: _hovered ? AppShadows.card : AppShadows.panel,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.description_rounded, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary, fontFamilyFallback: AppTypography.fallbacks),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
