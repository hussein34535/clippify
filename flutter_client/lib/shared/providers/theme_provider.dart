import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';

export '../../core/theme/app_theme.dart' show AppThemeMode;

// ─────────────────────────────────────────────
//  Accent color presets
// ─────────────────────────────────────────────
const List<({String name, Color color})> kAccentColors = [
  (name: 'أزرق',   color: Color(0xFF0A84FF)),
  (name: 'بنفسجي', color: Color(0xFFBF5AF2)),
  (name: 'وردي',   color: Color(0xFFFF375F)),
  (name: 'برتقالي',color: Color(0xFFFF9F0A)),
  (name: 'أخضر',  color: Color(0xFF30D158)),
  (name: 'سماوي', color: Color(0xFF32ADE6)),
  (name: 'أبيض',  color: Color(0xFFFFFFFF)),
];

// ─────────────────────────────────────────────
//  Prefs keys
// ─────────────────────────────────────────────
const _kThemeModeKey  = 'ui_theme_mode';
const _kAccentKey     = 'ui_accent_color';
const _kFontScaleKey  = 'ui_font_scale';
const _kCompactUIKey  = 'ui_compact_mode';
const _kThemePresetKey = 'ui_theme_preset';

// ─────────────────────────────────────────────
//  State
// ─────────────────────────────────────────────
class AppPrefsState {
  final AppThemeMode themeMode;
  final Color accentColor;
  final double fontScale;  // 0.85 – 1.2
  final bool compactUI;
  final String? themePresetName; // from ThemePreset presets

  const AppPrefsState({
    this.themeMode  = AppThemeMode.dark,
    this.accentColor = const Color(0xFF0A84FF),
    this.fontScale   = 1.0,
    this.compactUI   = false,
    this.themePresetName,
  });

  AppPrefsState copyWith({
    AppThemeMode? themeMode,
    Color? accentColor,
    double? fontScale,
    bool? compactUI,
    String? themePresetName,
  }) => AppPrefsState(
    themeMode:   themeMode   ?? this.themeMode,
    accentColor: accentColor ?? this.accentColor,
    fontScale:   fontScale   ?? this.fontScale,
    compactUI:   compactUI   ?? this.compactUI,
    themePresetName: themePresetName ?? this.themePresetName,
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
    final accentInt   = prefs.getInt(_kAccentKey)    ?? 0xFF0A84FF;
    final fontScale   = prefs.getDouble(_kFontScaleKey) ?? 1.0;
    final compactUI   = prefs.getBool(_kCompactUIKey)   ?? false;
    final themePreset = prefs.getString(_kThemePresetKey);

    state = AppPrefsState(
      themeMode:   AppThemeMode.values[modeIndex.clamp(0, AppThemeMode.values.length - 1)],
      accentColor: Color(accentInt),
      fontScale:   fontScale.clamp(0.85, 1.2),
      compactUI:   compactUI,
      themePresetName: themePreset,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeModeKey,    state.themeMode.index);
    await prefs.setInt(_kAccentKey,       state.accentColor.toARGB32());
    await prefs.setDouble(_kFontScaleKey, state.fontScale);
    await prefs.setBool(_kCompactUIKey,   state.compactUI);
    if (state.themePresetName != null) {
      await prefs.setString(_kThemePresetKey, state.themePresetName!);
    } else {
      await prefs.remove(_kThemePresetKey);
    }
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

  void setAccent(Color color) {
    state = state.copyWith(accentColor: color);
    _save();
  }

  void setFontScale(double scale) {
    state = state.copyWith(fontScale: scale.clamp(0.85, 1.2));
    _save();
  }

  void setCompactUI(bool compact) {
    state = state.copyWith(compactUI: compact);
    _save();
  }

  void setThemePreset(String? name) {
    state = state.copyWith(themePresetName: name);
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

  // If a ThemePreset is active, use it directly
  if (prefs.themePresetName != null) {
    final themePreset = _findThemePreset(prefs.themePresetName!);
    if (themePreset != null) return themePreset;
  }

  switch (prefs.themeMode) {
    case AppThemeMode.light:
      return CustomThemes.buildLight(accent: prefs.accentColor);
    case AppThemeMode.highContrast:
      return CustomThemes.highContrastTheme;
    case AppThemeMode.dark:
      return AppTheme.buildDark(accent: prefs.accentColor);
  }
});

/// Find a ThemePreset by name (lazy import to avoid circular dependency)
ThemeData? _findThemePreset(String name) {
  // ThemePreset is in features/ui/professional_ui.dart
  // We import it lazily via a simple lookup
  final presets = _kThemePresetMap[name];
  return presets;
}

/// Hardcoded presets to avoid import complexity
final _kThemePresetMap = <String, ThemeData>{
  'ClipAI Dark': _clipaiDark,
  'ClipAI Light': _clipaiLight,
  'Midnight': _midnight,
  'Sunset': _sunset,
  'Forest': _forest,
  'Ocean': _ocean,
};

final _clipaiDark = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF7C6AF7),
  scaffoldBackgroundColor: const Color(0xFF0A0A0D),
  useMaterial3: true,
);

final _clipaiLight = ThemeData(
  brightness: Brightness.light,
  colorSchemeSeed: const Color(0xFF7C6AF7),
  scaffoldBackgroundColor: const Color(0xFFFFFFFF),
  useMaterial3: true,
);

final _midnight = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF00D4FF),
  scaffoldBackgroundColor: const Color(0xFF05080F),
  useMaterial3: true,
);

final _sunset = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFFFF6B6B),
  scaffoldBackgroundColor: const Color(0xFF0F0A0E),
  useMaterial3: true,
);

final _forest = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF10B981),
  scaffoldBackgroundColor: const Color(0xFF070D09),
  useMaterial3: true,
);

final _ocean = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFF38BDF8),
  scaffoldBackgroundColor: const Color(0xFF020617),
  useMaterial3: true,
);

