import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/auth_store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/toast_provider.dart';
import '../../auth/auth_screen.dart';
import '../../auth/profile_screen.dart';

// عقود docs/CONTRACTS.md — قسم Plans & Credits.
const Color _kPlanProColor = Color(0xFF8B5CF6);
const Color _kPlanStudioColor = Color(0xFFFFD60A);
const Color _kPlanFreeColor = Color(0xFF8E8E93);

Color planChipColor(String plan) => switch (plan) {
      'pro' => _kPlanProColor,
      'studio' => _kPlanStudioColor,
      _ => _kPlanFreeColor,
    };

String planChipLabel(String plan) => switch (plan) {
      'pro' => 'Pro',
      'studio' => 'Studio',
      _ => 'Free',
    };

/// ورقة الحساب السفلية — تعرض حالة المصادقة والأرصدة، وتتيح الدخول/الخروج.
Future<void> showAccountSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _AccountSheet(),
  );
}

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final authenticated =
        auth.status == AuthStatus.authenticated && user != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: Container(
                  width: 420,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 48,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SheetHeader(user: user),
                      const Divider(height: 1, color: AppColors.borderSubtle),
                      if (authenticated)
                        _AuthenticatedBody(user: user)
                      else
                        const _UnauthenticatedBody(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  final AuthUser? user;

  const _SheetHeader({this.user});

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.account_circle_rounded,
                  size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Text(
              'حسابي',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFamily: 'Inter',
                fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'],
              ),
            ),
          ],
        ),
      );
    }

    final initial = u.name.isNotEmpty
        ? u.name[0].toUpperCase()
        : (u.email.isNotEmpty ? u.email[0].toUpperCase() : '?');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
            ),
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.name.isEmpty ? u.email : u.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  u.email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontFamily: 'Inter',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _PlanChip(plan: u.plan),
        ],
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  final String plan;

  const _PlanChip({required this.plan});

  @override
  Widget build(BuildContext context) {
    final color = planChipColor(plan);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        planChipLabel(plan),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _UnauthenticatedBody extends StatelessWidget {
  const _UnauthenticatedBody();

  @override
  Widget build(BuildContext context) {
    // AuthScreen تحتوي Scaffold كاملاً — يجب منحها قيد ارتفاع مباشراً
    // (وضعها داخل scrollable يجعل Scaffold يتمدد إلى ما لا نهاية).
    return SizedBox(
      height: 520,
      child: AuthScreen(
        onAuthenticated: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _AuthenticatedBody extends ConsumerWidget {
  final AuthUser user;

  const _AuthenticatedBody({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratio =
        user.creditsLimit > 0 ? user.creditsUsed / user.creditsLimit : 0.0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── الأرصدة ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'الأرصدة المستخدمة',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${user.creditsUsed} / ${user.creditsLimit}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
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

          const SizedBox(height: 18),

          // ── الإجراءات ────────────────────────────
          // ملاحظة: إجراء «تحديث الاستخدام» (GET /api/billing/usage) مخفي
          // حالياً — لا يوجد billing usage provider في lib بعد.
          _ActionTile(
            icon: Icons.person_rounded,
            label: '👤 حسابي',
            onTap: () => _openProfile(context),
          ),
          const SizedBox(height: 8),
          _ActionTile(
            icon: Icons.logout_rounded,
            label: '🚪 تسجيل خروج',
            destructive: true,
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  void _openProfile(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 48, vertical: 32),
        child: ProfileScreen(),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceVariant,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text(
          'تسجيل الخروج',
          textAlign: TextAlign.right,
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'هل أنت متأكد أنك تريد تسجيل الخروج؟',
          textAlign: TextAlign.right,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.destructive),
            child: const Text('خروج',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(authStateProvider.notifier).logout();
    // الورقة تبقى مفتوحة وتتحول تلقائياً لشاشة الدخول (تشاهد authStateProvider).
    ref.read(toastProvider.notifier).info('تم تسجيل الخروج بنجاح');
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool destructive;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.destructive : AppColors.textPrimary;
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        hoverColor: AppColors.border,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['Segoe UI', 'Arial', 'Tahoma'],
                  ),
                ),
              ),
              const Icon(Icons.chevron_left_rounded,
                  size: 15, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
