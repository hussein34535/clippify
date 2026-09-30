import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/ios_kit.dart';
import 'first_run_gate.dart';

/// Request a one-off replay of the onboarding (e.g. from Settings).
/// Home screen keeps the overlay mounted; flipping this shows it.
final onboardingReplayProvider = StateProvider<bool>((_) => false);

class OnboardingOverlay extends ConsumerStatefulWidget {
  final VoidCallback? onDismiss;

  const OnboardingOverlay({super.key, this.onDismiss});

  @override
  ConsumerState<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends ConsumerState<OnboardingOverlay> {
  bool _checked = false;
  bool _visible = false;
  final PageController _pageController = PageController();
  int _page = 0;
  ProviderSubscription<bool>? _replaySub;

  @override
  void initState() {
    super.initState();
    // مستمع لمرة واحدة هنا لا في build — كان ref.listen داخل build
    // يشترك من جديد مع كل إعادة بناء.
    _replaySub = ref.listenManual<bool>(onboardingReplayProvider,
        (prev, next) {
      if (next == true && mounted) setState(() => _visible = true);
    });
    _resolveVisibility();
  }

  @override
  void dispose() {
    _replaySub?.close();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _resolveVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _visible = FirstRunGate.shouldShow(prefs);
      _checked = true;
    });
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await FirstRunGate.markSeen(prefs);
    if (!mounted) return;
    setState(() => _visible = false);
    ref.read(onboardingReplayProvider.notifier).state = false;
    widget.onDismiss?.call();
  }

  void _next() {
    if (_page < 2) {
      _pageController.nextPage(duration: AppTheme.animSlow, curve: AppTheme.animCurve);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || !_visible) return const SizedBox.shrink();

    return Positioned.fill(
      key: const Key('onboarding_overlay'),
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        child: Center(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              // عرض متكيف — 520 الثابتة كانت تفيض على النوافذ الصغيرة.
              width: (MediaQuery.sizeOf(context).width - 48)
                  .clamp(280.0, 520.0),
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: AppColors.border, width: 0.5),
              boxShadow: AppShadows.modal,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    key: const Key('onboarding_dismiss_button'),
                    onPressed: _finish,
                    child: const Text('تخطي',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks)),
                  ),
                ),
                SizedBox(
                  height: 300,
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (i) => setState(() => _page = i),
                    children: const [
                      _OnboardingPage(
                        icon: Icons.movie_creation_rounded,
                        tint: AppColors.primary,
                        title: 'استورد الفيديو',
                        body: 'اسحب أي فيديو إلى المكتبة أو اضغط زر الاستيراد — كل الصيغ الشائعة مدعومة.',
                      ),
                      _OnboardingPage(
                        icon: Icons.auto_awesome_rounded,
                        tint: AppColors.indigo,
                        title: 'دع الذكاء الاصطناعي يختار',
                        body: 'زر Auto-Edit يحلل الفيديو ويقترح أفضل اللقطات تلقائياً على التايملاين.',
                      ),
                      _OnboardingPage(
                        icon: Icons.ios_share_rounded,
                        tint: AppColors.secondary,
                        title: 'عدّل وصدّر',
                        body: 'رتّب المقاطع على تايملاين احترافي ثم اضغط Export ليكون الفيديو جاهزاً للنشر.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // Dots indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: AppTheme.animBase,
                      curve: AppTheme.animCurve,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active ? AppColors.primary : AppColors.surfaceOverlay,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: AnimatedSwitcher(
                    duration: AppTheme.animFast,
                    child: IOSButton(
                      key: ValueKey('onboarding_primary_$_page'),
                      label: _page < 2 ? 'التالي' : 'ابدأ الآن',
                      icon: _page < 2 ? null : Icons.play_arrow_rounded,
                      expand: true,
                      fontSize: 15,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _next,
                    ),
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

class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.tint,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [tint, tint.withValues(alpha: 0.55)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 10)),
              ],
            ),
            child: Icon(icon, size: 42, color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3,
                color: AppColors.textPrimary, fontFamilyFallback: AppTypography.fallbacks),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, height: 1.6, color: AppColors.textSecondary, fontFamilyFallback: AppTypography.fallbacks),
          ),
        ],
      ),
    );
  }
}
