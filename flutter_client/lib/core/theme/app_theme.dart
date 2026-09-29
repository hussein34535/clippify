import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  Clippify Design System — Cupertino-inspired (iOS 17)
//  Dark-first (pro NLE default), light theme included.
//
//  Everything visual resolves to this file: colors, radii,
//  hairline borders, soft shadows, iOS type scale and the
//  Material sub-themes that keep widget defaults on-system.
// ─────────────────────────────────────────────────────────────

/// 4/8/12/16/24 spacing grid (iOS points).
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// iOS palette — dark (default) values. Light values live in
/// [CustomThemes].
class AppColors {
  // ── Backgrounds (deep systemGray ladder) ──────────────────
  static const Color background     = Color(0xFF0A0A0C); // canvas
  static const Color surface        = Color(0xFF1C1C1E); // systemGray6 dark
  static const Color surfaceVariant = Color(0xFF2C2C2E); // systemGray5 dark
  static const Color surfaceElevated = Color(0xFF2C2C2E);
  static const Color surfaceOverlay = Color(0xFF3A3A3C); // systemGray4 dark
  static const Color card           = Color(0xFF1C1C1E);
  static const Color overlay        = Color(0xFF0A0A0C);

  // ── Accents ───────────────────────────────────────────────
  static const Color primary        = Color(0xFF0A84FF); // systemBlue dark
  static const Color primaryVariant = Color(0xFF007AFF); // systemBlue light
  static const Color accent         = Color(0xFF0A84FF);
  static const Color secondary      = Color(0xFF30D158); // systemGreen dark
  static const Color destructive    = Color(0xFFFF453A); // systemRed dark
  static const Color warning        = Color(0xFFFF9F0A); // systemOrange dark
  static const Color yellow         = Color(0xFFFFD60A); // systemYellow dark
  static const Color indigo         = Color(0xFF5E5CE6); // systemIndigo dark
  static const Color teal           = Color(0xFF64D2FF); // systemTeal dark
  static const Color pink           = Color(0xFFFF375F); // systemPink dark

  // ── Text ─────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFFFFFFF);
  static const Color textSecondary  = Color(0x99EBEBF5); // 60% label
  static const Color textMuted      = Color(0x4DEBEBF5); // 30% label
  static const Color textDisabled   = Color(0x26FFFFFF);

  // ── Hairline borders (0.5px white @ 8%) ──────────────────
  static const Color border         = Color(0x14FFFFFF);
  static const Color borderSubtle   = Color(0x0FFFFFFF);
  static const Color divider        = Color(0x14FFFFFF);

  // ── Timeline ─────────────────────────────────────────────
  static const Color timelineTrack        = Color(0xFF141416);
  static const Color timelineClip         = Color(0xFF23252B);
  static const Color timelineClipSelected = Color(0xFF0A84FF);
}

/// Light-mode counterpart used by [CustomThemes.buildLight].
class AppColorsLight {
  static const Color background     = Color(0xFFF2F2F7);
  static const Color surface        = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFE5E5EA);
  static const Color surfaceOverlay = Color(0xFFD1D1D6);
  static const Color primary        = Color(0xFF007AFF);
  static const Color secondary      = Color(0xFF34C759);
  static const Color destructive    = Color(0xFFFF3B30);
  static const Color warning        = Color(0xFFFF9500);
  static const Color yellow         = Color(0xFFFFCC00);
  static const Color textPrimary    = Color(0xFF1C1C1E);
  static const Color textSecondary  = Color(0x993C3C43); // 60% label
  static const Color textMuted      = Color(0x4D3C3C43); // 30% label
  static const Color border         = Color(0x243C3C43); // separator
  static const Color divider        = Color(0x243C3C43);
}

// ─────────────────────────────────────────────────────────────
//  AppRadius — "continuous corner" feel
// ─────────────────────────────────────────────────────────────
class AppRadius {
  static const double xs   = 6.0;   // tiny chips
  static const double sm   = 8.0;   // timeline clips, small tiles
  static const double md   = 12.0;  // input fields, player frame
  static const double lg   = 16.0;  // cards
  static const double xl   = 20.0;  // dialogs, hero surfaces
  static const double xxl  = 20.0;
  static const double toast = 14.0;
  static const double pill  = 100.0;
}

// ─────────────────────────────────────────────────────────────
//  AppShadows — very soft elevation (no hard drop-offs)
// ─────────────────────────────────────────────────────────────
class AppShadows {
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.22),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get panel => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.14),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get button => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get modal => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.45),
      blurRadius: 48,
      offset: const Offset(0, 20),
    ),
  ];

  /// Soft blue glow for selected timeline clips.
  static List<BoxShadow> selection(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.35),
      blurRadius: 12,
      offset: const Offset(0, 0),
      spreadRadius: -2,
    ),
  ];
}

