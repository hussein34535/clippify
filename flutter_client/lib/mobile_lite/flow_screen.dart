import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'reel_art.dart';
import 'short_provider_settings.dart';
import 'studio_theme.dart';

/// شاشة واحدة لاختيار فيديو وتجهيز مقطع قصير تلقائيًا.
class LiteFlowScreen extends StatefulWidget {
  final void Function(LiteAnswers answers, String videoPath) onReady;
  final VoidCallback? onProviderSettings;
  final bool uploadsVideo;
  final bool supportsAiDirector;

  const LiteFlowScreen({
    super.key,
    required this.onReady,
    this.onProviderSettings,
    this.uploadsVideo = true,
    this.supportsAiDirector = false,
    this.readProviderAccess = ShortProviderSettings.access,
    this.grantVisionConsent = ShortProviderSettings.grantVision,
  });

  /// Test seam: what an AI-directed run still needs (provider / frame consent).
  final Future<ShortAiAccess> Function() readProviderAccess;

  /// Test seam: stores the explicit yes to sharing video frames.
  final Future<void> Function() grantVisionConsent;

  @override
  State<LiteFlowScreen> createState() => _LiteFlowScreenState();
}

class _LiteFlowScreenState extends State<LiteFlowScreen> {
  late LiteAnswers _answers = widget.supportsAiDirector
      ? const LiteAnswers(director: LiteDirector.ai, zoom: LiteZoom.auto)
      : const LiteAnswers();
  bool get _aiDirected => _answers.director == LiteDirector.ai;
  String? _videoPath;
  bool _isPickingVideo = false;
  bool _starting = false;

