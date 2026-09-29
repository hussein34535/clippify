import 'package:flutter/animation.dart' as f;

/// ─────────────────────────────────────────────
/// Design Tokens — Squad-B0 [TokenSmith]
/// ─────────────────────────────────────────────
///
/// CONTRACT: These token classes are the single source of truth for new UI.
/// Existing screens migrate to them GRADUALLY — do not bulk-rewrite working
/// code. New widgets MUST use these constants instead of raw numbers so
/// spacing/rhythm/motion stay consistent app-wide. Pure consts only: zero
/// runtime allocation, safe inside `const` widgets and default params.
///
/// NOTE: [Curves] intentionally shadows Flutter's `Curves`. Files importing
/// both should use `as tokens` or rely on the local declaration winning.

/// Spacing scale (px). Use for padding, gaps, margins.
abstract final class Spacing {
  /// Tight inline gaps (icon↔label).
  static const double xs = 4;

  /// Default compact gap between related controls.
  static const double sm = 8;

  /// Group-internal gap (form fields, chips).
  static const double md = 12;

  /// Standard panel/card padding.
  static const double lg = 16;

  /// Section separation, modal insets.
  static const double xl = 24;

  /// Major layout regions (sidebar gutters, page margins).
  static const double xxl = 32;
}

/// Corner radius scale (px). Mirrors Apple-HIG style radii.
abstract final class Radius {
  /// Inputs, small chips.
  static const double sm = 6;

  /// Buttons, cards (macOS default feel).
  static const double md = 10;

  /// Panels, dialogs.
  static const double lg = 14;

  /// Large sheets, hero surfaces.
  static const double xl = 20;

  /// Full-round pills & avatars.
  static const double pill = 999;
}

/// Motion duration scale (ms). Pick by surface weight, not taste.
abstract final class Durations {
  /// Micro-feedback: hover, ripple, checkbox.
  static const Duration fast150 = Duration(milliseconds: 150);

  /// Standard control transitions.
  static const Duration base200 = Duration(milliseconds: 200);

  /// Panels expanding, tooltips, snackbar.
  static const Duration slow300 = Duration(milliseconds: 300);

  /// Page/screen-level transitions only.
  static const Duration page250ms = Duration(milliseconds: 250);
}

/// Motion curve vocabulary. Two curves, no freelancing.
abstract final class Curves {
  /// Default for everything entering/moving on screen.
  static const f.Curve standard = f.Curves.easeOutCubic;

  /// Attention-grabbing overshoot (FAB pop, success toast).
  static const f.Curve emphasized = f.Curves.easeOutBack;
}