// ─────────────────────────────────────────────────────────────
//  AppTypography — iOS type scale (system font stack)
// ─────────────────────────────────────────────────────────────
class AppTypography {
  // System stack: SF on Apple platforms, Segoe UI elsewhere.
  // Arabic glyphs resolve through the Cairo family applied at
  // the MaterialApp level.
  static const List<String> fallbacks = ['Segoe UI', 'Arial', 'Tahoma'];

  static const TextStyle largeTitle = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5,
      color: AppColors.textPrimary, fontFamilyFallback: fallbacks);
  static const TextStyle title1 = TextStyle(
      fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3,
      color: AppColors.textPrimary, fontFamilyFallback: fallbacks);
  static const TextStyle headline = TextStyle(
      fontSize: 17, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, fontFamilyFallback: fallbacks);
  static const TextStyle body = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400,
      color: AppColors.textPrimary, fontFamilyFallback: fallbacks);
  static const TextStyle callout = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w400,
      color: AppColors.textSecondary, fontFamilyFallback: fallbacks);
  static const TextStyle subheadline = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600,
      color: AppColors.textPrimary, fontFamilyFallback: fallbacks);
  static const TextStyle footnote = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w400,
      color: AppColors.textSecondary, fontFamilyFallback: fallbacks);
  static const TextStyle caption1 = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400,
      color: AppColors.textSecondary, fontFamilyFallback: fallbacks);
  static const TextStyle caption2 = TextStyle(
      fontSize: 11, fontWeight: FontWeight.w500,
      color: AppColors.textMuted, fontFamilyFallback: fallbacks);
  static const TextStyle mono = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'monospace',
      letterSpacing: 0.3, color: AppColors.textPrimary);
}

// ─────────────────────────────────────────────────────────────
//  AppButtonStyle — pill buttons
// ─────────────────────────────────────────────────────────────
class AppButtonStyle {
  static const TextStyle _label = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks);

  /// Filled primary button (blue pill).
  static ButtonStyle filled({Color? color}) => ElevatedButton.styleFrom(
    backgroundColor: color ?? AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: _label,
  );

  /// Destructive filled (red pill).
  static ButtonStyle destructive() => filled(color: AppColors.destructive);

  /// Ghost / outline button (pill).
  static ButtonStyle outlined({Color? color}) => OutlinedButton.styleFrom(
    foregroundColor: color ?? AppColors.primary,
    side: BorderSide(color: (color ?? AppColors.primary).withValues(alpha: 0.45)),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: _label,
  );

  /// Subtle tinted text button.
  static ButtonStyle text({Color? color}) => TextButton.styleFrom(
    foregroundColor: color ?? AppColors.primary,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: _label,
  );

  /// Icon button (toolbar).
  static ButtonStyle iconToolbar() => IconButton.styleFrom(
    foregroundColor: AppColors.textSecondary,
    backgroundColor: Colors.transparent,
    hoverColor: AppColors.surfaceVariant,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
    padding: const EdgeInsets.all(6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

// ─────────────────────────────────────────────────────────────
//  AppDecorations – reusable BoxDecoration
// ─────────────────────────────────────────────────────────────
class AppDecorations {
  /// iOS card: surface fill, 16px radius, hairline border, soft shadow.
  static BoxDecoration get card => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: AppColors.border, width: 0.5),
    boxShadow: AppShadows.panel,
  );

  /// Panel / sidebar container.
  static BoxDecoration get panel => BoxDecoration(
    color: AppColors.surface,
    border: const Border(right: BorderSide(color: AppColors.border, width: 0.5)),
  );

  static BoxDecoration get panelLeft => BoxDecoration(
    color: AppColors.surface,
    border: const Border(left: BorderSide(color: AppColors.border, width: 0.5)),
  );

  /// Toolbar bar.
  static BoxDecoration get toolbar => BoxDecoration(
    color: AppColors.surface,
    border: const Border(bottom: BorderSide(color: AppColors.borderSubtle, width: 0.5)),
  );

  /// Input field — 12px radius, hairline border.
  static BoxDecoration inputDecoration({bool focused = false, Color? accent}) =>
      BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: focused ? (accent ?? AppColors.primary) : AppColors.border,
          width: focused ? 1.5 : 0.5,
        ),
      );

  /// Chip / tag — pill.
  static BoxDecoration chip({Color? color}) => BoxDecoration(
    color: (color ?? AppColors.primary).withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(AppRadius.pill),
    border: Border.all(color: (color ?? AppColors.primary).withValues(alpha: 0.35), width: 0.5),
  );
}

// ─────────────────────────────────────────────────────────────
//  AppTheme
// ─────────────────────────────────────────────────────────────
enum AppThemeMode { dark, light, highContrast }

class AppTheme {
  /// Motion vocabulary — 150–250ms, easeOutCubic.
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animBase = Duration(milliseconds: 200);
  static const Duration animSlow = Duration(milliseconds: 250);
  static const Curve animCurve = Curves.easeOutCubic;

