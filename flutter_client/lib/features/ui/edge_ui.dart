import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// -------------------------------------------
//  1. EdgeTheme � Professional Design System
//     Apple + DaVinci Resolve Dark
// -------------------------------------------
class EdgeTheme {
  static const Color canvas        = Color(0xFF000000);
  static const Color panelBg       = Color(0xFF1C1C1E);
  static const Color toolbar       = Color(0xFF2C2C2E);
  static const Color accent        = Color(0xFF0A84FF);
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x8EFFFFFF);
  static const Color divider       = Color(0x1FFFFFFF);

  static const Color timelineBg    = Color(0xFF121214);
  static const Color trackBg       = Color(0xFF1C1C1E);
  static const Color clipVideo     = Color(0xFF4B7BFF);
  static const Color clipAudio     = Color(0xFF32D74B);
  static const Color clipOverlay   = Color(0xFFFF9F0A);
  static const Color clipText      = Color(0xFFFF375F);
  static const Color playhead      = Color(0xFFFFFFFF);
  static const Color snapLine      = Color(0xFFFF9500);

  static const Color success       = Color(0xFF32D74B);
  static const Color warning       = Color(0xFFFF9F0A);
  static const Color error         = Color(0xFFFF453A);
  static const Color info          = Color(0xFF0A84FF);

  static const Color surfaceElevated  = Color(0xFF2C2C2E);
  static const Color surfaceOverlay   = Color(0xFF38383A);
  static const Color border           = Color(0x4DFFFFFF);
  static const Color menuBar      = Color(0xFF1C1C1E);
  static const Color menuBarText  = Color(0xFFE5E5EA);
  static const Color statusBar    = Color(0xFF1C1C1E);

  static const Color workAreaBar   = Color(0x40FF9500);
  static const Color workAreaBorder = Color(0xFFFF9500);

  static const double radiusXs  = 2.0;
  static const double radiusSm  = 4.0;
  static const double radiusMd  = 6.0;
  static const double radiusLg  = 8.0;
  static const double radiusXl  = 12.0;

  static BoxDecoration panelDecoration({Color? color, double? radius, Color? borderColor}) => BoxDecoration(
    color: color ?? panelBg,
    borderRadius: BorderRadius.circular(radius ?? radiusSm),
    border: Border.all(color: borderColor ?? divider),
  );

  static BoxDecoration get toolbarDecoration => BoxDecoration(
    color: toolbar,
    border: Border.all(color: divider),
    borderRadius: BorderRadius.circular(radiusXs),
  );
}
// -------------------------------------------
//  2. EdgeIcons � Consistent Icon Constants
// -------------------------------------------
class EdgeIcons {
  static const IconData mediaBin     = Icons.folder_rounded;
  static const IconData mediaFile    = Icons.movie_rounded;
  static const IconData mediaImage   = Icons.image_rounded;
  static const IconData mediaAudio   = Icons.audio_file_rounded;
  static const IconData mediaImport  = Icons.file_download_rounded;

  static const IconData split        = Icons.content_cut_rounded;
  static const IconData zoomIn       = Icons.zoom_in_rounded;
  static const IconData zoomOut      = Icons.zoom_out_rounded;
  static const IconData snap         = Icons.bolt_rounded;
  static const IconData addTrack     = Icons.add_circle_outline_rounded;
  static const IconData rippleDelete = Icons.auto_fix_normal_rounded;
  static const IconData mute         = Icons.volume_off_rounded;
  static const IconData visibility   = Icons.visibility_rounded;
  static const IconData lock         = Icons.lock_outline_rounded;

  static const IconData play         = Icons.play_arrow_rounded;
  static const IconData pause        = Icons.pause_rounded;
  static const IconData stop         = Icons.stop_rounded;
  static const IconData skipNext     = Icons.skip_next_rounded;
  static const IconData skipPrev     = Icons.skip_previous_rounded;
  static const IconData goToStart    = Icons.first_page_rounded;
  static const IconData goToEnd      = Icons.last_page_rounded;
  static const IconData loop         = Icons.loop_rounded;

