import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

export '../../core/theme/app_theme.dart' show AppThemeMode;

// ─────────────────────────────────────────────
//  Prefs keys
// ─────────────────────────────────────────────
const _kThemeModeKey  = 'ui_theme_mode';
const _kFontScaleKey  = 'ui_font_scale';

// ─────────────────────────────────────────────
//  State
// ─────────────────────────────────────────────
class AppPrefsState {
  final AppThemeMode themeMode;
  final double fontScale;  // 0.9 – 1.1

  const AppPrefsState({
    this.themeMode  = AppThemeMode.dark,
    this.fontScale   = 1.0,
  });

  Color get accentColor => const Color(0xFF0A84FF);

  AppPrefsState copyWith({
    AppThemeMode? themeMode,
    double? fontScale,
  }) => AppPrefsState(
    themeMode:   themeMode   ?? this.themeMode,
    fontScale:   fontScale   ?? this.fontScale,
  );
}

// ─────────────────────────────────────────────
//  Notifier
// ─────────────────────────────────────────────
class AppPrefsNotifier extends StateNotifier<AppPrefsState> {
  AppPrefsNotifier() : super(const AppPrefsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex   = prefs.getInt(_kThemeModeKey) ?? 0;
    final fontScale   = prefs.getDouble(_kFontScaleKey) ?? 1.0;

    state = AppPrefsState(
      themeMode:   AppThemeMode.values[modeIndex.clamp(0, AppThemeMode.values.length - 1)],
      fontScale:   fontScale.clamp(0.9, 1.1),
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeModeKey,    state.themeMode.index);
    await prefs.setDouble(_kFontScaleKey, state.fontScale);
  }

  // ── Public methods ──────────────────────────
  void toggleTheme() {
    final next = AppThemeMode.values[
      (state.themeMode.index + 1) % AppThemeMode.values.length
    ];
    state = state.copyWith(themeMode: next);
    _save();
  }

  void setTheme(AppThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }

  void setFontScale(double scale) {
    state = state.copyWith(fontScale: scale.clamp(0.9, 1.1));
    _save();
  }
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────
final appPrefsProvider =
    StateNotifierProvider<AppPrefsNotifier, AppPrefsState>(
        (_) => AppPrefsNotifier());

/// Shortcut: just the theme mode (backward compat)
final themeProvider = Provider<AppThemeMode>(
    (ref) => ref.watch(appPrefsProvider).themeMode);

/// Resolved ThemeData
final resolvedThemeProvider = Provider<ThemeData>((ref) {
  final prefs = ref.watch(appPrefsProvider);

  switch (prefs.themeMode) {
    case AppThemeMode.light:
      return CustomThemes.buildLight(accent: prefs.accentColor);
    case AppThemeMode.highContrast:
      return CustomThemes.highContrastTheme;
    case AppThemeMode.dark:
      return AppTheme.buildDark(accent: prefs.accentColor);
  }
});