  /// Build ThemeData for a given accent color.
  static ThemeData buildDark({Color accent = AppColors.primary}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: accent,
      cardColor: AppColors.card,
      dividerColor: AppColors.divider,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.standard,

      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        surfaceContainerHighest: AppColors.surfaceVariant,
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, fontFamilyFallback: AppTypography.fallbacks),
        headlineMedium: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, fontFamilyFallback: AppTypography.fallbacks),
        headlineSmall: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        titleLarge: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500, fontFamilyFallback: AppTypography.fallbacks),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontFamilyFallback: AppTypography.fallbacks),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
        bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamilyFallback: AppTypography.fallbacks),
        labelLarge: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        labelMedium: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500, fontFamilyFallback: AppTypography.fallbacks),
        labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 10, fontFamilyFallback: AppTypography.fallbacks),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        iconTheme: IconThemeData(color: AppColors.textPrimary, size: 20),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(style: AppButtonStyle.filled(color: accent)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: AppButtonStyle.outlined(color: accent)),
      textButtonTheme: TextButtonThemeData(style: AppButtonStyle.text(color: accent)),

      iconButtonTheme: IconButtonThemeData(style: AppButtonStyle.iconToolbar()),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: AppColors.surfaceOverlay,
        // Disabled sliders must not look interactive: an explicit
        // activeTrackColor above would otherwise override Flutter's
        // disabled default and paint the track in full accent blue.
        disabledActiveTrackColor: accent.withValues(alpha: 0.28),
        disabledInactiveTrackColor: AppColors.surfaceOverlay,
        disabledThumbColor: AppColors.textMuted,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 4,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? AppColors.secondary : AppColors.surfaceOverlay),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : AppColors.surfaceVariant),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: AppColors.border),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamilyFallback: AppTypography.fallbacks),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.borderSubtle,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
        space: 1,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.circular(AppRadius.xs),
          boxShadow: AppShadows.panel,
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontFamilyFallback: AppTypography.fallbacks),
        waitDuration: const Duration(milliseconds: 600),
        verticalOffset: 16,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.surfaceOverlay),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        elevation: 24,
        shadowColor: Colors.black54,
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        elevation: 24,
        shadowColor: Colors.black87,
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariant,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontFamilyFallback: AppTypography.fallbacks),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.toast)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Legacy helper – kept for backward compat
  static ThemeData get darkTheme => buildDark();
}

// ─────────────────────────────────────────────────────────────
//  Light & High-Contrast themes
// ─────────────────────────────────────────────────────────────
class CustomThemes {
  static ThemeData buildLight({Color accent = AppColorsLight.primary}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColorsLight.background,
      primaryColor: accent,
      cardColor: AppColorsLight.surface,
      dividerColor: AppColorsLight.divider,
      splashFactory: NoSplash.splashFactory,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: AppColorsLight.secondary,
        surface: AppColorsLight.surface,
        surfaceContainerHighest: AppColorsLight.surfaceVariant,
        error: AppColorsLight.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColorsLight.textPrimary,
        onSurfaceVariant: AppColorsLight.textSecondary,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColorsLight.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, fontFamilyFallback: AppTypography.fallbacks),
        headlineMedium: TextStyle(color: AppColorsLight.textPrimary, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, fontFamilyFallback: AppTypography.fallbacks),
        headlineSmall: TextStyle(color: AppColorsLight.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        titleLarge: TextStyle(color: AppColorsLight.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        bodyLarge: TextStyle(color: AppColorsLight.textPrimary, fontSize: 15, fontFamilyFallback: AppTypography.fallbacks),
        bodyMedium: TextStyle(color: AppColorsLight.textSecondary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
        bodySmall: TextStyle(color: AppColorsLight.textMuted, fontSize: 11, fontFamilyFallback: AppTypography.fallbacks),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColorsLight.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColorsLight.border, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColorsLight.border, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 4,
        thumbColor: Colors.white,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColorsLight.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColorsLight.border, width: 0.5),
        ),
        titleTextStyle: const TextStyle(color: AppColorsLight.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamilyFallback: AppTypography.fallbacks),
        contentTextStyle: const TextStyle(color: AppColorsLight.textSecondary, fontSize: 13, fontFamilyFallback: AppTypography.fallbacks),
      ),
    );
  }

  static ThemeData get lightTheme => buildLight();

  static ThemeData get highContrastTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.black,
    primaryColor: Colors.yellowAccent,
    colorScheme: const ColorScheme.dark(
      primary: Colors.yellowAccent,
      secondary: Colors.cyanAccent,
      surface: Color(0xFF1C1C1C),
      error: Colors.redAccent,
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      onSurface: Colors.white,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white, fontFamilyFallback: AppTypography.fallbacks),
      bodyMedium: TextStyle(color: Colors.yellowAccent, fontFamilyFallback: AppTypography.fallbacks),
    ),
    dividerColor: Colors.white24,
  );
}