  static const IconData add          = Icons.add_rounded;
  static const IconData close        = Icons.close_rounded;
  static const IconData delete       = Icons.delete_rounded;
  static const IconData edit         = Icons.edit_rounded;
  static const IconData copy         = Icons.copy_rounded;
  static const IconData paste        = Icons.content_paste_rounded;
  static const IconData cut          = Icons.content_cut_rounded;
  static const IconData undo         = Icons.undo_rounded;
  static const IconData redo         = Icons.redo_rounded;
  static const IconData save         = Icons.save_rounded;
  static const IconData settings     = Icons.settings_rounded;
  static const IconData export_      = Icons.file_upload_rounded;
  static const IconData fullscreen   = Icons.fullscreen_rounded;
  static const IconData search       = Icons.search_rounded;
  static const IconData more         = Icons.more_horiz_rounded;

  static const IconData inspector    = Icons.info_outline_rounded;
  static const IconData library      = Icons.library_books_rounded;
  static const IconData timeline     = Icons.timeline_rounded;
  static const IconData waveform     = Icons.equalizer_rounded;
}
// -------------------------------------------
//  3. EdgeTypography � Professional Type Scale
// -------------------------------------------
class EdgeTypography {
  static const String displayFamily  = 'Inter';
  static const String uiFamily      = 'Inter';

  static const TextStyle displayLarge = TextStyle(
    fontFamily: displayFamily, fontSize: 34, fontWeight: FontWeight.w700,
    letterSpacing: -0.5, height: 1.15, color: EdgeTheme.textPrimary,
  );
  static const TextStyle displayMedium = TextStyle(
    fontFamily: displayFamily, fontSize: 28, fontWeight: FontWeight.w700,
    letterSpacing: -0.3, height: 1.2, color: EdgeTheme.textPrimary,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: displayFamily, fontSize: 22, fontWeight: FontWeight.w600,
    letterSpacing: -0.2, height: 1.25, color: EdgeTheme.textPrimary,
  );
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: displayFamily, fontSize: 18, fontWeight: FontWeight.w600,
    letterSpacing: -0.1, height: 1.3, color: EdgeTheme.textPrimary,
  );
  static const TextStyle headlineSmall = TextStyle(
    fontFamily: displayFamily, fontSize: 16, fontWeight: FontWeight.w600,
    letterSpacing: 0, height: 1.3, color: EdgeTheme.textPrimary,
  );

  static const TextStyle titleLarge = TextStyle(
    fontFamily: uiFamily, fontSize: 15, fontWeight: FontWeight.w600,
    letterSpacing: -0.1, height: 1.35, color: EdgeTheme.textPrimary,
  );
  static const TextStyle titleMedium = TextStyle(
    fontFamily: uiFamily, fontSize: 14, fontWeight: FontWeight.w500,
    letterSpacing: 0, height: 1.4, color: EdgeTheme.textPrimary,
  );
  static const TextStyle titleSmall = TextStyle(
    fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w500,
    letterSpacing: 0, height: 1.4, color: EdgeTheme.textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: uiFamily, fontSize: 13, fontWeight: FontWeight.w400,
    letterSpacing: 0, height: 1.45, color: EdgeTheme.textPrimary,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: uiFamily, fontSize: 12, fontWeight: FontWeight.w400,
    letterSpacing: 0, height: 1.45, color: EdgeTheme.textSecondary,
  );
  static const TextStyle bodySmall = TextStyle(
    fontFamily: uiFamily, fontSize: 11, fontWeight: FontWeight.w400,
    letterSpacing: 0, height: 1.45, color: EdgeTheme.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: uiFamily, fontSize: 11, fontWeight: FontWeight.w500,
    letterSpacing: 0.2, height: 1.3, color: EdgeTheme.textSecondary,
  );

  static const TextStyle small = TextStyle(
    fontFamily: uiFamily, fontSize: 10, fontWeight: FontWeight.w500,
    letterSpacing: 0.3, height: 1.2, color: EdgeTheme.textSecondary,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600,
    letterSpacing: 0.5, height: 1.3, color: EdgeTheme.textPrimary,
  );
  static const TextStyle monoSmall = TextStyle(
    fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w500,
    letterSpacing: 0.3, height: 1.2, color: EdgeTheme.textSecondary,
  );
}

// -------------------------------------------
//  4. EdgeSpacing � Consistent Spacing Scale
// -------------------------------------------
class EdgeSpacing {
  static const double xxs  = 2.0;
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 24.0;
  static const double xxl  = 32.0;
  static const double xxxl = 48.0;
  static const double huge = 64.0;
}

