import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart' as tokens;
import '../../shared/l10n/context_l10n.dart';
import '../../shared/providers/toast_provider.dart';
import '../timeline/providers/timeline_provider.dart';
import 'rendered_clip.dart';
import 'timeline_bridge.dart';

/// شاشة النتائج الفيروسية لعملية الـ Auto-Edit.
///
/// قابلة للاختبار بدون تعقيد Riverpod: كل الأفعال تمر عبر callbacks اختيارية،
/// وإن لم تُمرَّر تُستخدم التنفيذات الافتراضية المعتمدة على [ref].
class AutoEditResultsScreen extends ConsumerStatefulWidget {
  final List<RenderedClipData> clips;
  final String? compiledUrl;
  final String? sourceVideoPath;

  /// درجة الانتباه المتوقعة (0–100) لكل مقطع حسب [RenderedClipData.index] —
  /// من استجابة الـ auto-edit عند توفّرها؛ null أو غياب المفتاح ⇒ شارة «—».
  final Map<int, int>? attentionScores;

  /// حقن الاختبار — افتراضياً null وتُستخدم التنفيذات الداخلية.
  final Future<void> Function(RenderedClipData clip)? onPreview;
  final Future<void> Function(RenderedClipData clip)? onSave;
  final int Function(RenderedClipData clip)? onSendOne;
  final int Function(List<RenderedClipData> sortedByScoreDesc)? onAddAll;
  final Future<void> Function(String dir)? onExportAll;

  const AutoEditResultsScreen({
    super.key,
    required this.clips,
    this.compiledUrl,
    this.sourceVideoPath,
    this.attentionScores,
    this.onPreview,
    this.onSave,
    this.onSendOne,
    this.onAddAll,
    this.onExportAll,
  });

  /// أحمر < 0.5 ← كهرماني ← أخضر — تدرج لون درجة الانتشار.
  static Color scoreColor(double score) {
    final s = score.clamp(0.0, 1.0);
    const red = AppColors.destructive;
    const amber = AppColors.yellow;
    const green = AppColors.secondary;
    if (s <= 0.5) {
      return Color.lerp(red, amber, s * 2)!;
    }
    return Color.lerp(amber, green, (s - 0.5) * 2)!;
  }

  /// القائمة معروضة بترتيب النتيجة تنازلياً والرتبة = الموضع + 1.
  List<RenderedClipData> get rankedClips {
    final sorted = [...clips]
      ..sort((a, b) => b.viralScore.compareTo(a.viralScore));
    return sorted;
  }

  @override
  ConsumerState<AutoEditResultsScreen> createState() =>
      _AutoEditResultsScreenState();
}

class _AutoEditResultsScreenState extends ConsumerState<AutoEditResultsScreen> {
  bool get _isDesktopTarget => !kIsWeb && Platform.isWindows;

  bool _isLocalFile(String url) =>
      url.isNotEmpty &&
      !url.startsWith('http://') &&
      !url.startsWith('https://');

  double _resolveInsertAt() {
    final data = ref.read(timelineProvider);
    double t = data.timeline.playheadSec;
    final tracks = data.timeline.tracks.video;
    if (tracks.isNotEmpty) {
      for (final c in tracks.first.clips) {
        if (c.endTimeInTimeline > t) t = c.endTimeInTimeline;
      }
    }
    return t < 0 ? 0 : t;
  }

