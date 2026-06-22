import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
//  AppColors – Apple macOS–style dark palette
// ─────────────────────────────────────────────
class AppColors {
  // ── Backgrounds (Pitch Black & Deep Dark UI) ──────
  static const Color background      = Color(0xFF090909); // Ultra-dark canvas background
  static const Color surface         = Color(0xFF121214); // Deep dark surface
  static const Color surfaceVariant  = Color(0xFF1E1E22); // Lighter dark surface for hovered / active states
  static const Color card            = Color(0xFF121214);
  static const Color overlay         = Color(0xFF090909);

  // ── Accent (default blue – overridable) ─────
  static const Color primary         = Color(0xFF0A84FF); // systemBlue
  static const Color primaryVariant  = Color(0xFF0070F3);
  static const Color secondary       = Color(0xFF30D158); // systemGreen
  static const Color accent          = Color(0xFF0A84FF);
  static const Color destructive     = Color(0xFFFF453A); // systemRed
  static const Color warning         = Color(0xFFFFD60A); // systemYellow

  // ── Text ────────────────────────────────────
  static const Color textPrimary     = Color(0xFFFFFFFF);
  static const Color textSecondary   = Color(0x99EBEBF5); // 60% white
  static const Color textMuted       = Color(0x4DEBEBF5); // 30% white
  static const Color textDisabled    = Color(0x26FFFFFF); // 15% white

  // ── Borders & Dividers (Sleek Apple style borders) ──
  static const Color border          = Color(0x1BFFFFFF); // 10.5% white separator
  static const Color borderSubtle    = Color(0x0FFFFFFF); // 6% white line
  static const Color divider         = Color(0x0FFFFFFF);

  // ── Timeline ────────────────────────────────
  static const Color timelineTrack        = Color(0xFF121214);
  static const Color timelineClip         = Color(0xFF252528);
  static const Color timelineClipSelected = Color(0xFF0A84FF);
}

// ─────────────────────────────────────────────
//  AppRadius – Apple HIG corner radii
// ─────────────────────────────────────────────
class AppRadius {
  static const double xs   = 4.0;
  static const double sm   = 6.0;
  static const double md   = 10.0;  // macOS button default
  static const double lg   = 12.0;
  static const double xl   = 16.0;
  static const double xxl  = 20.0;
  static const double pill  = 100.0;
}

// ─────────────────────────────────────────────
//  AppShadows – subtle elevation
// ─────────────────────────────────────────────
class AppShadows {
  static List<BoxShadow> get card => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.35),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get panel => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.25),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get button => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.20),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];
}

// ─────────────────────────────────────────────
class AppButtonStyle {
  /// Filled primary button (blue pill)
  static ButtonStyle filled({Color? color}) => ElevatedButton.styleFrom(
    backgroundColor: color ?? AppColors.primary,
    foregroundColor: Colors.white,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'], inherit: false),
  );

  /// Ghost / outline button
  static ButtonStyle outlined({Color? color}) => OutlinedButton.styleFrom(
    foregroundColor: color ?? AppColors.primary,
    side: BorderSide(color: (color ?? AppColors.primary).withValues(alpha: 0.5)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'], inherit: false),
  );

  /// Subtle text button
  static ButtonStyle text({Color? color}) => TextButton.styleFrom(
    foregroundColor: color ?? AppColors.primary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'], inherit: false),
  );

  /// Icon button (toolbar)
  static ButtonStyle iconToolbar() => IconButton.styleFrom(
    foregroundColor: AppColors.textSecondary,
    backgroundColor: Colors.transparent,
    hoverColor: AppColors.surfaceVariant,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
    padding: const EdgeInsets.all(6),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

// ─────────────────────────────────────────────
//  AppDecorations – reusable BoxDecoration
// ─────────────────────────────────────────────
class AppDecorations {
  /// Glass-effect card (Apple vibrancy style)
  static BoxDecoration get card => BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.xl),
    border: Border.all(color: AppColors.border),
    boxShadow: AppShadows.card,
  );

  /// Panel / sidebar container
  static BoxDecoration get panel => BoxDecoration(
    color: AppColors.surface,
    border: const Border(right: BorderSide(color: AppColors.border)),
  );

  static BoxDecoration get panelLeft => BoxDecoration(
    color: AppColors.surface,
    border: const Border(left: BorderSide(color: AppColors.border)),
  );

  /// Toolbar bar
  static BoxDecoration get toolbar => BoxDecoration(
    color: AppColors.surface,
    border: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
  );

  /// Input field
  static BoxDecoration inputDecoration({bool focused = false, Color? accent}) =>
      BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: focused ? (accent ?? AppColors.primary) : AppColors.border,
          width: focused ? 1.5 : 1,
        ),
      );

  /// Chip / tag
  static BoxDecoration chip({Color? color}) => BoxDecoration(
    color: (color ?? AppColors.primary).withValues(alpha: 0.15),
    borderRadius: BorderRadius.circular(AppRadius.pill),
    border: Border.all(color: (color ?? AppColors.primary).withValues(alpha: 0.35)),
  );
}