// -------------------------------------------
//  5. EdgeAnimations � Duration + Curve
// -------------------------------------------
class EdgeAnimations {
  static const Duration fast       = Duration(milliseconds: 100);
  static const Duration normal     = Duration(milliseconds: 200);
  static const Duration slow       = Duration(milliseconds: 350);
  static const Duration expressive = Duration(milliseconds: 500);

  static const Curve easeOutCubic    = Curves.easeOutCubic;
  static const Curve easeInOutCubic  = Curves.easeInOutCubic;
  static const Curve easeOutExpo     = Curves.easeOutExpo;
  static const Curve easeInOutExpo   = Curves.easeInOutExpo;
  static const Curve spring          = Curves.fastOutSlowIn;
  static const Curve bounce          = Curves.elasticOut;

  static const EdgeInsets panelSlide = EdgeInsets.only(bottom: 48.0);
  static const Duration panelSlideDuration = Duration(milliseconds: 300);
}
// -------------------------------------------
//  6. EdgePanel � Professional Panel
// -------------------------------------------
class EdgePanel extends StatefulWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final IconData? icon;
  final bool collapsible;
  final bool collapsed;
  final ValueChanged<bool>? onCollapsed;
  final Color? headerColor;
  final Color? bodyColor;
  final double headerHeight;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? headerPadding;
  final Widget? leading;
  final bool showDragHandle;
  final double minHeight;
  final double? maxHeight;

  const EdgePanel({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.icon,
    this.collapsible = false,
    this.collapsed = false,
    this.onCollapsed,
    this.headerColor,
    this.bodyColor,
    this.headerHeight = 32.0,
    this.padding = EdgeInsets.zero,
    this.headerPadding,
    this.leading,
    this.showDragHandle = false,
    this.minHeight = 32.0,
    this.maxHeight,
  });

  @override
  State<EdgePanel> createState() => _EdgePanelState();
}

class _EdgePanelState extends State<EdgePanel> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _heightFactor;
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.collapsed;
    _animController = AnimationController(
      duration: EdgeAnimations.normal, vsync: this,
    );
    _heightFactor = _animController.drive(CurveTween(curve: EdgeAnimations.easeInOutCubic));
    if (!_collapsed) _animController.value = 1.0;
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!widget.collapsible) return;
    setState(() => _collapsed = !_collapsed);
    if (_collapsed) { _animController.reverse(); } else { _animController.forward(); }
    widget.onCollapsed?.call(_collapsed);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: EdgeTheme.panelDecoration(
        color: widget.bodyColor ?? EdgeTheme.panelBg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EdgePanelHeader(
            title: widget.title, icon: widget.icon,
            actions: widget.actions, collapsed: _collapsed,
            collapsible: widget.collapsible, onToggle: _toggle,
            headerColor: widget.headerColor, height: widget.headerHeight,
            leading: widget.leading, padding: widget.headerPadding,
          ),
          if (widget.collapsible)
            AnimatedBuilder(
              animation: _heightFactor,
              builder: (context, child) => ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _heightFactor.value,
                  child: child,
                ),
              ),
              child: _buildBody(),
            )
          else
            _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Flexible(
      child: widget.padding == EdgeInsets.zero
          ? widget.child
          : Padding(padding: widget.padding, child: widget.child),
    );
  }
}

class _EdgePanelHeader extends StatelessWidget {
  final String title; final IconData? icon;
  final List<Widget>? actions; final bool collapsed;
  final bool collapsible; final VoidCallback onToggle;
  final Color? headerColor; final double height;
  final Widget? leading; final EdgeInsetsGeometry? padding;

