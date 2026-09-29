import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend/auto_edit_api.dart';
import '../../core/backend/backend_service.dart' show service;
import '../../core/theme/app_theme.dart';
import '../../shared/l10n/context_l10n.dart';
import '../../shared/providers/toast_provider.dart';
import 'auto_edit_progress_screen.dart';

// TODO(l10n): top-level const tables have no BuildContext — Arabic labels kept
// as-is; localized labels are resolved at render sites via l10n.t(id keys).
const List<(String, String)> _kContentTypes = [
  ('auto', 'اكتشاف تلقائي ✨'),
  ('podcast', 'بودكاست'),
  ('comedy', 'كوميديا'),
  ('educational', 'تعليمي'),
  ('motivation', 'تحفيز'),
  ('interview', 'مقابلة'),
  ('awareness', 'توعوي'),
  ('gaming', 'جيمنج'),
];

const List<(String, String, IconData)> _kPlatforms = [
  ('tiktok', 'تيك توك', Icons.music_note_rounded),
  ('shorts', 'شورتس', Icons.play_arrow_rounded),
  ('reels', 'ريلز', Icons.camera_alt_outlined),
  ('square', 'مربع ١:١', Icons.crop_square_rounded),
];

const List<(String?, String)> _kCaptionThemes = [
  (null, 'افتراضي ذكي'),
  ('TikTok Yellow', 'TikTok Yellow'),
  ('Minimalist Clean', 'Minimalist Clean'),
  ('Cyberpunk Neon', 'Cyberpunk Neon'),
  ('Bold Impact', 'Bold Impact'),
];

class AutoEditWizardDialog extends StatefulWidget {
  final String videoPath;
  final AutoEditApi api;

  const AutoEditWizardDialog({
    super.key,
    required this.videoPath,
    required this.api,
  });

  @override
  State<AutoEditWizardDialog> createState() => _AutoEditWizardDialogState();
}

class _AutoEditWizardDialogState extends State<AutoEditWizardDialog> {
  AutoEditAnswers _ans = const AutoEditAnswers();
  int _currentStep = 0;
  bool _submitting = false;
  late final TextEditingController _instructionsCtrl;
  TextEditingController? _briefCtrl;

  @override
  void initState() {
    super.initState();
    _instructionsCtrl = TextEditingController(text: _ans.customInstructions);
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    _briefCtrl?.dispose();
    super.dispose();
  }

  void _patch({
    String? contentType,
    String? platform,
    int? nClips,
    double? clipDurationSec,
    bool? music,
    bool? broll,
    bool? translateArabic,
    String? customInstructions,
    String? Function()? captionTheme,
  }) {
    setState(() {
      _ans = AutoEditAnswers(
        contentType: contentType ?? _ans.contentType,
        platform: platform ?? _ans.platform,
        nClips: nClips ?? _ans.nClips,
        clipDurationSec: clipDurationSec ?? _ans.clipDurationSec,
        music: music ?? _ans.music,
        broll: broll ?? _ans.broll,
        translateArabic: translateArabic ?? _ans.translateArabic,
        customInstructions: customInstructions ?? _ans.customInstructions,
        captionTheme:
            captionTheme != null ? captionTheme() : _ans.captionTheme,
      );
    });
  }

  // ---- Paste-brief (POST /api/brief/parse) -------------------------------
  // TODO(l10n): نصوص هذه الميزة عربية مؤقتاً إلى حين إضافة مفاتيح app_strings.

