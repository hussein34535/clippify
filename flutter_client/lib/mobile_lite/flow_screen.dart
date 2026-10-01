import 'package:flutter/material.dart';

import '../features/mobile/library_mobile_page.dart' show defaultPickVideos;
import 'models.dart';

/// مساعد المونتاج: 4 أسئلة ببطاقات كبيرة → اختيار فيديو → مراجعة → تشغيل.
/// بسيط عمدًا: لا تايملاين، لا إعدادات، المساعد يقرر كل شيء.
class LiteFlowScreen extends StatefulWidget {
  final void Function(LiteAnswers answers, String videoPath) onReady;

  const LiteFlowScreen({super.key, required this.onReady});

  @override
  State<LiteFlowScreen> createState() => _LiteFlowScreenState();
}

class _LiteFlowScreenState extends State<LiteFlowScreen> {
  int _step = 0;
  LiteAnswers _answers = const LiteAnswers();
  String? _videoPath;
  String? _videoName;

  static const _titles = [
    'إيه المنصة؟',
    'الفيديو عن إيه؟',
    'عايزه طوله قد إيه؟',
    'اللمسات الأخيرة',
    'اختار الفيديو',
    'كله جاهز',
  ];

  void _next() {
    if (_step < _titles.length - 1) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _step > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _back,
              )
            : null,
        title: Text(_titles[_step]),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return _cards<LitePlatform>(
          const [
            (LitePlatform.tiktok, 'تيك توك', Icons.music_note_rounded),
            (LitePlatform.shorts, 'شورتس', Icons.play_circle_rounded),
            (LitePlatform.reels, 'ريلز', Icons.movie_rounded),
            (LitePlatform.youtube, 'يوتيوب', Icons.smart_display_rounded),
          ],
          _answers.platform,
          (v) => setState(() {
            _answers = _answers.copyWith(platform: v);
            _next();
          }),
        );
      case 1:
        return _cards<LiteContent>(
          const [
            (LiteContent.auto, 'هو يقرر', Icons.auto_awesome_rounded),
            (LiteContent.podcast, 'بودكاست', Icons.mic_rounded),
            (LiteContent.comedy, 'كوميدي', Icons.sentiment_very_satisfied_rounded),
            (LiteContent.educational, 'تعليمي', Icons.school_rounded),
            (LiteContent.motivation, 'تحفيزي', Icons.bolt_rounded),
            (LiteContent.interview, 'مقابلة', Icons.people_rounded),
          ],
          _answers.content,
          (v) => setState(() {
            _answers = _answers.copyWith(content: v);
            _next();
          }),
        );
      case 2:
        return _cards<LiteLength>(
          const [
            (LiteLength.short, 'قصير (~30 ث)', Icons.flash_on_rounded),
            (LiteLength.medium, 'متوسط (~دقيقة)', Icons.timer_rounded),
            (LiteLength.long, 'طويل (دقائق)', Icons.hourglass_full_rounded),
          ],
          _answers.length,
          (v) => setState(() {
            _answers = _answers.copyWith(length: v);
            _next();
          }),
        );
      case 3:
        return _touches();
      case 4:
        return _pick();
      default:
        return _review();
    }
  }

  Widget _cards<T>(
    List<(T, String, IconData)> items,
    T selected,
    void Function(T) onPick,
  ) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final (value, label, icon) = items[i];
        final isSel = value == selected;
        return Card(
          color: isSel
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPick(value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              child: Row(
                children: [
                  Icon(icon, size: 28),
                  const SizedBox(width: 14),
                  Text(label, style: const TextStyle(fontSize: 18)),
                  const Spacer(),
                  if (isSel) const Icon(Icons.check_circle_rounded),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _touches() {
    return ListView(
      children: [
        const Text('الكابشن', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final c in LiteCaptions.values)
              ChoiceChip(
                label: Text(_captionLabel(c)),
                selected: _answers.captions == c,
                onSelected: (_) =>
                    setState(() => _answers = _answers.copyWith(captions: c)),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SwitchListTile(
          title: const Text('موسيقى خلفية هادئة'),
          value: _answers.music,
          onChanged: (v) =>
              setState(() => _answers = _answers.copyWith(music: v)),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _next,
          child: const Text('كمّل لاختيار الفيديو'),
        ),
      ],
    );
  }

  static String _captionLabel(LiteCaptions c) => switch (c) {
        LiteCaptions.auto => 'تلقائي',
        LiteCaptions.yellow => 'أصفر',
        LiteCaptions.neon => 'نيون',
        LiteCaptions.minimal => 'هادئ',
        LiteCaptions.white => 'أبيض عريض',
      };

  Widget _pick() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.video_library_rounded, size: 64),
                const SizedBox(height: 12),
                Text(
                  _videoName ?? 'اختار فيديو من جهازك',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),
        FilledButton.tonal(
          onPressed: () async {
            final paths = await pickVideoFile();
            if (paths.isNotEmpty && mounted) {
              setState(() {
                _videoPath = paths.first;
                _videoName =
                    paths.first.split(RegExp(r'[\\/]')).last;
              });
            }
          },
          child: Text(_videoPath == null ? 'اختار فيديو' : 'غيّر الفيديو'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _videoPath == null
              ? null
              : () => setState(() => _step++),
          child: const Text('راجع وابدأ'),
        ),
      ],
    );
  }

  Widget _review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 40),
                const SizedBox(height: 12),
                Text(
                  liteSummaryAr(_answers),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17),
                ),
                const SizedBox(height: 8),
                Text(
                  _videoName ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        const Text(
          'المساعد هيقص الصمت، يظبط الإيقاع والكابشن، ويطلع لك المقاطع — أنت بس استنى.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _videoPath == null
              ? null
              : () => widget.onReady(_answers, _videoPath!),
          child: const Text('يلا ابدأ المونتاج'),
        ),
      ],
    );
  }
}

/// اختيار ملف فيديو — يُحقن في الاختبارات.
Future<List<String>> Function() pickVideoFile = defaultPickVideos;