  const _EdgePanelHeader({
    required this.title, this.icon, this.actions,
    required this.collapsed, required this.collapsible,
    required this.onToggle, this.headerColor, required this.height,
    this.leading, this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: headerColor ?? EdgeTheme.toolbar,
        border: const Border(bottom: BorderSide(color: EdgeTheme.divider)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 12, color: EdgeTheme.textSecondary), const SizedBox(width: 6)],
          Expanded(
            child: Text(title, style: EdgeTypography.titleSmall, overflow: TextOverflow.ellipsis),
          ),
          if (actions != null) ...actions!,
          if (collapsible)
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: AnimatedRotation(
                  turns: collapsed ? -0.25 : 0,
                  duration: EdgeAnimations.normal,
                  child: Icon(Icons.chevron_right_rounded, size: 14, color: EdgeTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
// -------------------------------------------
//  7. EdgeToolbar � Professional Toolbar
// -------------------------------------------
class EdgeToolbar extends StatelessWidget {
  final List<EdgeToolbarItem> items;
  final List<EdgeToolbarSegment>? segments;
  final int? selectedSegment;
  final ValueChanged<int>? onSegmentChanged;
  final String? searchHint;
  final ValueChanged<String>? onSearch;
  final String? searchValue;
  final Widget? leading;
  final Widget? trailing;
  final double height;

  const EdgeToolbar({
    super.key, this.items = const [], this.segments,
    this.selectedSegment, this.onSegmentChanged,
    this.searchHint, this.onSearch, this.searchValue,
    this.leading, this.trailing, this.height = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: EdgeTheme.toolbarDecoration,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          if (segments != null) ...[
            _EdgeSegmentedControl(
              segments: segments!, selected: selectedSegment ?? 0,
              onChanged: onSegmentChanged ?? (_) {},
            ),
            const SizedBox(width: 12),
            _EdgeDivider(),
            const SizedBox(width: 12),
          ],
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _EdgeToolButton(item: item),
          )),
          const Spacer(),
          if (searchHint != null)
            _EdgeSearchBar(
              hint: searchHint!, value: searchValue ?? '',
              onChanged: onSearch ?? (_) {},
            ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class EdgeToolbarItem {
  final IconData icon; final String tooltip;
  final VoidCallback? onPressed;
  final bool selected; final bool enabled; final Widget? badge;

  const EdgeToolbarItem({
    required this.icon, required this.tooltip, this.onPressed,
    this.selected = false, this.enabled = true, this.badge,
  });
}

class EdgeToolbarSegment {
  final IconData icon; final String tooltip;
  const EdgeToolbarSegment({required this.icon, required this.tooltip});
}

class _EdgeToolButton extends StatefulWidget {
  final EdgeToolbarItem item;
  const _EdgeToolButton({required this.item});
  @override
  State<_EdgeToolButton> createState() => _EdgeToolButtonState();
}

class _EdgeToolButtonState extends State<_EdgeToolButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Tooltip(
      message: item.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: item.enabled ? item.onPressed : null,
          child: AnimatedContainer(
            duration: EdgeAnimations.fast,
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: item.selected
                  ? EdgeTheme.accent.withValues(alpha: 0.3)
                  : _hovered && item.enabled
                      ? EdgeTheme.surfaceElevated : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(child: Icon(item.icon, size: 16,
                  color: item.enabled
                      ? (item.selected ? EdgeTheme.accent : EdgeTheme.textSecondary)
                      : EdgeTheme.textSecondary.withValues(alpha: 0.4),
                )),
                if (item.badge != null)
                  Positioned(right: -2, top: -2, child: item.badge!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeDivider extends StatelessWidget {
  const _EdgeDivider();
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 20, color: EdgeTheme.divider);
  }
}

class _EdgeSearchBar extends StatefulWidget {
  final String hint; final String value; final ValueChanged<String> onChanged;
  const _EdgeSearchBar({required this.hint, required this.value, required this.onChanged});
  @override
  State<_EdgeSearchBar> createState() => _EdgeSearchBarState();
}

class _EdgeSearchBarState extends State<_EdgeSearchBar> {
  late TextEditingController _controller;

  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.value); }

  @override
  void didUpdateWidget(_EdgeSearchBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160, height: 24,
      decoration: BoxDecoration(
        color: EdgeTheme.panelBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: EdgeTheme.divider),
      ),
      child: TextField(
        controller: _controller, style: EdgeTypography.bodySmall,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: EdgeTypography.bodySmall.copyWith(color: EdgeTheme.textSecondary.withValues(alpha: 0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          suffixIcon: Icon(Icons.search_rounded, size: 14, color: EdgeTheme.textSecondary),
          suffixIconConstraints: const BoxConstraints(maxHeight: 24, maxWidth: 24),
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _EdgeSegmentedControl extends StatelessWidget {
  final List<EdgeToolbarSegment> segments;
  final int selected; final ValueChanged<int> onChanged;

  const _EdgeSegmentedControl({required this.segments, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      decoration: BoxDecoration(
        color: EdgeTheme.panelBg,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: EdgeTheme.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(segments.length, (i) {
          final seg = segments[i];
          final isSelected = i == selected;
          final isFirst = i == 0; final isLast = i == segments.length - 1;
          return Tooltip(
            message: seg.tooltip,
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: EdgeAnimations.fast,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? EdgeTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: isFirst ? const Radius.circular(4) : Radius.zero,
                    bottomLeft: isFirst ? const Radius.circular(4) : Radius.zero,
                    topRight: isLast ? const Radius.circular(4) : Radius.zero,
                    bottomRight: isLast ? const Radius.circular(4) : Radius.zero,
                  ),
                  border: isSelected ? Border.all(color: EdgeTheme.accent.withValues(alpha: 0.5)) : null,
                ),
                child: Icon(seg.icon, size: 14, color: isSelected ? EdgeTheme.accent : EdgeTheme.textSecondary),
              ),
            ),
          );
        }),
      ),
    );
  }
}
// -------------------------------------------
//  8. EdgeTimelineRuler � Professional Ruler
// -------------------------------------------
class EdgeTimelineRuler extends StatelessWidget {
  final double zoomLevel; final double durationSec;
  final double playheadSec; final double workAreaStart;
  final double workAreaEnd; final double viewportWidth;
  final double scrollOffset; final bool showWorkArea;
  final int fps; final double height;

  const EdgeTimelineRuler({
    super.key, required this.zoomLevel, required this.durationSec,
    required this.playheadSec, this.workAreaStart = 0, this.workAreaEnd = 0,
    required this.viewportWidth, this.scrollOffset = 0,
    this.showWorkArea = false, this.fps = 30, this.height = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _TimelineRulerPainter(
          zoomLevel: zoomLevel, durationSec: durationSec,
          playheadSec: playheadSec, workAreaStart: workAreaStart,
          workAreaEnd: workAreaEnd, scrollOffset: scrollOffset,
          showWorkArea: showWorkArea, fps: fps,
        ),
        size: Size(viewportWidth, height),
      ),
    );
  }
}

class _TimelineRulerPainter extends CustomPainter {
  final double zoomLevel; final double durationSec;
  final double playheadSec; final double workAreaStart;
  final double workAreaEnd; final double scrollOffset;
  final bool showWorkArea; final int fps;

  _TimelineRulerPainter({
    required this.zoomLevel, required this.durationSec,
    required this.playheadSec, required this.workAreaStart,
    required this.workAreaEnd, required this.scrollOffset,
    required this.showWorkArea, required this.fps,
  });

  double get _pps => zoomLevel;

  double get _tickInterval {
    if (_pps > 200) return 0.1;
    if (_pps > 100) return 0.25;
    if (_pps > 50) return 0.5;
    if (_pps > 20) return 1;
    if (_pps > 10) return 2;
    if (_pps > 5) return 5;
    return 10;
  }

  double get _subTickCount => 4;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = EdgeTheme.trackBg;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final linePaint = Paint()..color = EdgeTheme.divider..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 1), Offset(size.width, size.height - 1), linePaint);

    final startSec = scrollOffset / _pps;
    final endSec = (scrollOffset + size.width) / _pps;
    final tick = _tickInterval;
    final subTickStep = tick / (_subTickCount + 1);
    final firstTick = ((startSec / tick).floor()) * tick;

    if (showWorkArea && workAreaEnd > workAreaStart) {
      final waX = workAreaStart * _pps - scrollOffset;
      final waW = (workAreaEnd - workAreaStart) * _pps;
      canvas.drawRect(Rect.fromLTWH(waX, 0, waW, size.height), Paint()..color = EdgeTheme.workAreaBar);
      final waBorder = Paint()..color = EdgeTheme.workAreaBorder..strokeWidth = 1;
      canvas.drawLine(Offset(waX, 0), Offset(waX, size.height), waBorder);
      canvas.drawLine(Offset(waX + waW, 0), Offset(waX + waW, size.height), waBorder);
    }

    double t = firstTick;
    while (t <= endSec) {
      final x = t * _pps - scrollOffset;
      if (x < -5 || x > size.width + 5) { t += tick; continue; }

      final isMinor = t % (_tickInterval * 5) != 0;
      final tickHeight = isMinor ? size.height * 0.35 : size.height * 0.6;
      final tickPaint = Paint()
        ..color = isMinor ? EdgeTheme.divider : EdgeTheme.textSecondary.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, size.height - tickHeight), Offset(x, size.height), tickPaint);

      if (!isMinor) {
        final timecode = _formatTimecode(t);
        final tp = TextPainter(
          text: TextSpan(text: timecode, style: EdgeTypography.monoSmall),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, size.height - tickHeight - tp.height - 2));
      }

