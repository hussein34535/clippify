import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/backend/auto_edit_api.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart' as tokens;
import '../../mobile_lite/studio_theme.dart';
import '../../shared/l10n/context_l10n.dart';
import '../results/auto_edit_results_screen.dart';
import '../results/rendered_clip.dart';

AutoEditApi? _defaultInstance;

AutoEditApi defaultAutoEditApi() => _defaultInstance ??= AutoEditApi();

// TODO(l10n): top-level const table has no BuildContext — Arabic labels kept
// as-is; localized labels resolved at render time via 'stage_<id>' keys.
const List<(String, String)> _kStages = [
  ('queued', 'انتظار'),
  ('transcribing', 'تفريغ الصوت'),
  ('understanding', 'فهم الفيديو 🧠'),
  ('selecting', 'اختيار أفضل اللحظات'),
  ('hooks', 'صياغة الهوك'),
  ('effects', 'تخطيط المؤثرات'),
  ('rendering', 'الرندر النهائي'),
  ('compiling', 'الدمج'),
];

class AutoEditProgressScreen extends StatefulWidget {
  final String sessionId;
  final String videoPath;
  final AutoEditAnswers? answers;
  final AutoEditApi api;
  final bool studioMode;

  /// عند توفره يُستدعى بالمقاطع بدل الانتقال لشاشة النتائج الكاملة —
  /// للتدفقات المستقلة (نسخة الموبايل الخفيفة) بشاشة نهاية خاصة بها.
  final void Function(List<RenderedClipData> clips)? onDone;

  const AutoEditProgressScreen({
    super.key,
    required this.sessionId,
    required this.videoPath,
    this.answers,
    required this.api,
    this.studioMode = false,
    this.onDone,
  });

  @override
  State<AutoEditProgressScreen> createState() => _AutoEditProgressScreenState();
}

