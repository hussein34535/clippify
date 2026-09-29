import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/backend/auto_edit_api.dart';
import '../wizard/auto_edit_progress_screen.dart'
    show AutoEditProgressScreen, defaultAutoEditApi;
import 'library_mobile_page.dart' show defaultPickVideos;

/// Converts the wizard's answers map (docs/CONTRACTS.md → POST /api/auto-edit
/// body.answers) into the typed [AutoEditAnswers]. Built field-by-field
/// because the class intentionally has no fromJson.
AutoEditAnswers answersFromMap(Map<String, dynamic> m) => AutoEditAnswers(
      contentType: (m['content_type'] ?? 'auto') as String,
      platform: (m['platform'] ?? 'tiktok') as String,
      nClips: ((m['n_clips'] ?? 5) as num).toInt(),
      clipDurationSec: ((m['clip_duration_sec'] ?? 60) as num).toDouble(),
      captionTheme: m['caption_theme'] as String?,
      music: (m['music'] ?? false) as bool,
      broll: (m['broll'] ?? true) as bool,
      translateArabic: (m['translate_arabic'] ?? false) as bool,
      customInstructions: (m['custom_instructions'] ?? '') as String,
    );

/// Answers shape mirrors POST /api/auto-edit → body.answers (docs/CONTRACTS.md).
Map<String, dynamic> defaultAutoEditAnswers() => <String, dynamic>{
      'content_type': 'auto',
      'platform': 'tiktok',
      'n_clips': 5,
      'clip_duration_sec': 60.0,
      'caption_theme': null, // null = حسب نوع المحتوى
      'music': false,
      'broll': true,
      'translate_arabic': false,
      'custom_instructions': '',
    };

const Map<String, String> _contentTypes = {
  'auto': 'تلقائي',
  'podcast': 'بودكاست',
  'comedy': 'كوميدي',
  'educational': 'تعليمي',
  'motivation': 'تحفيزي',
  'interview': 'مقابلة',
  'awareness': 'توعوي',
  'gaming': 'قيمنق',
};

const Map<String, String> _platforms = {
  'tiktok': 'تيك توك',
  'shorts': 'شورتس',
  'reels': 'ريلز',
  'square': 'مربع',
};

const Map<String?, String> _captionThemes = {
  null: 'تلقائي',
  'TikTok Yellow': 'أصفر تيك توك',
  'Neon': 'نيون',
  'Minimal': 'مينيمال',
  'Bold White': 'أبيض عريض',
};

/// Mobile auto-edit wizard: produces an AutoEditAnswers-shaped map
/// identical to the desktop/API contract (docs/CONTRACTS.md), then starts
/// the session itself and pushes AutoEditProgressScreen on success.
class WizardPageMobile extends StatefulWidget {
  final String? initialVideoPath;

  /// Injectable for tests — defaults to the shared [defaultAutoEditApi].
  final AutoEditApi? api;

  final Future<List<String>> Function() pickVideos;

  const WizardPageMobile({
    super.key,
    this.initialVideoPath,
    this.api,
    this.pickVideos = defaultPickVideos,
  });

  @override
  State<WizardPageMobile> createState() => _WizardPageMobileState();
}