      for (int i = 1; i <= _subTickCount; i++) {
        final subX = (t + subTickStep * i) * _pps - scrollOffset;
        if (subX < 0 || subX > size.width) continue;
        canvas.drawLine(
          Offset(subX, size.height - 4), Offset(subX, size.height),
          Paint()..color = EdgeTheme.divider.withValues(alpha: 0.5)..strokeWidth = 0.5,
        );
      }
      t += tick;
    }

    final phX = playheadSec * _pps - scrollOffset;
    if (phX >= 0 && phX <= size.width) {
      canvas.drawLine(Offset(phX, 0), Offset(phX, size.height),
        Paint()..color = EdgeTheme.playhead..strokeWidth = 1);
      final path = Path()
        ..moveTo(phX, 0)..lineTo(phX - 5, 7)..lineTo(phX + 5, 7)..close();
      canvas.drawPath(path, Paint()..color = EdgeTheme.playhead);
    }

    final curTc = _formatTimecode(playheadSec);
    final curTp = TextPainter(
      text: TextSpan(text: curTc, style: EdgeTypography.monoSmall.copyWith(fontSize: 9)),
      textDirection: TextDirection.ltr,
    )..layout();
    curTp.paint(canvas, Offset(size.width - curTp.width - 4, 2));
  }

  String _formatTimecode(double sec) {
    if (sec.isInfinite || sec.isNaN) return '00:00:00;00';
    final h = (sec ~/ 3600);
    final m = ((sec % 3600) ~/ 60);
    final s = (sec % 60).toInt();
    final frame = ((sec - sec.floorToDouble()) * fps).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')};${frame.toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_TimelineRulerPainter old) =>
      old.zoomLevel != zoomLevel || old.durationSec != durationSec ||
      old.playheadSec != playheadSec || old.scrollOffset != scrollOffset ||
      old.workAreaStart != workAreaStart || old.workAreaEnd != workAreaEnd;
}
// -------------------------------------------
//  9. EdgeWorkspace � Full Workspace System
// -------------------------------------------
class EdgePanelConfig {
  final String id; final String title;
  final IconData icon; final bool visible;
  final double size; final double minSize;
  final double maxSize; final int order;