  /// يرسل نص البريف إلى POST /api/brief/parse ويعبّئ حقول المعالج عند النجاح.
  /// يعيد true فقط عند نجاح التحليل والتعبئة؛ 404 ⇒ توست «قادمة قريباً».
  Future<bool> _parseBrief(String text) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final toast = container.read(toastProvider.notifier);
    try {
      final res = await Dio(BaseOptions(
        baseUrl: service.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      )).post<Map<String, dynamic>>(
        '/api/brief/parse',
        data: {'brief_text': text},
      );
      final m = _unwrapBrief(res.data ?? const {});
      final ct = _briefStr(m, const ['content_type', 'contentType']);
      final pl = _briefStr(m, const ['platform']);
      final theme = _briefStr(m, const ['caption_theme', 'captionTheme']);
      final instructions =
          _briefStr(m, const ['custom_instructions', 'customInstructions']);
      final nClips = _briefNum(m, const ['n_clips', 'nClips']);
      final dur = _briefNum(m, const ['clip_duration_sec', 'clipDurationSec']);
      final music = _briefFlag(m, const ['music']);
      final broll = _briefFlag(m, const ['broll', 'b_roll', 'bRoll']);
      final trAr = _briefFlag(m, const ['translate_arabic', 'translateArabic']);

      String? validCt;
      if (ct != null && _kContentTypes.any((e) => e.$1 == ct)) validCt = ct;
      String? validPl;
      if (pl != null && _kPlatforms.any((e) => e.$1 == pl)) validPl = pl;

      if (!mounted) return false;
      setState(() {
        _ans = AutoEditAnswers(
          contentType: validCt ?? _ans.contentType,
          platform: validPl ?? _ans.platform,
          nClips: nClips?.round().clamp(1, 10) ?? _ans.nClips,
          clipDurationSec:
              dur?.clamp(15.0, 180.0).toDouble() ?? _ans.clipDurationSec,
          music: music ?? _ans.music,
          broll: broll ?? _ans.broll,
          translateArabic: trAr ?? _ans.translateArabic,
          customInstructions: instructions ?? _ans.customInstructions,
          captionTheme: theme ?? _ans.captionTheme,
        );
      });
      if (instructions != null) _instructionsCtrl.text = instructions;
      toast.success('تم تحليل البريف وتعبئة إعدادات المعالج ✅');
      return true;
    } on DioException catch (e) {
      if (!mounted) return false;
      if (e.response?.statusCode == 404) {
        toast.info('الميزة قادمة قريباً');
      } else {
        debugPrint('[Wizard] brief parse failed: ${e.message}');
        toast.error('تعذّر تحليل البريف — حاول مجدداً');
      }
      return false;
    } catch (e) {
      debugPrint('[Wizard] brief parse failed: $e');
      if (mounted) toast.error('تعذّر تحليل البريف — حاول مجدداً');
      return false;
    }
  }

  Future<void> _openBriefDialog() async {
    final l10n = context.l10n; // captured before opening the dialog route
    final briefCtrlRef = _briefCtrl ??= TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var parsing = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              side: const BorderSide(color: AppColors.border),
            ),
            title: const Text('📋 لصق بريف حملة',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            content: TextField(
              key: const ValueKey('wizard_brief_field'),
              controller: briefCtrlRef,
              autofocus: true,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText:
                    'الصق نص البريف: نوع المحتوى، المنصة، عدد المقاطع، الأسلوب...',
                counterStyle:
                    TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l10n.t('common_cancel')),
              ),
              ElevatedButton(
                onPressed: parsing
                    ? null
                    : () async {
                        final text = briefCtrlRef.text.trim();
                        if (text.isEmpty) return;
                        setDialogState(() => parsing = true);
                        final ok = await _parseBrief(text);
                        if (!ctx.mounted) return;
                        if (ok) Navigator.of(ctx).pop();
                        setDialogState(() => parsing = false);
                      },
                child: parsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('تحليل وتعبئة',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
      },
    );
  }

  static Map<String, dynamic> _unwrapBrief(Map<String, dynamic> m) {
    for (final k in const ['settings', 'answers', 'brief', 'data']) {
      final v = m[k];
      if (v is Map) return v.cast<String, dynamic>();
    }
    return m;
  }

  static String? _briefStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  static num? _briefNum(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v;
      if (v is String) {
        final parsed = num.tryParse(v);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static bool? _briefFlag(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.toLowerCase();
        if (s == 'true' || s == '1') return true;
        if (s == 'false' || s == '0') return false;
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final l10n = context.l10n; // captured before async gap
    setState(() => _submitting = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final nav = Navigator.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    final sessionId =
        await widget.api.start(widget.videoPath, _ans);
    if (!mounted) return;
    if (sessionId == null || sessionId.isEmpty) {
      container.read(toastProvider.notifier).error(
          l10n.t('wizard_error_start_failed'));
      setState(() => _submitting = false);
      return;
    }
    nav.pop();
    rootNav.push(MaterialPageRoute(
      builder: (_) => AutoEditProgressScreen(
        sessionId: sessionId,
        videoPath: widget.videoPath,
        answers: _ans,
        api: widget.api,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = (size.width * 0.92).clamp(280.0, 520.0);
    final height = (size.height * 0.92).clamp(420.0, 640.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: width,
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const Divider(height: 1, color: AppColors.borderSubtle),
              Expanded(
                child: Stepper(
                  currentStep: _currentStep,
                  physics: const ClampingScrollPhysics(),
                  onStepTapped: (i) => setState(() => _currentStep = i),
                  onStepContinue: _currentStep < 2
                      ? () => setState(() => _currentStep++)
                      : null,
                  onStepCancel: _currentStep > 0
                      ? () => setState(() => _currentStep--)
                      : null,
                  controlsBuilder: (context, details) {
                    if (_currentStep >= 2) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: details.onStepContinue,
                          icon: const Icon(Icons.arrow_left_rounded, size: 18),
                          label: Text(context.l10n.t('wizard_continue'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    );
                  },
                  steps: [
                    Step(
                      title: Text(context.l10n.t('wizard_step_content'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      isActive: true,
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.indexed,
                      content: _buildContentStep(),
                    ),
                    Step(
                      title: Text(context.l10n.t('wizard_step_shape'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      isActive: _currentStep >= 1,
                      state: _currentStep > 1
                          ? StepState.complete
                          : StepState.indexed,
                      content: _buildShapeStep(),
                    ),
                    Step(
                      title: Text(context.l10n.t('wizard_step_style'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      isActive: _currentStep >= 2,
                      state: StepState.indexed,
                      content: _buildStyleStep(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.borderSubtle),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.t('wizard_title'),
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            tooltip: context.l10n.t('common_close'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _buildContentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // زر البريف مدمج مع صف عنوان القسم حتى لا يتغير ارتفاع الخطوة
        // (اختبارات الـ wizard تعتمد على بقاء زر «متابعة» في نطاق النقر).
        // TODO(l10n): نص الزر عربي مؤقت إلى حين إضافة مفاتيح app_strings.
        Row(
          children: [
            Expanded(
              child: _buildSectionTitle(
                  context.l10n.t('wizard_section_content_type')),
            ),
            TextButton.icon(
              key: const ValueKey('wizard_brief_btn'),
              onPressed: _openBriefDialog,
              style: TextButton.styleFrom(
                visualDensity:
                    const VisualDensity(horizontal: -4, vertical: -4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: const Size(0, 26),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.content_paste_go_rounded,
                  size: 14, color: AppColors.primary),
              label: const Text('📋 لصق بريف حملة',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
          ],
        ),
        _buildSectionTitle(context.l10n.t('wizard_section_content_type')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kContentTypes.map((ct) {
            final selected = _ans.contentType == ct.$1;
            return ChoiceChip(
              label: Text(context.l10n.t('wizard_content_${ct.$1}')),
              selected: selected,
              onSelected: (_) => _patch(contentType: ct.$1),
              selectedColor: AppColors.primary.withValues(alpha: 0.35),
              backgroundColor: AppColors.surfaceVariant,
              labelStyle: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(context.l10n.t('wizard_section_platform')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kPlatforms.map((pl) {
            final selected = _ans.platform == pl.$1;
            return ChoiceChip(
              avatar: Icon(pl.$3,
                  size: 16, color: selected ? Colors.white : AppColors.primary),
              label: Text(context.l10n.t('wizard_platform_${pl.$1}')),
              selected: selected,
              onSelected: (_) => _patch(platform: pl.$1),
              selectedColor: AppColors.primary.withValues(alpha: 0.35),
              backgroundColor: AppColors.surfaceVariant,
              labelStyle: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : AppColors.textSecondary,
              ),
              side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildShapeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.t('wizard_n_clips'),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text('${_ans.nClips} ${context.l10n.t('unit_clips')}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ],
        ),
        Slider(
          value: _ans.nClips.toDouble(),
          min: 1,
          max: 10,
          divisions: 9,
          label: '${_ans.nClips}',
          onChanged: (v) => _patch(nClips: v.round()),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.t('wizard_clip_duration'),
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
            Text(
                '${_ans.clipDurationSec.round()} ${context.l10n.t('unit_seconds')}',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ],
        ),
        Slider(
          value: _ans.clipDurationSec.clamp(15, 180),
          min: 15,
          max: 180,
          label:
              '${_ans.clipDurationSec.round()} ${context.l10n.t('unit_seconds')}',
          onChanged: (v) => _patch(clipDurationSec: v),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.t('wizard_translate_arabic'),
                  style: const TextStyle(fontSize: 13)),
            ),
            Switch(value: _ans.translateArabic, onChanged: (v) => _patch(translateArabic: v)),
          ],
        ),
      ],
    );
  }

  Widget _buildStyleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.t('wizard_music'),
                  style: const TextStyle(fontSize: 13)),
            ),
            Switch(value: _ans.music, onChanged: (v) => _patch(music: v)),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(context.l10n.t('wizard_broll'),
                  style: const TextStyle(fontSize: 13)),
            ),
            Switch(value: _ans.broll, onChanged: (v) => _patch(broll: v)),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _ans.captionTheme,
          decoration: InputDecoration(
              labelText: context.l10n.t('wizard_label_caption_theme')),
          items: _kCaptionThemes
              .map((t) => DropdownMenuItem<String?>(
                    value: t.$1,
                    child: Text(
                        // TODO(l10n): brand-name themes stay verbatim; only the
                        // null-id default entry is localized.
                        t.$1 == null
                            ? context.l10n.t('wizard_caption_default')
                            : t.$2,
                        style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) =>
              _patch(captionTheme: () => v),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _instructionsCtrl,
          maxLines: 3,
          maxLength: 300,
          onChanged: (v) => _ans =
              AutoEditAnswers(
                contentType: _ans.contentType,
                platform: _ans.platform,
                nClips: _ans.nClips,
                clipDurationSec: _ans.clipDurationSec,
                music: _ans.music,
                broll: _ans.broll,
                translateArabic: _ans.translateArabic,
                customInstructions: v,
                captionTheme: _ans.captionTheme,
              ),
          decoration: InputDecoration(
            hintText: context.l10n.t('wizard_instructions_hint'),
            counterStyle:
                const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          TextButton(
            onPressed: _submitting
                ? null
                : () {
                    if (_currentStep == 0) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _currentStep--);
                    }
                  },
            child: Text(_currentStep == 0
                ? context.l10n.t('common_cancel')
                : context.l10n.t('common_back')),
          ),
          const Spacer(),
          _GradientSubmitButton(
            key: const ValueKey('wizard_submit'),
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(context.l10n.t('wizard_start'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _GradientSubmitButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const _GradientSubmitButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.secondary]),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

Future<void> showAutoEditWizardDialog(
  BuildContext context, {
  required String videoPath,
  AutoEditApi? api,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AutoEditWizardDialog(
      videoPath: videoPath,
      api: api ?? defaultAutoEditApi(),
    ),
  );
}