class _WizardPageMobileState extends State<WizardPageMobile> {
  late final Map<String, dynamic> _answers = defaultAutoEditAnswers();
  String? _videoPath;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _videoPath = widget.initialVideoPath;
  }

  Future<void> _chooseVideo() async {
    try {
      final paths = await widget.pickVideos();
      if (!mounted || paths.isEmpty) return;
      setState(() => _videoPath = paths.first);
    } catch (e) {
      debugPrint('[WizardMobile] pick failed: $e');
    }
  }

  Future<void> _submit() async {
    final path = _videoPath;
    if (path == null || path.isEmpty || _submitting) return;
    final api = widget.api ?? defaultAutoEditApi();
    final answers = answersFromMap(_answers);
    setState(() => _submitting = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final sessionId = await api.start(path, answers);
    if (!mounted) return;
    if (sessionId == null || sessionId.isEmpty) {
      setState(() => _submitting = false);
      messenger.showSnackBar(const SnackBar(
        content: Text('فشل بدء المونتاج — تأكد من تشغيل الباك إند ومن توفر رصيد كافٍ.'),
      ));
      return;
    }
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => AutoEditProgressScreen(
        sessionId: sessionId,
        videoPath: path,
        answers: answers,
        api: api,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          // SingleChildScrollView (not ListView): the form is short and we
          // want all fields materialized eagerly.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0A84FF), Color(0xFFBF5AF2)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'حمّل فيديو… واستلم مقاطع جاهزة للنشر 🔥',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: Icon(
                    _videoPath == null
                        ? Icons.video_library_outlined
                        : Icons.check_circle,
                    color:
                        _videoPath == null ? scheme.primary : scheme.secondary,
                  ),
                  title: Text(_videoPath == null
                      ? 'اختر فيديو'
                      : p.basename(_videoPath!)),
                  subtitle: _videoPath == null ? const Text('MP4 / MOV') : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseVideo,
                ),
              ),
              _section(
                context,
                'نوع المحتوى',
                _chipGroup(
                  _contentTypes,
                  (v) => setState(() => _answers['content_type'] = v),
                  selected: _answers['content_type'] as String,
                ),
              ),
              _section(
                context,
                'المنصة',
                _chipGroup(
                  _platforms,
                  (v) => setState(() => _answers['platform'] = v),
                  selected: _answers['platform'] as String,
                ),
              ),
              _section(
                context,
                'عدد المقاطع: ${_answers['n_clips']}',
                Slider(
                  value: (_answers['n_clips'] as num).toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '${_answers['n_clips']}',
                  onChanged: (v) =>
                      setState(() => _answers['n_clips'] = v.round()),
                ),
              ),
              _section(
                context,
                'مدة المقطع: ${(_answers['clip_duration_sec'] as num).round()} ثانية',
                Slider(
                  value: (_answers['clip_duration_sec'] as num).toDouble(),
                  min: 15,
                  max: 180,
                  divisions: 33,
                  label: '${(_answers['clip_duration_sec'] as num).round()}s',
                  onChanged: (v) =>
                      setState(() => _answers['clip_duration_sec'] = v.roundToDouble()),
                ),
              ),
              _section(
                context,
                'ثيم الترجمة',
                _chipGroupNullable(
                  _captionThemes,
                  (v) => setState(() => _answers['caption_theme'] = v),
                  selected: _answers['caption_theme'] as String?,
                ),
              ),
              _section(
                context,
                'خيارات',
                Column(
                  children: [
                    SwitchListTile(
                      title: const Text('موسيقى خلفية'),
                      value: _answers['music'] as bool,
                      onChanged: (v) => setState(() => _answers['music'] = v),
                    ),
                    SwitchListTile(
                      title: const Text('B-Roll تلقائي'),
                      value: _answers['broll'] as bool,
                      onChanged: (v) => setState(() => _answers['broll'] = v),
                    ),
                    SwitchListTile(
                      title: const Text('ترجمة للعربية'),
                      value: _answers['translate_arabic'] as bool,
                      onChanged: (v) =>
                          setState(() => _answers['translate_arabic'] = v),
                    ),
                  ],
                ),
              ),
              _section(
                context,
                'تعليمات إضافية (اختياري)',
                TextField(
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'مثال: ركز على اللحظات المضحكة…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) =>
                      setState(() => _answers['custom_instructions'] = v),
                ),
              ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_videoPath == null || _submitting) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('ابدأ المونتاج'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  Widget _chipGroup(
    Map<String, String> options,
    ValueChanged<String> onSelect, {
    required String selected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries
          .map((e) => ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onSelect(e.key),
              ))
          .toList(),
    );
  }

  Widget _chipGroupNullable(
    Map<String?, String> options,
    ValueChanged<String?> onSelect, {
    required String? selected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries
          .map((e) => ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onSelect(e.key),
              ))
          .toList(),
    );
  }
}