  const EdgePanelConfig({
    required this.id, required this.title,
    required this.icon, this.visible = true,
    this.size = 200, this.minSize = 120,
    this.maxSize = 600, this.order = 0,
  });

  EdgePanelConfig copyWith({
    bool? visible, double? size, int? order,
  }) => EdgePanelConfig(
    id: id, title: title, icon: icon,
    visible: visible ?? this.visible,
    size: size ?? this.size, minSize: minSize,
    maxSize: maxSize, order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'visible': visible,
    'size': size, 'order': order,
  };

  factory EdgePanelConfig.fromJson(Map<String, dynamic> json) => EdgePanelConfig(
    id: json['id'] as String, title: json['title'] as String,
    icon: Icons.folder_rounded, visible: json['visible'] as bool? ?? true,
    size: (json['size'] as num?)?.toDouble() ?? 200,
    minSize: 120, maxSize: 600, order: json['order'] as int? ?? 0,
  );
}

class EdgeLayout {
  final List<EdgePanelConfig> leftPanels;
  final List<EdgePanelConfig> rightPanels;
  final List<EdgePanelConfig> topPanels;

  const EdgeLayout({
    this.leftPanels = const [],
    this.rightPanels = const [],
    this.topPanels = const [],
  });

  Map<String, dynamic> toJson() => {
    'leftPanels': leftPanels.map((p) => p.toJson()).toList(),
    'rightPanels': rightPanels.map((p) => p.toJson()).toList(),
    'topPanels': topPanels.map((p) => p.toJson()).toList(),
  };

