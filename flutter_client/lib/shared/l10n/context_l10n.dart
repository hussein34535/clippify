import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_strings.dart';
import 'locale_provider.dart';

/// `context.l10n` — works WITHOUT flutter_localizations delegates because the
/// app renders its own strings. Reads the locale directly from
/// [localeProvider] via the nearest ProviderScope; falls back to Arabic when
/// used outside a scope (never throws).
extension L10nContext on BuildContext {
  L10n get l10n {
    try {
      final container = ProviderScope.containerOf(this, listen: false);
      return L10n(container.read(localeProvider).resolved);
    } catch (_) {
      return const L10n(L10n.fallbackLocale);
    }
  }
}
