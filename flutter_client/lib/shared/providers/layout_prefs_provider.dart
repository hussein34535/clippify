import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-customizable layout settings.
///
/// These control the visual spacing of the home screen layout — panel
/// widths, gaps, corner radii, header height. Stored in SharedPreferences
/// so they persist across restarts.
class LayoutPrefsState {
  /// Workspace padding around all panels (px). Default 6.
  final double workspacePadding;

  /// Gap between panels (px). Default 6.
  final double panelGap;

  /// Corner radius for all panels (px). Default 8.
  final double panelRadius;

  /// Border width for panels (px). Default 1.
  final double panelBorderWidth;

  /// Header height (px). Default 56.
  final double headerHeight;

  /// Left panel (Media Browser) width as fraction of window. Default 0.18.
  final double leftPanelFraction;

  /// Right panel (Inspector) width as fraction of window. Default 0.22.
  final double rightPanelFraction;

  /// Bottom row (Timeline) height as fraction of window. Default 0.40.
  final double timelineFraction;

  /// Clip minimum width in timeline (px). Default 40.
  final double clipMinWidth;

  /// Clip resize handle hit area width (px). Default 12.
  final double resizeHandleWidth;

  const LayoutPrefsState({
    this.workspacePadding = 6.0,
    this.panelGap = 6.0,
    this.panelRadius = 8.0,
    this.panelBorderWidth = 1.0,
    this.headerHeight = 56.0,
    this.leftPanelFraction = 0.18,
    this.rightPanelFraction = 0.22,
    this.timelineFraction = 0.40,
    this.clipMinWidth = 40.0,
    this.resizeHandleWidth = 12.0,
  });

  LayoutPrefsState copyWith({
    double? workspacePadding,
    double? panelGap,
    double? panelRadius,
    double? panelBorderWidth,
    double? headerHeight,
    double? leftPanelFraction,
    double? rightPanelFraction,
    double? timelineFraction,
    double? clipMinWidth,
    double? resizeHandleWidth,
  }) => LayoutPrefsState(
    workspacePadding: workspacePadding ?? this.workspacePadding,
    panelGap: panelGap ?? this.panelGap,
    panelRadius: panelRadius ?? this.panelRadius,
    panelBorderWidth: panelBorderWidth ?? this.panelBorderWidth,
    headerHeight: headerHeight ?? this.headerHeight,
    leftPanelFraction: leftPanelFraction ?? this.leftPanelFraction,
    rightPanelFraction: rightPanelFraction ?? this.rightPanelFraction,
    timelineFraction: timelineFraction ?? this.timelineFraction,
    clipMinWidth: clipMinWidth ?? this.clipMinWidth,
    resizeHandleWidth: resizeHandleWidth ?? this.resizeHandleWidth,
  );

  /// Reset to defaults.
  factory LayoutPrefsState.defaultValues() => const LayoutPrefsState();
}

class LayoutPrefsNotifier extends StateNotifier<LayoutPrefsState> {
  LayoutPrefsNotifier() : super(const LayoutPrefsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = LayoutPrefsState(
      workspacePadding: prefs.getDouble('layout_workspace_padding') ?? 6.0,
      panelGap: prefs.getDouble('layout_panel_gap') ?? 6.0,
      panelRadius: prefs.getDouble('layout_panel_radius') ?? 8.0,
      panelBorderWidth: prefs.getDouble('layout_panel_border_width') ?? 1.0,
      headerHeight: prefs.getDouble('layout_header_height') ?? 56.0,
      leftPanelFraction: prefs.getDouble('layout_left_fraction') ?? 0.18,
      rightPanelFraction: prefs.getDouble('layout_right_fraction') ?? 0.22,
      timelineFraction: prefs.getDouble('layout_timeline_fraction') ?? 0.40,
      clipMinWidth: prefs.getDouble('layout_clip_min_width') ?? 40.0,
      resizeHandleWidth: prefs.getDouble('layout_resize_handle_width') ?? 12.0,
    );
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('layout_workspace_padding', state.workspacePadding);
    await prefs.setDouble('layout_panel_gap', state.panelGap);
    await prefs.setDouble('layout_panel_radius', state.panelRadius);
    await prefs.setDouble('layout_panel_border_width', state.panelBorderWidth);
    await prefs.setDouble('layout_header_height', state.headerHeight);
    await prefs.setDouble('layout_left_fraction', state.leftPanelFraction);
    await prefs.setDouble('layout_right_fraction', state.rightPanelFraction);
    await prefs.setDouble('layout_timeline_fraction', state.timelineFraction);
    await prefs.setDouble('layout_clip_min_width', state.clipMinWidth);
    await prefs.setDouble('layout_resize_handle_width', state.resizeHandleWidth);
  }

  void setWorkspacePadding(double v) { state = state.copyWith(workspacePadding: v.clamp(0, 24)); _save(); }
  void setPanelGap(double v) { state = state.copyWith(panelGap: v.clamp(0, 16)); _save(); }
  void setPanelRadius(double v) { state = state.copyWith(panelRadius: v.clamp(0, 24)); _save(); }
  void setPanelBorderWidth(double v) { state = state.copyWith(panelBorderWidth: v.clamp(0, 4)); _save(); }
  void setHeaderHeight(double v) { state = state.copyWith(headerHeight: v.clamp(40, 80)); _save(); }
  void setLeftPanelFraction(double v) { state = state.copyWith(leftPanelFraction: v.clamp(0.10, 0.40)); _save(); }
  void setRightPanelFraction(double v) { state = state.copyWith(rightPanelFraction: v.clamp(0.15, 0.45)); _save(); }
  void setTimelineFraction(double v) { state = state.copyWith(timelineFraction: v.clamp(0.20, 0.70)); _save(); }
  void setClipMinWidth(double v) { state = state.copyWith(clipMinWidth: v.clamp(20, 200)); _save(); }
  void setResizeHandleWidth(double v) { state = state.copyWith(resizeHandleWidth: v.clamp(4, 24)); _save(); }

  void resetToDefaults() {
    state = const LayoutPrefsState();
    _save();
  }
}

final layoutPrefsProvider =
    StateNotifierProvider<LayoutPrefsNotifier, LayoutPrefsState>(
        (_) => LayoutPrefsNotifier());