  String slugOf(RenderedClipData clip) {
    final raw = clip.hookText.trim().toLowerCase();
    var s = raw.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.length > 30) s = s.substring(0, 30);
    final base = s.isEmpty ? 'viral' : s;
    return '${base}_clip${clip.index + 1}';
  }

  String _extensionOf(String url) {
    final ext = p.extension(url);
    return (ext.isNotEmpty && ext.length <= 5) ? ext : '.mp4';
  }

  Future<void> _defaultPreview(RenderedClipData clip) async {
    final l10n = context.l10n;
    if (!_isDesktopTarget || !_isLocalFile(clip.fileUrl)) {
      ref
          .read(toastProvider.notifier)
          .info(l10n.t('results_preview_local_only'));
      return;
    }
    if (!File(clip.fileUrl).existsSync()) {
      ref
          .read(toastProvider.notifier)
          .error(l10n.tf('results_file_missing', {'path': clip.fileUrl}));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _PreviewDialog(filePath: clip.fileUrl),
    );
  }

  Future<void> _defaultSave(RenderedClipData clip) async {
    final l10n = context.l10n; // captured before async gaps
    if (!_isDesktopTarget || !_isLocalFile(clip.fileUrl)) {
      ref
          .read(toastProvider.notifier)
          .error(l10n.t('results_save_requires_local'));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.t('results_pick_save_dir'),
    );
    if (dir == null || !mounted) return;

    final suggested = TextEditingController(
      text: '${slugOf(clip)}${_extensionOf(clip.fileUrl)}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('results_save_dialog_title')),
        content: TextField(
          controller: suggested,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.t('results_file_name_label'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.t('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, suggested.text.trim()),
            child: Text(l10n.t('common_save')),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await File(clip.fileUrl).copy(p.join(dir, name));
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .success(l10n.tf('results_saved_toast', {'name': name}));
    } catch (e) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .error(l10n.tf('results_save_failed', {'error': '$e'}));
    }
  }

  int _defaultSendOne(RenderedClipData clip) {
    final vcs = clipsToVideoClips([clip], insertAtSec: _resolveInsertAt());
    return appendToTimeline(ref, vcs);
  }

  int _defaultAddAll(List<RenderedClipData> sorted) {
    final vcs = clipsToVideoClips(sorted, insertAtSec: _resolveInsertAt());
    return appendToTimeline(ref, vcs);
  }

  Future<void> _defaultExportAll(String dir) async {
    final l10n = context.l10n; // captured before async gaps
    var ok = 0;
    final errors = <String>[];
    for (final c in widget.clips) {
      if (!_isLocalFile(c.fileUrl)) continue;
      try {
        await File(
          c.fileUrl,
        ).copy(p.join(dir, '${slugOf(c)}${_extensionOf(c.fileUrl)}'));
        ok++;
      } catch (e) {
        errors.add(c.fileUrl);
      }
    }
    if (!mounted) return;
    if (errors.isEmpty && ok > 0) {
      ref
          .read(toastProvider.notifier)
          .success(l10n.tf('results_exported_toast', {'n': '$ok', 'dir': dir}));
    } else if (ok == 0) {
      ref.read(toastProvider.notifier).error(l10n.t('results_no_local_files'));
    } else {
      ref
          .read(toastProvider.notifier)
          .info(
            l10n.tf('results_partial_export_toast', {
              'n': '$ok',
              'failed': '${errors.length}',
            }),
          );
    }
  }

  void _handleAddAll() {
    final sorted = widget.rankedClips;
    final added = widget.onAddAll != null
        ? widget.onAddAll!(sorted)
        : _defaultAddAll(sorted);
    ref
        .read(toastProvider.notifier)
        .success(context.l10n.tf('results_added_many_toast', {'n': '$added'}));
    Navigator.of(context).maybePop();
  }

  Future<void> _handleExportAll() async {
    final l10n = context.l10n; // captured before async gap
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.t('results_export_dir_title'),
    );
    if (dir == null || !mounted) return;
    if (widget.onExportAll != null) {
      await widget.onExportAll!(dir);
    } else {
      await _defaultExportAll(dir);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranked = widget.rankedClips;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(ranked),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cols = constraints.maxWidth >= 900 ? 2 : 1;
                  if (ranked.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.t('results_empty'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(tokens.Spacing.lg),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: tokens.Spacing.md,
                      crossAxisSpacing: tokens.Spacing.md,
                      childAspectRatio: cols == 2 ? 1.85 : 2.3,
                    ),
                    itemCount: ranked.length,
                    itemBuilder: (context, i) => _StaggerIn(
                      index: i,
                      child: _ResultCard(
                        clip: ranked[i],
                        rank: i + 1,
                        isDesktopTarget: _isDesktopTarget,
                        attentionScore:
                            widget.attentionScores?[ranked[i].index],
                        onPreview: (c) => widget.onPreview != null
                            ? widget.onPreview!(c)
                            : _defaultPreview(c),
                        onSave: (c) => widget.onSave != null
                            ? widget.onSave!(c)
                            : _defaultSave(c),
                        onSendOne: (c) {
                          final n = widget.onSendOne != null
                              ? widget.onSendOne!(c)
                              : _defaultSendOne(c);
                          ref
                              .read(toastProvider.notifier)
                              .success(
                                context.l10n.t('results_added_one_toast'),
                              );
                          return n;
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(List<RenderedClipData> ranked) {
    return Container(
      decoration: AppDecorations.toolbar,
      padding: const EdgeInsets.symmetric(
        horizontal: tokens.Spacing.lg,
        vertical: tokens.Spacing.sm,
      ),
      child: Row(
        children: [
          const SizedBox(width: tokens.Spacing.sm),
          Text(
            context.l10n.t('results_title'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: tokens.Spacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: tokens.Spacing.md,
              vertical: tokens.Spacing.xs,
            ),
            decoration: AppDecorations.chip(color: AppColors.primary),
            child: Text(
              '${ranked.length} ${context.l10n.t('unit_clips')}',
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: context.l10n.t('common_close'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: AppDecorations.toolbar.copyWith(
        border: const Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: tokens.Spacing.lg,
        vertical: tokens.Spacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('export_all'),
            onPressed: _handleExportAll,
            icon: const Icon(Icons.folder_copy_outlined, size: 16),
            label: Text(context.l10n.t('results_export_all')),
          ),
          const SizedBox(width: tokens.Spacing.md),
          ElevatedButton.icon(
            key: const ValueKey('add_all'),
            onPressed: _handleAddAll,
            icon: const Icon(Icons.playlist_add, size: 16),
            label: Text(context.l10n.t('results_add_all')),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends StatefulWidget {
  final RenderedClipData clip;
  final int rank;
  final bool isDesktopTarget;

  /// درجة الانتباه المتوقعة (0–100) — null ⇒ تُعرض «—».
  final int? attentionScore;
  final Future<void> Function(RenderedClipData) onPreview;
  final Future<void> Function(RenderedClipData) onSave;
  final int Function(RenderedClipData) onSendOne;

  const _ResultCard({
    required this.clip,
    required this.rank,
    required this.isDesktopTarget,
    this.attentionScore,
    required this.onPreview,
    required this.onSave,
    required this.onSendOne,
  });

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _hovering = false;

  RenderedClipData get clip => widget.clip;
  int get rank => widget.rank;

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // ذهبي
      case 2:
        return const Color(0xFFC0C0C0); // فضي
      case 3:
        return const Color(0xFFCD7F32); // برونزي
      default:
        return AppColors.surfaceVariant;
    }
  }

  Color get _scoreRingColor =>
      AutoEditResultsScreen.scoreColor(clip.viralScore);

  @override
  Widget build(BuildContext context) {
    final hue = (clip.index * 47) % 360;
    final thumbTop = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.38).toColor();
    final thumbBottom = HSLColor.fromAHSL(
      1,
      ((hue + 40) % 360).toDouble(),
      0.55,
      0.20,
    ).toColor();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: tokens.Durations.base200,
        curve: tokens.Curves.standard,
        transform: _hovering
            ? Matrix4.translationValues(0, -2, 0)
            : Matrix4.identity(),
        decoration: AppDecorations.card.copyWith(
          border: Border.all(
            color: _hovering
                ? AppColors.primary.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildThumbnail(context, thumbTop, thumbBottom),
            Expanded(child: _buildInfo(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context, Color top, Color bottom) {
    return Container(
      width: 150,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(AppRadius.xl),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              size: 46,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          Positioned(
            top: tokens.Spacing.sm,
            left: tokens.Spacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: tokens.Spacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                context.l10n.tf('results_duration_badge', {
                  'v': clip.durationSec.toStringAsFixed(1),
                }),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: tokens.Spacing.sm,
            right: tokens.Spacing.sm,
            child: Icon(
              Icons.auto_awesome,
              size: 14,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfo(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        tokens.Spacing.md,
        tokens.Spacing.sm,
        tokens.Spacing.md,
        tokens.Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: tokens.Spacing.md,
                  vertical: tokens.Spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: _rankColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: _rankColor.withValues(alpha: 0.7)),
                ),
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    color: _rankColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: tokens.Spacing.xs),
              // TODO(l10n): tooltip نص عربي مؤقت إلى حين إضافة مفتاح app_strings.
              Tooltip(
                message: 'درجة الانتباه المتوقعة',
                triggerMode: TooltipTriggerMode.tap,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: tokens.Spacing.sm,
                    vertical: tokens.Spacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: AppColors.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 11,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.attentionScore != null
                            ? '${widget.attentionScore}/100'
                            : '—',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 52,
                height: 52,
                child: CustomPaint(
                  painter: _ScoreRingPainter(
                    score: clip.viralScore,
                    color: _scoreRingColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: tokens.Spacing.xs),
          Expanded(
            child: Text(
              '«${clip.hookText.isEmpty ? context.l10n.t('results_no_hook') : clip.hookText}»',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                height: 1.25,
              ),
            ),
          ),
          if (clip.captionTheme.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: tokens.Spacing.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: tokens.Spacing.sm,
                  vertical: 2,
                ),
                decoration: AppDecorations.chip(color: AppColors.secondary),
                child: Text(
                  clip.captionTheme,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ),
          Wrap(
            spacing: tokens.Spacing.xs,
            runSpacing: -6,
            children: [
              TextButton.icon(
                onPressed: () => widget.onPreview(clip),
                icon: const Icon(Icons.visibility_outlined, size: 14),
                label: Text(
                  context.l10n.t('results_preview_btn'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onSave(clip),
                icon: const Icon(Icons.save_outlined, size: 14),
                label: Text(
                  context.l10n.t('results_save_btn'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              TextButton.icon(
                onPressed: () => widget.onSendOne(clip),
                icon: const Icon(Icons.add_circle_outline, size: 14),
                label: Text(
                  context.l10n.t('results_to_timeline_btn'),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRingPainter extends CustomPainter {
  final double score;
  final Color color;

  _ScoreRingPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 5.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surfaceVariant;
    canvas.drawArc(rect, 0, 3.14159 * 2, false, bg);

    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke
      ..color = color;
    canvas.drawArc(
      rect,
      -1.5708,
      3.14159 * 2 * score.clamp(0.0, 1.0),
      false,
      fg,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: '${(score * 100).round()}%',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
          fontFamilyFallback: const ['Segoe UI', 'Arial'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) =>
      old.score != score || old.color != color;
}

class _PreviewDialog extends StatefulWidget {
  final String filePath;
  const _PreviewDialog({required this.filePath});

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.filePath));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(tokens.Spacing.md),
            child: Text(
              context.l10n.tf('preview_title', {
                'name': p.basename(widget.filePath),
              }),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(
            width: screenSize.width * 0.8 < 520 ? screenSize.width * 0.8 : 520,
            height: screenSize.height * 0.5 < 320
                ? screenSize.height * 0.5
                : 320,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Video(controller: _controller),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(tokens.Spacing.sm),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.t('common_close')),
            ),
          ),
        ],
      ),
    );
  }
}

/// دخول متدرّج: كل كرت ينزلق للأعلى مع تلاشٍ، بتأخير 100ms لكل عنصر.
class _StaggerIn extends StatefulWidget {
  final int index;
  final Widget child;

  const _StaggerIn({required this.index, required this.child});

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: tokens.Durations.slow300,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: tokens.Curves.standard,
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