  factory EdgeLayout.fromJson(Map<String, dynamic> json) => EdgeLayout(
    leftPanels: (json['leftPanels'] as List?)?.map((e) => EdgePanelConfig.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    rightPanels: (json['rightPanels'] as List?)?.map((e) => EdgePanelConfig.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    topPanels: (json['topPanels'] as List?)?.map((e) => EdgePanelConfig.fromJson(e as Map<String, dynamic>)).toList() ?? [],
  );
}

class EdgeWorkspace {
  final String id; final String name;
  final Map<String, double> panelFractions;
  final EdgeLayout layout;

  const EdgeWorkspace({
    required this.id, required this.name,
    this.panelFractions = const {'left': 0.2, 'right': 0.25, 'bottom': 0.45},
    this.layout = const EdgeLayout(),
  });

  static const List<EdgeWorkspace> defaults = [
    EdgeWorkspace(id: 'editing', name: 'Editing', panelFractions: {'left': 0.15, 'right': 0.2, 'bottom': 0.4}),
    EdgeWorkspace(id: 'color', name: 'Color', panelFractions: {'left': 0.15, 'right': 0.35, 'bottom': 0.3}),
    EdgeWorkspace(id: 'audio', name: 'Audio', panelFractions: {'left': 0.2, 'right': 0.25, 'bottom': 0.35}),
    EdgeWorkspace(id: 'effects', name: 'Effects', panelFractions: {'left': 0.2, 'right': 0.35, 'bottom': 0.3}),
    EdgeWorkspace(id: 'minimal', name: 'Minimal', panelFractions: {'left': 0.12, 'right': 0.15, 'bottom': 0.5}),
  ];
}

class EdgeWorkspaceManager {
  String _currentId = 'editing';
  EdgeWorkspace? _customWorkspace;

  String get currentId => _currentId;
  EdgeWorkspace get current =>
      _customWorkspace ?? EdgeWorkspace.defaults.firstWhere((w) => w.id == _currentId, orElse: () => EdgeWorkspace.defaults.first);

  Map<String, double> get fractions => current.panelFractions;

  void switchTo(String id) {
    if (EdgeWorkspace.defaults.any((w) => w.id == id)) {
      _currentId = id;
      _customWorkspace = null;
    }
  }

  void setCustomFractions(Map<String, double> fractions) {
    _customWorkspace = EdgeWorkspace(id: 'custom', name: 'Custom', panelFractions: fractions);
    _currentId = 'custom';
  }

  void resetToDefault() { _currentId = 'editing'; _customWorkspace = null; }

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('edge_workspace_id', _currentId);
  }

  Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('edge_workspace_id');
    if (id != null && EdgeWorkspace.defaults.any((w) => w.id == id)) _currentId = id;
  }
}
// -------------------------------------------
//  10. EdgeMenuButton � Menu Bar Item
// -------------------------------------------
class EdgeMenuEntry {
  final String label;
  final String? shortcut;
  final IconData? icon;
  final VoidCallback? action;
  final List<EdgeMenuEntry>? submenu;
  final bool divider;
  final bool enabled;

  const EdgeMenuEntry({
    required this.label, this.shortcut, this.icon,
    this.action, this.submenu, this.divider = false, this.enabled = true,
  });

  const EdgeMenuEntry.divider()
      : label = '', shortcut = null, icon = null, action = null,
        submenu = null, divider = true, enabled = true;
}

class EdgeMenuButton extends StatefulWidget {
  final String label;
  final List<EdgeMenuEntry> entries;

  const EdgeMenuButton({super.key, required this.label, required this.entries});

  @override
  State<EdgeMenuButton> createState() => _EdgeMenuButtonState();
}

