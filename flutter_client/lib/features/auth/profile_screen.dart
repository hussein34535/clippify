import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/auth_store.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/l10n/context_l10n.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: switch (auth.status) {
            AuthStatus.loading => const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            AuthStatus.unauthenticated => const _UnauthenticatedView(),
            AuthStatus.authenticated => _ProfileCard(user: auth.user!),
          },
        ),
      ),
    );
  }
}

class _UnauthenticatedView extends StatelessWidget {
  const _UnauthenticatedView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.account_circle_outlined,
            size: 56, color: AppColors.textMuted),
        const SizedBox(height: 12),
        Text(
          context.l10n.t('profile_not_signed_in'),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
      ],
    );
  }
}

Color _planColor(String plan) => switch (plan) {
      'pro' => const Color(0xFFBF5AF2), // بنفسجي
      'studio' => AppColors.warning, // ذهبي
      _ => const Color(0xFF8E8E93), // رمادي
    };

// TODO(l10n): plan names are brand labels (match billing tiers) — left as-is.
String _planLabel(String plan) => switch (plan) {
      'pro' => 'Pro',
      'studio' => 'Studio',
      _ => 'Free',
    };

class _PlanChip extends StatelessWidget {
  final String plan;
  const _PlanChip(this.plan);

  @override
  Widget build(BuildContext context) {
    final color = _planColor(plan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        _planLabel(plan),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class _ProfileCard extends ConsumerStatefulWidget {
  final AuthUser user;
  const _ProfileCard({required this.user});

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  bool _loggingOut = false;

  Future<void> _confirmLogout() async {
    final l10n = context.l10n; // captured before async gap
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceVariant,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(l10n.t('profile_logout_confirm_title'),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: Text(l10n.t('profile_logout_confirm_body'),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: Text(l10n.t('profile_logout_confirm_btn'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loggingOut = true);
    await ref.read(authStateProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final ratio =
        user.creditsLimit > 0 ? user.creditsUsed / user.creditsLimit : 0.0;

    return Container(
      width: 360,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withValues(alpha: .18),
                backgroundImage: null,
                child: Text(
                  user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _PlanChip(user.plan),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.l10n.t('profile_credits_used'),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5)),
              Text('${user.creditsUsed} / ${user.creditsLimit}',
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation(
                ratio >= 1.0 ? AppColors.destructive : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              onPressed: _loggingOut ? null : _confirmLogout,
              icon: _loggingOut
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.logout, size: 17),
              label: Text(context.l10n.t('profile_logout_btn'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.destructive,
                side: BorderSide(color: AppColors.destructive.withValues(alpha: .5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