// ─────────────────────────────────────────────
//  AppTheme
// ─────────────────────────────────────────────
enum AppThemeMode { dark, light, highContrast }

class AppTheme {
  /// Build ThemeData for a given accent color
  static ThemeData buildDark({Color accent = AppColors.primary}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: accent,
      cardColor: AppColors.card,
      dividerColor: AppColors.divider,

      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),

      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.bold, fontFamily: 'Outfit', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'], letterSpacing: -0.5),
        headlineMedium: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Outfit', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma'], letterSpacing: -0.3),
        titleLarge: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w500, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodySmall: TextStyle(color: AppColors.textMuted, fontSize: 11, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        labelLarge: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        labelMedium: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 10, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        iconTheme: IconThemeData(color: AppColors.textSecondary, size: 18),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(style: AppButtonStyle.filled()),
      outlinedButtonTheme: OutlinedButtonThemeData(style: AppButtonStyle.outlined()),
      textButtonTheme: TextButtonThemeData(style: AppButtonStyle.text()),

      iconButtonTheme: IconButtonThemeData(style: AppButtonStyle.iconToolbar()),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: AppColors.surfaceVariant,
        thumbColor: Colors.white,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackHeight: 3,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : AppColors.surfaceVariant),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accent : AppColors.surfaceVariant),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        side: const BorderSide(color: AppColors.border),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.borderSubtle,
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        waitDuration: const Duration(milliseconds: 600),
        verticalOffset: 16,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(AppColors.surfaceVariant),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.border),
        ),
        elevation: 8,
        shadowColor: Colors.black54,
        textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          side: const BorderSide(color: AppColors.border),
        ),
        elevation: 24,
        shadowColor: Colors.black87,
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceVariant,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Legacy helper – kept for backward compat
  static ThemeData get darkTheme => buildDark();
}

// ─────────────────────────────────────────────
//  Light & High-Contrast themes
// ─────────────────────────────────────────────
class CustomThemes {
  static ThemeData buildLight({Color accent = const Color(0xFF007AFF)}) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      primaryColor: accent,
      colorScheme: ColorScheme.light(
        primary: accent,
        secondary: const Color(0xFF34C759),
        surface: Colors.white,
        error: const Color(0xFFFF3B30),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: const Color(0xFF1C1C1E),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Color(0xFF1C1C1E), fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodyLarge: TextStyle(color: Color(0xFF1C1C1E), fontSize: 14, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodyMedium: TextStyle(color: Color(0xFF6C6C70), fontSize: 13, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
        bodySmall: TextStyle(color: Color(0xFF8E8E93), fontSize: 11, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      ),
      dividerColor: const Color(0xFFD1D1D6),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
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
      bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
      bodyMedium: TextStyle(color: Colors.yellowAccent, fontFamily: 'Inter', fontFamilyFallback: ['Segoe UI', 'Arial', 'Tahoma']),
    ),
    dividerColor: Colors.white24,
  );
}