class _AutoEditProgressScreenState extends State<AutoEditProgressScreen> {
  late String _sessionId;
  AutoEditEvent? _last;
  String? _errorDetail;
  bool _finished = false;
  bool _restarting = false;
  bool _confirmingCancel = false;
  List<RenderedClipData>? _pendingStudioClips;
  AutoEditEvent? _pendingQuestions;
  bool _submittingQuestions = false;
  StreamSubscription<AutoEditEvent>? _sub;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _subscribe();
  }

  @override
  void dispose() {
    _finished = true;
    _idleTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = widget.api.subscribeProgress(_sessionId).listen(
          _onEvent,
          onError: (Object e) {
            if (_finished || !mounted) return;
            setState(() => _errorDetail = '$e');
          },
          onDone: () {
            // البث اتقفل من غير حدث done (اشتراك متأخر/شبكة) — التقدم واقف
            // عند 100% بلا انتقال. الاستكمال عبر polling بدل التعليق.
            if (_finished || !mounted) return;
            _recoverViaStatus();
          },
        );
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 90), () async {
      if (!_finished && mounted) {
        await _recoverViaStatus();
        if (!_finished && mounted && _errorDetail == null) {
          _showTimeoutSnack(context.l10n.t('progress_stalled'));
          if (_pendingQuestions != null) _resetIdleTimer();
        }
      }
    });
  }

  /// استكمال عبر polling: لو الجلسة done فعلًا ننتقل بالـ clips، ولو
  /// فاشلة نعرض السبب — بدل الوقوف الأبدي عند آخر نسبة.
  @visibleForTesting
  Future<void> recoverForTest() => _recoverViaStatus();

  Future<void> _recoverViaStatus() async {
    if (_finished || !mounted) return;
    try {
      final st = await widget.api.status(_sessionId);
      final status = st?['status'] as String?;
      if (status == 'done') {
        final result =
            ((st?['result'] as Map?) ?? const {}).cast<String, dynamic>();
        final clips = (result['clips'] as List?) ?? const [];
        if (!mounted || _finished) return;
        _finished = true;
        _goResults(clips);
      } else if (status == 'awaiting_answers') {
        final events = (st?['events'] as List?) ?? const [];
        AutoEditEvent? questionEvent;
        for (final event in events.whereType<Map>()) {
          final decoded = AutoEditApi.decodeEvent(jsonEncode(event));
          if (decoded.type == 'questions') questionEvent = decoded;
        }
        if (questionEvent != null && mounted && !_finished) {
          _idleTimer?.cancel();
          setState(() {
            _pendingQuestions = questionEvent;
            _submittingQuestions = false;
            _last = questionEvent;
          });
        }
      } else if (status == 'error' || status == 'failed') {
        if (!mounted) return;
        final err = (st?['error'] ?? st?['message'] ?? 'فشل المعالجة').toString();
        setState(() => _errorDetail = err);
      } else if (_pendingQuestions != null) {
        // المهلة انتهت على المحرك أو تمت الإجابة من جهاز آخر؛ البطاقة القديمة
        // لازم تختفي بدل ما تحجب التقدم لباقي الجلسة.
        setState(() {
          _pendingQuestions = null;
          _submittingQuestions = false;
        });
        _resetIdleTimer();
      }
    } catch (_) {}
  }

  void _showTimeoutSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 4),
    ));
  }

  void _onEvent(AutoEditEvent event) {
    if (_finished || !mounted) return;
    _resetIdleTimer();
    switch (event.type) {
      case 'questions':
        _idleTimer?.cancel();
        setState(() {
          _pendingQuestions = event;
          _submittingQuestions = false;
          _last = event;
        });
        break;
      case 'done':
        _finished = true;
        _goResults(event.clipsJson ?? const []);
        break;
      case 'error':
        setState(() {
          _pendingQuestions = null;
          _errorDetail =
              event.messageAr.isNotEmpty ? event.messageAr : event.messageEn;
        });
        break;
      default:
        setState(() => _last = event);
        break;
    }
  }

  Future<void> _submitQuestions(List<AutoEditQuestionAnswer> answers) async {
    if (_submittingQuestions) return;
    setState(() => _submittingQuestions = true);
    final ok = await widget.api.answerQuestions(_sessionId, answers);
    if (!mounted) return;
    if (_pendingQuestions == null) return;
    if (ok) {
      setState(() => _pendingQuestions = null);
    } else {
      setState(() => _submittingQuestions = false);
      _showTimeoutSnack('تعذر إرسال الإجابات. حاول مرة أخرى أو تخطَّ الأسئلة.');
    }
  }

  void _goResults(List<dynamic> clipsJson) {
    final clips = clipsJson
        .whereType<Map>()
        .map((c) => RenderedClipData.fromJson(c.cast<String, dynamic>()))
        .toList();
    if (!mounted) return;
    final onDone = widget.onDone;
    if (onDone != null) {
      if (widget.studioMode && _confirmingCancel) {
        _pendingStudioClips = clips;
        return;
      }
      onDone(clips);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AutoEditResultsScreen(
        clips: clips,
        sourceVideoPath: widget.videoPath,
      ),
    ));
  }

  Future<void> _confirmCancel() async {
    if (_confirmingCancel || _finished) return;
    _confirmingCancel = true;
    final l10n = context.l10n; // captured before async gap
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('progress_cancel_confirm_title'),
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(l10n.t('progress_cancel_confirm_body'),
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.t('progress_keep_going'))),
          OutlinedButton(
            style: AppButtonStyle.outlined(color: AppColors.destructive),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.t('progress_confirm_cancel')),
          ),
        ],
      ),
    );
    _confirmingCancel = false;
    final ready = _pendingStudioClips;
    _pendingStudioClips = null;
    if (mounted && ready != null) {
      widget.onDone?.call(ready);
      return;
    }
    if (confirmed != true || !mounted || _finished) return;
    await performCancel();
  }

  /// ينفّذ الإلغاء الفعلي بعد التأكيد (مفصولة لقابلية الاختبار).
  @visibleForTesting
  Future<void> performCancel() async {
    _finished = true;
    await _sub?.cancel();
    try {
      await widget.api.cancel(_sessionId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry() async {
    if (widget.answers == null) {
      Navigator.of(context).pop();
      return;
    }
    final l10n = context.l10n; // captured before async gap
    setState(() {
      _errorDetail = null;
      _last = null;
      _restarting = true;
    });
    final sid = await widget.api.start(widget.videoPath, widget.answers!);
    if (!mounted) return;
    if (sid == null || sid.isEmpty) {
      setState(() {
        _errorDetail = l10n.t('progress_restart_failed');
        _restarting = false;
      });
      return;
    }
    setState(() {
      _sessionId = sid;
      _restarting = false;
    });
    _subscribe();
  }

  int get _currentIndex {
    final stage = _last?.stage ?? '';
    for (var i = 0; i < _kStages.length; i++) {
      if (_kStages[i].$1 == stage) return i;
    }
    return -1;
  }

  double get _progress => ((_last?.progress ?? 0) / 100).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    if (widget.studioMode) return _buildStudio();
    final progressPct = (_last?.progress ?? 0).clamp(0.0, 100.0);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    tokens.Spacing.lg, tokens.Spacing.md, tokens.Spacing.lg, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: _progress),
                    duration: tokens.Durations.slow300,
                    curve: tokens.Curves.emphasized,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value.clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: tokens.Spacing.sm),
                child: Center(
                  child: Text(
                    '${progressPct.round()}%',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      fontFamilyFallback: ['Consolas', 'Menlo', 'monospace'],
                    ),
                  ),
                ),
              ),
              Expanded(child: _buildBody()),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudio() {
    final detail = switch (_last?.stage) {
      'transcribing' || 'understanding' => 'بنحلل الكلام والصوت في الفيديو.',
      'selecting' || 'hooks' => 'بندور على لقطة ليها بداية ونهاية واضحة.',
      'effects' => 'بنجهز اللمسات الأخيرة للمقطع.',
      'rendering' || 'compiling' || 'done' => 'بنجهز ملف الفيديو للمعاينة والحفظ.',
      _ => 'الفيديو وصل. بنجهّزه للمعالجة.',
    };
    final failed = _errorDetail != null;
    return PopScope(
      canPop: _finished || failed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finished && !failed) _confirmCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استوديو الريلز'),
          automaticallyImplyLeading: false,
        ),
        body: StudioLayout(
          footer: _pendingQuestions != null && !failed
              ? const SizedBox.shrink()
              : failed
                  ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: const ValueKey('wizard_retry'),
                      onPressed: _retry,
                      child: const Text('حاول مجددًا'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('رجوع'),
                    ),
                  ],
                )
              : OutlinedButton(
                  onPressed: _restarting ? null : _confirmCancel,
                  child: const Text('إلغاء المونتاج'),
                ),
          children: [
            if (_pendingQuestions != null && !failed)
              _QuestionCard(
                key: const ValueKey('director_questions'),
                event: _pendingQuestions!,
                busy: _submittingQuestions,
                onSubmit: _submitQuestions,
              )
            else
              StudioProgress(
                title: failed ? 'المونتاج ما كملش' : 'بنجهّز الريل',
                detail: _errorDetail ?? detail,
                icon: failed
                    ? Icons.error_outline_rounded
                    : Icons.movie_filter_outlined,
                progress: _restarting || _last == null ? null : _progress,
                failed: failed,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: AppDecorations.toolbar,
      padding: const EdgeInsets.symmetric(
          horizontal: tokens.Spacing.md, vertical: tokens.Spacing.sm),
      child: Row(
        children: [
          IconButton(
            // المهمة شغالة؟ رجوع مباشر كان يتركها تحرق موارد السيرفر —
            // يمرّ بتأكيد الإلغاء الذي يوقفها فعليًا. المنتهية تُغلق فورًا.
            onPressed: (_finished || _errorDetail != null)
                ? () => Navigator.of(context).maybePop()
                : _confirmCancel,
            icon: const Icon(Icons.arrow_forward_rounded, size: 20),
            tooltip: context.l10n.t('common_back'),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.t('progress_title'),
                  key: const ValueKey('auto_edit_progress_title'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                    '${context.l10n.t('progress_session_prefix')} $_sessionId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final questions = _pendingQuestions;
    if (questions != null && _errorDetail == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(tokens.Spacing.lg),
        child: _QuestionCard(
          key: const ValueKey('director_questions'),
          event: questions,
          busy: _submittingQuestions,
          onSubmit: _submitQuestions,
        ),
      );
    }
    if (_restarting) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_errorDetail != null) return _buildErrorCard();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
          horizontal: tokens.Spacing.xl, vertical: tokens.Spacing.sm),
      itemCount: _kStages.length,
      itemBuilder: (context, i) => _buildStageRow(i),
    );
  }

  Widget _buildStageRow(int i) {
    final idx = _currentIndex;
    final isDone = idx > i;
    final isActive = idx == i;

    final icon = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? AppColors.secondary.withValues(alpha: 0.18)
            : isActive
                ? AppColors.warning.withValues(alpha: 0.18)
                : AppColors.surfaceVariant,
        border: Border.all(
          color: isDone
              ? AppColors.secondary
              : isActive
                  ? AppColors.warning
                  : AppColors.border,
        ),
      ),
      child: isDone
          ? const Icon(Icons.check_rounded,
              size: 17, color: AppColors.secondary)
          : isActive
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: Padding(
                    padding: EdgeInsets.all(3),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.warning),
                  ),
                )
              : const Icon(Icons.circle_outlined,
                  size: 12, color: AppColors.textMuted),
    );

    final label = Text(
      context.l10n.t('stage_${_kStages[i].$1}'),
      style: TextStyle(
        fontSize: 14,
        fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
        color: isDone
            ? AppColors.textSecondary
            : isActive
                ? AppColors.textPrimary
                : AppColors.textMuted,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _PulsingIcon(active: isActive, child: icon),
          const SizedBox(width: tokens.Spacing.md),
          Expanded(child: label),
        ]),
        if (isActive && (_last?.messageAr.isNotEmpty ?? false))
          Padding(
            padding: const EdgeInsetsDirectional.only(
                start: 42, top: tokens.Spacing.xs),
            child: Text(_last!.messageAr,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ),
        if (i < _kStages.length - 1)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14),
            child: Container(width: 2, height: 16, color: AppColors.border),
          ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(tokens.Spacing.xl),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: AppDecorations.card.copyWith(
            border:
                Border.all(color: AppColors.destructive.withValues(alpha: 0.6)),
          ),
          padding: const EdgeInsets.all(tokens.Spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppColors.destructive),
              const SizedBox(height: tokens.Spacing.sm),
              Text(context.l10n.t('progress_error_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: tokens.Spacing.sm),
              Text(_errorDetail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: tokens.Spacing.lg),
              // Wrap (not Row): the retry/close pair must never overflow the
              // narrow error card regardless of button label/padding sizes.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: tokens.Spacing.md,
                runSpacing: tokens.Spacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('wizard_retry'),
                    style: AppButtonStyle.outlined(),
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(context.l10n.t('progress_retry')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(context.l10n.t('common_close')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: AppDecorations.toolbar.copyWith(
        border: const Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: tokens.Spacing.lg, vertical: tokens.Spacing.md),
      child: OutlinedButton.icon(
        style: AppButtonStyle.outlined(color: AppColors.destructive),
        onPressed: _confirmCancel,
        icon: const Icon(Icons.cancel_outlined, size: 16),
        label: Text(context.l10n.t('progress_cancel_button')),
      ),
    );
  }
}

/// أسئلة اختيارية قصيرة يطرحها المخرج الذكي قبل الرندر. كل سؤال له
/// اختيارات متعددة، ويمكن إرسال بعض الإجابات أو تخطي الكل.
class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    super.key,
    required this.event,
    required this.busy,
    required this.onSubmit,
  });

  final AutoEditEvent event;
  final bool busy;
  final Future<void> Function(List<AutoEditQuestionAnswer>) onSubmit;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  final Map<String, String> _selected = {};

  @override
  void initState() {
    super.initState();
    // اختيار التوصية مسبقًا يخلي «ابدأ المونتاج» جاهزًا بضغطة واحدة،
    // مع إمكانية تغييرها أو تخطي الأسئلة كلها.
    for (final question in widget.event.questions ?? const <AutoEditQuestion>[]) {
      final recommended = question.recommended;
      if (recommended != null &&
          question.options.any((option) => option.id == recommended)) {
        _selected[question.id] = recommended;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.event.questions ?? const <AutoEditQuestion>[];
    return Container(
      decoration: AppDecorations.card,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.forum_outlined, size: 30, color: AppColors.primary),
          const SizedBox(height: 8),
          const Text(
            'قبل ما نبدأ المونتاج',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'اختيارات سريعة تساعدنا نطلع أفضل نسخة — أو تخطَّ الأسئلة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          for (final question in questions) ...[
            Text(
              question.question,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 7,
              runSpacing: 4,
              children: [
                for (final option in question.options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _selected[question.id] == option.id,
                    onSelected: widget.busy
                        ? null
                        : (_) => setState(
                            () => _selected[question.id] = option.id,
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: widget.busy || _selected.isEmpty
                ? null
                : () => widget.onSubmit([
                      for (final entry in _selected.entries)
                        AutoEditQuestionAnswer(
                          questionId: entry.key,
                          optionId: entry.value,
                        ),
                    ]),
            child: widget.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ابدأ المونتاج'),
          ),
          TextButton(
            onPressed: widget.busy ? null : () => widget.onSubmit(const []),
            child: const Text('تخطَّ الأسئلة'),
          ),
        ],
      ),
    );
  }
}

/// نبض خفيف (تكبير/تصغير متكرر) على أيقونة المرحلة النشطة.
class _PulsingIcon extends StatefulWidget {
  final bool active;
  final Widget child;

  const _PulsingIcon({required this.active, required this.child});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingIcon old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.12).animate(CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      )),
      child: widget.child,
    );
  }
}
