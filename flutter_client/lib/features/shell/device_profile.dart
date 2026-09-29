import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Breakpoint below which we show the simplified mobile shell.
const double kCompactBreakpoint = 600;

/// Pure width check (logical pixels).
bool isCompactWidth(double logicalWidth) => logicalWidth < kCompactBreakpoint;

/// Context-based helper: true on phones (<600 logical px wide).
bool isCompact(BuildContext context) =>
    isCompactWidth(MediaQuery.sizeOf(context).width);

/// Watches window/view metrics and exposes whether we are in compact mode.
class CompactModeNotifier extends StateNotifier<bool> with WidgetsBindingObserver {
  CompactModeNotifier() : super(_computeCurrent()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static bool _computeCurrent() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final dpr = view.devicePixelRatio;
    if (view.physicalSize == Size.zero || dpr <= 0) return false;
    return isCompactWidth(view.physicalSize.width / dpr);
  }

  @override
  void didChangeMetrics() {
    state = _computeCurrent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// True when the app window is phone-sized (<600dp). Rotation-aware.
final compactModeProvider =
    StateNotifierProvider<CompactModeNotifier, bool>((ref) => CompactModeNotifier());
