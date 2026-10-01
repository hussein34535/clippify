/// إجابات مساعد الموبايل الخفيف — 4 أسئلة بسيطة تُترجم لإعدادات
/// المونتاج التلقائي كاملة (دون أن يرى المستخدم أي تعقيد).
enum LitePlatform { tiktok, shorts, reels, youtube }

enum LiteContent { auto, podcast, comedy, educational, motivation, interview }

enum LiteLength { short, medium, long }

enum LiteCaptions { auto, yellow, neon, minimal, white }

class LiteAnswers {
  final LitePlatform platform;
  final LiteContent content;
  final LiteLength length;
  final LiteCaptions captions;
  final bool music;

  const LiteAnswers({
    this.platform = LitePlatform.tiktok,
    this.content = LiteContent.auto,
    this.length = LiteLength.medium,
    this.captions = LiteCaptions.auto,
    this.music = false,
  });

  LiteAnswers copyWith({
    LitePlatform? platform,
    LiteContent? content,
    LiteLength? length,
    LiteCaptions? captions,
    bool? music,
  }) =>
      LiteAnswers(
        platform: platform ?? this.platform,
        content: content ?? this.content,
        length: length ?? this.length,
        captions: captions ?? this.captions,
        music: music ?? this.music,
      );
}

String _platformApi(LitePlatform p) => switch (p) {
      LitePlatform.tiktok => 'tiktok',
      LitePlatform.shorts => 'shorts',
      LitePlatform.reels => 'reels',
      LitePlatform.youtube => 'tiktok', // عمودي افتراضيًا؛ الباك إند يضبط الأبعاد
    };

String _contentApi(LiteContent c) => switch (c) {
      LiteContent.auto => 'auto',
      LiteContent.podcast => 'podcast',
      LiteContent.comedy => 'comedy',
      LiteContent.educational => 'educational',
      LiteContent.motivation => 'motivation',
      LiteContent.interview => 'interview',
    };

String? _captionApi(LiteCaptions c) => switch (c) {
      LiteCaptions.auto => null,
      LiteCaptions.yellow => 'TikTok Yellow',
      LiteCaptions.neon => 'Neon',
      LiteCaptions.minimal => 'Minimal',
      LiteCaptions.white => 'Bold White',
    };

/// عدد المقاطع وطولها من المدة المستهدفة.
(int, double) _clipsFor(LiteLength l) => switch (l) {
      LiteLength.short => (3, 30.0),
      LiteLength.medium => (5, 60.0),
      LiteLength.long => (8, 120.0),
    };

/// خريطة body.answers لـ POST /api/auto-edit (نفس شكل defaultAutoEditAnswers).
Map<String, dynamic> liteAnswersToMap(LiteAnswers a) {
  final (nClips, clipSec) = _clipsFor(a.length);
  return <String, dynamic>{
    'content_type': _contentApi(a.content),
    'platform': _platformApi(a.platform),
    'n_clips': nClips,
    'clip_duration_sec': clipSec,
    'caption_theme': _captionApi(a.captions),
    'music': a.music,
    'broll': true,
    'translate_arabic': false,
    'custom_instructions': _briefFor(a),
  };
}

/// تعليمات تلقائية من الإجابات — المساعد "يفهم" المطلوب ويكتبه للباك إند.
String _briefFor(LiteAnswers a) {
  const plat = {
    LitePlatform.tiktok: 'تيك توك عمودي',
    LitePlatform.shorts: 'يوتيوب شورتس',
    LitePlatform.reels: 'إنستجرام ريلز',
    LitePlatform.youtube: 'يوتيوب',
  };
  const cont = {
    LiteContent.auto: 'الأفضل تلقائيًا',
    LiteContent.podcast: 'بودكاست',
    LiteContent.comedy: 'كوميدي',
    LiteContent.educational: 'تعليمي',
    LiteContent.motivation: 'تحفيزي',
    LiteContent.interview: 'مقابلة',
  };
  const len = {
    LiteLength.short: 'قصير (~30 ثانية)',
    LiteLength.medium: 'متوسط (~دقيقة)',
    LiteLength.long: 'طويل (دقائق)',
  };
  final extra = a.music ? ' مع موسيقى خلفية هادئة.' : '';
  return 'مونتاج ${cont[a.content]} لمنصة ${plat[a.platform]}، '
      'المدة ${len[a.length]}.$extra';
}

/// ملخص عربي للمراجعة قبل التشغيل ("هنعمل كذا").
String liteSummaryAr(LiteAnswers a) {
  const plat = {
    LitePlatform.tiktok: 'تيك توك',
    LitePlatform.shorts: 'شورتس',
    LitePlatform.reels: 'ريلز',
    LitePlatform.youtube: 'يوتيوب',
  };
  const cont = {
    LiteContent.auto: 'تلقائي',
    LiteContent.podcast: 'بودكاست',
    LiteContent.comedy: 'كوميدي',
    LiteContent.educational: 'تعليمي',
    LiteContent.motivation: 'تحفيزي',
    LiteContent.interview: 'مقابلة',
  };
  const cap = {
    LiteCaptions.auto: 'تلقائي',
    LiteCaptions.yellow: 'أصفر',
    LiteCaptions.neon: 'نيون',
    LiteCaptions.minimal: 'هادئ',
    LiteCaptions.white: 'أبيض عريض',
  };
  final (n, _) = _clipsFor(a.length);
  return 'هنطلع لك $n مقاطع ${plat[a.platform]} '
      'بستايل ${cont[a.content]} وكابشن ${cap[a.captions]}'
      '${a.music ? ' وموسيقى' : ''}.';
}