  Future<void> _pickVideo() async {
    setState(() => _isPickingVideo = true);
    String? pickedPath;
    try {
      final paths = await pickVideoFile();
      pickedPath = paths.firstOrNull;
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر فتح اختيار الفيديو. حاول تاني.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _videoPath = pickedPath ?? _videoPath;
          _isPickingVideo = false;
        });
      }
    }
  }

  /// يسأل عن إذن مشاركة الصور قبل تشغيل مخرج AI، ويرجّع الإجابات النهائية
  /// (أو null لو المستخدم ألغى). رفض المشاركة يكمل بالمونتاج المحلي.
  Future<LiteAnswers?> _gateAiConsent() async {
    if (!_aiDirected || !widget.supportsAiDirector) return _answers;

    ShortAiAccess access;
    try {
      access = await widget.readProviderAccess();
    } on Exception {
      access = ShortAiAccess.unconfigured;
    }
    if (!mounted) return null;

    if (access == ShortAiAccess.unconfigured) {
      final choice = await _askGate(
        title: 'مخرج AI محتاج مزوّد',
        body:
            'فعّل مزوّد الذكاء الاصطناعي واحفظ المفتاح الأول، أو كمّل بالمونتاج '
            'المحلي من غير مشاركة صور.',
        primaryLabel: 'افتح الإعدادات',
        primaryChoice: _GateChoice.settings,
      );
      if (!mounted || choice == null) return null;
      if (choice == _GateChoice.settings) {
        widget.onProviderSettings?.call();
        return null;
      }
      if (choice == _GateChoice.local) {
        setState(
          () => _answers = _answers.copyWith(director: LiteDirector.local),
        );
      }
      return _answers;
    }

    if (access == ShortAiAccess.needsVisionConsent) {
      final choice = await _askGate(
        title: 'إذن إرسال صور من الفيديو',
        body:
            'مخرج AI بيحتاج يشوف لحد ١٨ صورة مصغّرة من الفيديو، مع مقتطفات '
            'الكلام، عشان يختار القص والكادر. الصور بتتبعت للمزوّد السحابي، '
            'والمونتاج والرندر بيتمّوا على جهازك. تقدر تلغي الإذن في أي وقت '
            'من إعدادات الذكاء الاصطناعي.',
        primaryLabel: 'أوافق وأكمل',
        primaryChoice: _GateChoice.allow,
      );
      if (!mounted || choice == null) return null;
      if (choice == _GateChoice.local) {
        setState(
          () => _answers = _answers.copyWith(director: LiteDirector.local),
        );
        return _answers;
      }
      try {
        await widget.grantVisionConsent();
      } on Exception {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذّر حفظ الإذن. افتح إعدادات الذكاء الاصطناعي وفعّل '
              '«إرسال صور من الفيديو».',
            ),
          ),
        );
        return null;
      }
    }
    return _answers;
  }

  Future<_GateChoice?> _askGate({
    required String title,
    required String body,
    required String primaryLabel,
    required _GateChoice primaryChoice,
  }) {
    return showDialog<_GateChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _GateChoice.local),
            child: const Text('مونتاج محلي'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, primaryChoice),
            child: Text(primaryLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    final videoPath = _videoPath;
    if (videoPath == null || _starting) return;
    setState(() => _starting = true);
    try {
      final answers = await _gateAiConsent();
      if (!mounted || answers == null) return;
      widget.onReady(answers, videoPath);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final videoPath = _videoPath;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Clippify',
          textDirection: TextDirection.ltr,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (widget.onProviderSettings != null)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'إعدادات الذكاء الاصطناعي',
              onPressed: widget.onProviderSettings,
            ),
        ],
      ),
      body: StudioLayout(
        footer: FilledButton.icon(
          onPressed: _isPickingVideo || _starting
              ? null
              : videoPath == null
              ? _pickVideo
              : _start,
          icon: Icon(
            videoPath == null ? Icons.add_rounded : Icons.auto_awesome_outlined,
          ),
          label: Text(
            videoPath == null
                ? 'اختار فيديو'
                : _aiDirected
                ? 'ابدأ التحليل والمونتاج بالـAI'
                : 'يلا ابدأ المونتاج',
          ),
        ),
        children: [
          Text(
            'استوديو الريلز',
            style: text.labelLarge?.copyWith(color: studioAccent),
          ),
          const SizedBox(height: 8),
          Text(
            videoPath == null
                ? 'حوّل فيديوك لريل جاهز'
                : 'الفيديو جاهز للمونتاج',
            style: text.headlineMedium?.copyWith(
              height: 1.28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            videoPath == null
                ? 'اختار الفيديو، وخلّي Clippify يختار اللقطة ويعمل المونتاج.'
                : _aiDirected
                ? 'الـAI هيفهم المشهد ويختار طريقة المونتاج.'
                : 'اختار أسلوب الريل أو سيبنا نختاره تلقائيًا.',
            style: text.bodyMedium?.copyWith(color: studioMuted, height: 1.6),
          ),
          const SizedBox(height: 20),
          if (videoPath == null) ...[
            const ReelArt(),
            const SizedBox(height: 16),
            const Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _FormatLabel(
                  icon: Icons.aspect_ratio_outlined,
                  text: 'عمودي 9:16',
                ),
                _FormatLabel(
                  icon: Icons.movie_outlined,
                  text: 'ريلز · تيك توك · شورتس',
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Divider(height: 1, color: studioLine),
            const SizedBox(height: 16),
            Text('بعد المونتاج', style: text.titleSmall),
            const SizedBox(height: 4),
            Text(
              'اتفرّج على الريل هنا الأول، وبعدها احفظه أو شاركه.',
              style: text.bodyMedium?.copyWith(color: studioMuted, height: 1.6),
            ),
          ] else ...[
            _SelectedVideo(
              name: videoPath.split(RegExp(r'[\\/]')).last,
              onPick: _isPickingVideo ? null : _pickVideo,
            ),
            const SizedBox(height: 16),
            if (widget.supportsAiDirector) ...[
              Wrap(
                spacing: 7,
                children: [
                  for (final director in LiteDirector.values)
                    ChoiceChip(
                      label: Text(
                        director == LiteDirector.ai ? 'مخرج AI' : 'مونتاج محلي',
                      ),
                      selected: _answers.director == director,
                      onSelected: (_) => setState(
                        () => _answers = _answers.copyWith(director: director),
                      ),
                    ),
                ],
              ),
              if (_aiDirected)
                Text(
                  'التحليل يرسل حتى ١٨ صورة مصغّرة من الفيديو ومقتطفات من الكلام للمزوّد.',
                  style: text.bodySmall?.copyWith(color: studioMuted),
                ),
              const SizedBox(height: 8),
            ],
            if (!_aiDirected) ...[
              Text('أسلوب المونتاج', style: text.titleMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 2,
                children: [
                  for (final creative in LiteCreative.values)
                    ChoiceChip(
                      label: Text(creative.label),
                      selected: _answers.creative == creative,
                      onSelected: (_) => setState(
                        () => _answers = _answers.copyWith(creative: creative),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _buildOptions(),
            const SizedBox(height: 10),
            _editDirection(),
            if (widget.uploadsVideo) ...[
              const SizedBox(height: 12),
              const _FormatLabel(
                icon: Icons.cloud_upload_outlined,
                text: 'الفيديو هيترفع لخدمة المونتاج بعد ما تبدأ.',
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildOptions() {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.tune_rounded),
      title: const Text('إعدادات المقطع (اختياري)'),
      subtitle: Text(liteSummaryAr(_answers)),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('المنصة'),
        Wrap(
          spacing: 8,
          children: [
            for (final platform in const [
              LitePlatform.reels,
              LitePlatform.tiktok,
              LitePlatform.shorts,
            ])
              ChoiceChip(
                label: Text(platform.labelAr),
                selected: _answers.platform == platform,
                onSelected: (_) => setState(
                  () => _answers = _answers.copyWith(platform: platform),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('المدة المستهدفة'),
        Wrap(
          spacing: 8,
          children: [
            for (final length in LiteLength.values)
              ChoiceChip(
                label: Text('${length.seconds} ثانية'),
                selected: _answers.length == length,
                onSelected: (_) => setState(
                  () => _answers = _answers.copyWith(length: length),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _editDirection() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: const Icon(Icons.auto_awesome_outlined),
    title: const Text('توجيه المونتاج'),
    subtitle: const Text('اختياري: أوصف الستايل اللي عايزه'),
    expandedCrossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        initialValue: _answers.editBrief,
        onChanged: (value) => _answers = _answers.copyWith(editBrief: value),
        maxLength: 500,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'طلبك للمونتير',
          hintText: 'ألوان دافية، شيل السكتات، وزوم خفيف',
          alignLabelWithHint: true,
          border: OutlineInputBorder(),
        ),
      ),
      if (!_aiDirected && _answers.creative != LiteCreative.clean) ...[
        const SizedBox(height: 8),
        TextFormField(
          initialValue: _answers.creativeTitle,
          onChanged: (value) =>
              _answers = _answers.copyWith(creativeTitle: value),
          maxLength: 34,
          decoration: const InputDecoration(
            labelText: 'عنوان افتتاحي (اختياري)',
            border: OutlineInputBorder(),
          ),
        ),
        SwitchListTile(
          title: const Text('موسيقى أصلية للريل'),
          contentPadding: EdgeInsets.zero,
          value: _answers.creativeMusic,
          onChanged: (value) => setState(
            () => _answers = _answers.copyWith(creativeMusic: value),
          ),
        ),
        SwitchListTile(
          title: const Text('مؤثرات صوتية مع الحركة'),
          contentPadding: EdgeInsets.zero,
          value: _answers.creativeEffects,
          onChanged: (value) => setState(
            () => _answers = _answers.copyWith(creativeEffects: value),
          ),
        ),
      ],
      const SizedBox(height: 8),
      const Text('الزوم'),
      Wrap(
        spacing: 8,
        children: [
          for (final zoom in LiteZoom.values)
            ChoiceChip(
              label: Text(zoom.label),
              selected: _answers.zoom == zoom,
              onSelected: (_) =>
                  setState(() => _answers = _answers.copyWith(zoom: zoom)),
            ),
        ],
      ),
    ],
  );
}

enum _GateChoice { allow, local, settings }

class _SelectedVideo extends StatelessWidget {
  const _SelectedVideo({required this.name, required this.onPick});

  final String name;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: studioSurface,
      borderRadius: BorderRadius.all(Radius.circular(14)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الفيديو المختار',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.movie_outlined, color: studioAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          TextButton(onPressed: onPick, child: const Text('غيّر الفيديو')),
        ],
      ),
    ),
  );
}

class _FormatLabel extends StatelessWidget {
  const _FormatLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 17, color: studioMuted),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: studioMuted),
        ),
      ),
    ],
  );
}

/// اختيار ملف فيديو واحد — يُحقن في الاختبارات.
Future<List<String>> Function() pickVideoFile = () async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.video,
    allowMultiple: false,
  );
  return result?.paths.whereType<String>().toList() ?? [];
};
