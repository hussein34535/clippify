import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_strings.dart';
import 'locale_provider.dart';

/// Reusable language switcher (العربية / English / النظام).
///
/// Deliberately NOT wired into other screens yet — desktop settings and the
/// mobile profile will embed it later. Safe to drop into any Row/Column.
class LanguageToggleRow extends ConsumerWidget {
  const LanguageToggleRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(localeProvider);
    final l10n = L10n(state.resolved);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 10),
          child: Text(
            l10n.t('settings_language'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        _LanguageOption(
          valueKey: 'lang_ar',
          label: l10n.t('lang_arabic'),
          selected: state.pref == LanguagePref.arabic,
          onTap: () => ref
              .read(localeProvider.notifier)
              .setLanguage(LanguagePref.arabic),
        ),
        const SizedBox(width: 6),
        _LanguageOption(
          valueKey: 'lang_en',
          label: l10n.t('lang_english'),
          selected: state.pref == LanguagePref.english,
          onTap: () => ref
              .read(localeProvider.notifier)
              .setLanguage(LanguagePref.english),
        ),
        const SizedBox(width: 6),
        _LanguageOption(
          valueKey: 'lang_system',
          label: l10n.t('lang_system'),
          selected: state.pref == LanguagePref.system,
          onTap: () => ref
              .read(localeProvider.notifier)
              .setLanguage(LanguagePref.system),
        ),
      ],
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String valueKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.valueKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: ValueKey(valueKey),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: .4),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
