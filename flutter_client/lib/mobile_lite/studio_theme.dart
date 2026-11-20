import 'package:flutter/material.dart';

import '../core/theme/tokens.dart' as tokens;

const studioCanvas = Color(0xFF100F18);
const studioSurface = Color(0xFF1B1927);
const studioAccent = Color(0xFFD2BEFF);
const studioInk = Color(0xFFF6F1FF);
const studioMuted = Color(0xFFBEB6CD);
const studioLine = Color(0xFF3B344B);

ThemeData studioTheme(ThemeData base) {
  final colors = base.colorScheme.copyWith(
    brightness: Brightness.dark,
    primary: studioAccent,
    onPrimary: const Color(0xFF211431),
    secondary: studioAccent,
    secondaryContainer: const Color(0xFF35264B),
    onSecondaryContainer: studioInk,
    surface: studioSurface,
    onSurface: studioInk,
    onSurfaceVariant: studioMuted,
    outline: studioMuted,
    outlineVariant: studioLine,
    error: const Color(0xFFFFB4AC),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(tokens.Radius.lg),
  );
  return base.copyWith(
    colorScheme: colors,
    scaffoldBackgroundColor: studioCanvas,
    textTheme: ThemeData.dark().textTheme.apply(
      fontFamily: 'Cairo',
      bodyColor: studioInk,
      displayColor: studioInk,
    ),
    dividerColor: studioLine,
    appBarTheme: const AppBarTheme(
      backgroundColor: studioCanvas,
      foregroundColor: studioInk,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: studioAccent,
        foregroundColor: colors.onPrimary,
        minimumSize: const Size(48, 54),
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: studioInk,
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: studioLine),
        shape: shape,
      ),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(color: studioInk),
      secondaryLabelStyle: const TextStyle(color: studioInk),
      backgroundColor: studioSurface,
      selectedColor: colors.secondaryContainer,
      checkmarkColor: studioAccent,
      side: const BorderSide(color: studioLine),
      padding: const EdgeInsets.symmetric(horizontal: tokens.Spacing.sm),
    ),
  );
}

class StudioLayout extends StatelessWidget {
  const StudioLayout({super.key, required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: children,
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(width: double.infinity, child: footer),
              ),
          ],
        ),
      ),
    ),
  );
}

class StudioProgress extends StatelessWidget {
  const StudioProgress({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    this.progress,
    this.failed = false,
  });

  final String title;
  final String detail;
  final IconData icon;
  final double? progress;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accent = failed ? Theme.of(context).colorScheme.error : studioAccent;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Icon(icon, color: accent, size: 36),
          const SizedBox(height: 20),
          Text(
            title,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            detail,
            style: text.bodyMedium?.copyWith(color: studioMuted, height: 1.65),
          ),
          if (!failed) ...[
            const SizedBox(height: 24),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${(progress! * 100).round()}%',
                  textDirection: TextDirection.ltr,
                  style: text.titleLarge?.copyWith(color: accent),
                ),
              ),
            LinearProgressIndicator(
              value:
                  progress ??
                  (MediaQuery.disableAnimationsOf(context) ? 0 : null),
              minHeight: 5,
              borderRadius: BorderRadius.circular(5),
              color: accent,
              backgroundColor: studioLine,
              semanticsLabel: title,
            ),
          ],
        ],
      ),
    );
  }
}
