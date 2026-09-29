import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/auth_store.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/l10n/app_strings.dart';
import '../../shared/l10n/context_l10n.dart';

class AuthScreen extends ConsumerStatefulWidget {
  final VoidCallback? onAuthenticated;
  const AuthScreen({super.key, this.onAuthenticated});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isRegister = false;
  bool _busy = false;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n; // captured before async gap
    setState(() => _busy = true);
    final notifier = ref.read(authStateProvider.notifier);
    try {
      if (_isRegister) {
        await notifier.register(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
          _nameCtrl.text.trim(),
        );
      } else {
        await notifier.login(_emailCtrl.text.trim(), _passwordCtrl.text);
      }
      widget.onAuthenticated?.call();
    } catch (e) {
      // TODO(l10n): AuthException.messageAr comes from the backend — left as-is.
      final msg = e is AuthException ? e.messageAr : l10n.t('auth_unexpected_error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // TODO(l10n): forced RTL kept to avoid visual regressions.
            content: Text(msg, textDirection: TextDirection.rtl),
            backgroundColor: AppColors.destructive,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueAsGuest() async {
    await GuestFlag.set(true);
    ref.read(skipAuthProviderProvider.notifier).state = true;
    widget.onAuthenticated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.border),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildLogo(),
                      const SizedBox(height: 12),
                      Text(
                        l10n.t('auth_welcome'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRegister
                            ? l10n.t('auth_register_subtitle')
                            : l10n.t('auth_login_subtitle'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      _buildModeToggle(l10n),
                      const SizedBox(height: 20),
                      if (_isRegister) ...[
                        _buildField(
                          controller: _nameCtrl,
                          label: l10n.t('auth_field_name'),
                          icon: Icons.person_outline,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? l10n.t('auth_err_name_required')
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _buildField(
                        controller: _emailCtrl,
                        label: l10n.t('auth_field_email'),
                        icon: Icons.alternate_email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => (v == null || !v.contains('@'))
                            ? l10n.t('auth_err_invalid_email')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _buildField(
                        controller: _passwordCtrl,
                        label: l10n.t('auth_field_password'),
                        icon: Icons.lock_outline,
                        obscure: true,
                        validator: (v) => (v == null || v.length < 6)
                            ? l10n.t('auth_err_short_password')
                            : null,
                      ),
                      const SizedBox(height: 20),
                      _buildSubmitButton(l10n),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _continueAsGuest,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                        ),
                        child: Text(l10n.t('auth_skip')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.secondary],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: .35),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.content_cut_rounded,
            color: Colors.white, size: 26),
      ),
    );
  }

  Widget _buildModeToggle(L10n l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          _buildToggleTab(l10n.t('auth_tab_login'), !_isRegister, () {
            setState(() => _isRegister = false);
          }),
          _buildToggleTab(l10n.t('auth_tab_register'), _isRegister, () {
            setState(() => _isRegister = true);
          }),
        ],
      ),
    );
  }

  Widget _buildToggleTab(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.destructive),
        ),
      ),
    );
  }

  Widget _buildSubmitButton(L10n l10n) {
    return SizedBox(
      height: 46,
      child: ElevatedButton(
        onPressed: _busy ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: .5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        child: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              )
            : Text(
                _isRegister ? l10n.t('auth_btn_register') : l10n.t('auth_btn_login'),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }
}
