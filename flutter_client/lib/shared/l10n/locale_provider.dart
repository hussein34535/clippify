import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User language preference — persisted in SharedPreferences under
/// [LocaleNotifier.prefsKey] (`clippify_locale`).
enum LanguagePref { arabic, english, system }

/// Immutable snapshot of the language setting plus the resolved [Locale].
class LocaleState {
  final LanguagePref pref;
  final Locale resolved;

  const LocaleState({
    this.pref = LanguagePref.arabic,
    this.resolved = const Locale('ar'),
  });
}

class LocaleNotifier extends StateNotifier<LocaleState> {
  LocaleNotifier() : super(const LocaleState()) {
    _load();
  }

  static const String prefsKey = 'clippify_locale';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    applyStored(prefs.getString(prefsKey));
  }

  /// Applies a raw stored value ('ar' | 'en' | 'system'); null → 'ar'.
  void applyStored(String? stored) {
    final pref = prefFromStored(stored);
    state = LocaleState(pref: pref, resolved: resolve(pref));
  }

  Future<void> setLanguage(LanguagePref pref) async {
    state = LocaleState(pref: pref, resolved: resolve(pref));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, prefToStored(pref));
  }

  static LanguagePref prefFromStored(String? stored) {
    switch (stored) {
      case 'en':
        return LanguagePref.english;
      case 'system':
        return LanguagePref.system;
      default:
        return LanguagePref.arabic; // 'ar' is the product default
    }
  }

  static String prefToStored(LanguagePref pref) {
    switch (pref) {
      case LanguagePref.english:
        return 'en';
      case LanguagePref.system:
        return 'system';
      case LanguagePref.arabic:
        return 'ar';
    }
  }

  static Locale resolve(LanguagePref pref) {
    switch (pref) {
      case LanguagePref.arabic:
        return const Locale('ar');
      case LanguagePref.english:
        return const Locale('en');
      case LanguagePref.system:
        final sys = PlatformDispatcher.instance.locale;
        final code = sys.languageCode.toLowerCase();
        if (code.startsWith('en')) return const Locale('en');
        // Arabic-first product: any non-English system locale → ar.
        return const Locale('ar');
    }
  }
}

final localeProvider =
    StateNotifierProvider<LocaleNotifier, LocaleState>((_) => LocaleNotifier());