class _EdgeMenuButtonState extends State<EdgeMenuButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (key) {},
      tooltip: '',
      offset: const Offset(0, 28),
      color: EdgeTheme.toolbar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: EdgeTheme.divider),
      ),
      elevation: 8,
      constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
      itemBuilder: (_) => _buildItems(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: EdgeAnimations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? EdgeTheme.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(widget.label, style: EdgeTypography.bodyLarge.copyWith(fontSize: 12, color: EdgeTheme.menuBarText)),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _buildItems() {
    final entries = <PopupMenuEntry<String>>[];
    for (final entry in widget.entries) {
      if (entry.divider) {
        entries.add(const PopupMenuDivider(height: 1));
        continue;
      }
      if (entry.submenu != null) {
        entries.add(
          PopupMenuItem<String>(
            enabled: entry.enabled,
            child: _buildSubmenuItem(entry),
          ),
        );
      } else {
        entries.add(
          PopupMenuItem<String>(
            enabled: entry.enabled,
            onTap: entry.action,
            child: _buildMenuItem(entry),
          ),
        );
      }
    }
    return entries;
  }

  Widget _buildMenuItem(EdgeMenuEntry entry) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          if (entry.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(entry.icon, size: 14, color: EdgeTheme.textSecondary),
            )
          else
            const SizedBox(width: 24),
          Expanded(
            child: Text(entry.label, style: TextStyle(
              fontSize: 12, color: entry.enabled ? EdgeTheme.textPrimary : EdgeTheme.textSecondary.withValues(alpha: 0.4),
            )),
          ),
          if (entry.shortcut != null)
            Text(entry.shortcut!, style: const TextStyle(
              fontSize: 10, color: EdgeTheme.textSecondary, fontFamily: 'monospace',
            )),
        ],
      ),
    );
  }

  Widget _buildSubmenuItem(EdgeMenuEntry entry) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          if (entry.icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(entry.icon, size: 14, color: EdgeTheme.textSecondary),
            )
          else
            const SizedBox(width: 24),
          Text(entry.label, style: const TextStyle(fontSize: 12, color: EdgeTheme.textPrimary)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 12, color: EdgeTheme.textSecondary),
        ],
      ),
    );
  }
}
// -------------------------------------------
//  11. EdgeStatusBar � Professional Status Bar
// -------------------------------------------
class EdgeStatusBar extends StatelessWidget {
  final double currentTimecode;
  final double zoomLevel;
  final double fps;
  final bool isBackendConnected;
  final bool isExporting;
  final double exportProgress;
  final String exportStatus;
  final String? statusMessage;
  final int proxyCount;
  final bool unsavedChanges;

  const EdgeStatusBar({
    super.key,
    this.currentTimecode = 0,
    this.zoomLevel = 30,
    this.fps = 30,
    this.isBackendConnected = true,
    this.isExporting = false,
    this.exportProgress = 0,
    this.exportStatus = '',
    this.statusMessage,
    this.proxyCount = 0,
    this.unsavedChanges = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: EdgeTheme.statusBar,
        border: Border(top: BorderSide(color: EdgeTheme.divider)),
      ),
      child: Row(
        children: [
          // Connection status
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isBackendConnected ? EdgeTheme.success : EdgeTheme.error,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isBackendConnected ? 'Backend Connected' : 'Disconnected',
            style: EdgeTypography.small.copyWith(fontSize: 10),
          ),
          if (statusMessage != null) ...[
            Container(width: 1, height: 12, color: EdgeTheme.divider, margin: const EdgeInsets.symmetric(horizontal: 8)),
            Text(statusMessage!, style: EdgeTypography.small.copyWith(fontSize: 10)),
          ],
          const Spacer(),
          // Export progress
          if (isExporting)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 50, height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: exportProgress,
                        backgroundColor: EdgeTheme.panelBg,
                        valueColor: const AlwaysStoppedAnimation(EdgeTheme.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('${(exportProgress * 100).toInt()}%', style: EdgeTypography.small.copyWith(fontSize: 10, color: EdgeTheme.accent)),
                ],
              ),
            ),
          // Timecode
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: EdgeTheme.panelBg,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _formatSMPTE(currentTimecode),
              style: const TextStyle(
                fontFamily: 'monospace', fontSize: 11,
                fontWeight: FontWeight.w600, color: EdgeTheme.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // FPS
          Text('${fps.toInt()} fps', style: EdgeTypography.small.copyWith(fontSize: 10)),
          const SizedBox(width: 8),
          // Zoom
          Text('${zoomLevel.toInt()}x', style: EdgeTypography.small.copyWith(fontSize: 10)),
          if (proxyCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: EdgeTheme.warning.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text('$proxyCount proxies', style: EdgeTypography.small.copyWith(fontSize: 9, color: EdgeTheme.warning)),
            ),
          ],
          if (unsavedChanges) ...[
            const SizedBox(width: 8),
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: EdgeTheme.warning),
            ),
          ],
        ],
      ),
    );
  }

  String _formatSMPTE(double sec) {
    if (sec.isInfinite || sec.isNaN) return '00:00:00;00';
    final h = (sec ~/ 3600);
    final m = ((sec % 3600) ~/ 60);
    final s = (sec % 60).toInt();
    final frame = ((sec - sec.floorToDouble()) * fps).round();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')};${frame.toString().padLeft(2, '0')}';
  }
}
