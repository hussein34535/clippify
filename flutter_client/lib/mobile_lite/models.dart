enum LitePlatform {
  tiktok('تيك توك'),
  shorts('شورتس'),
  reels('ريلز'),
  youtube('يوتيوب');

  const LitePlatform(this.labelAr);

  final String labelAr;
}

enum LiteContent { auto, podcast, comedy, educational, motivation, interview }

enum LiteLength {
  short(30),
  medium(45),
  long(60);

  const LiteLength(this.seconds);

  final int seconds;
}

enum LiteCaptions { auto, yellow, neon, minimal, white }

enum LiteDirector { ai, local }

enum LiteCreative {
  auto('تلقائي'),
  reaction('رد فعل'),
  story('حكاية'),
  kinetic('إيقاع سريع'),
  clean('بسيط');

  const LiteCreative(this.label);
  final String label;
}

enum LiteZoom {
  requested('لو طلبت'),
  auto('حسب اللقطة'),
  off('مقفول');

  const LiteZoom(this.label);
  final String label;
}

class LiteAnswers {
  final LitePlatform platform;
  final LiteContent content;
  final LiteLength length;
  final LiteCaptions captions;
  final bool music;
  final String editBrief;
  final LiteZoom zoom;
  final LiteCreative creative;
  final String creativeTitle;
  final bool creativeMusic;
  final bool creativeEffects;
  final LiteDirector? director;

  const LiteAnswers({
    this.platform = LitePlatform.tiktok,
    this.content = LiteContent.auto,
    this.length = LiteLength.medium,
    this.captions = LiteCaptions.auto,
    this.music = false,
    this.editBrief = '',
    this.zoom = LiteZoom.requested,
    this.creative = LiteCreative.auto,
    this.creativeTitle = '',
    this.creativeMusic = true,
    this.creativeEffects = true,
    this.director,
  });

  LiteAnswers copyWith({
    LitePlatform? platform,
    LiteContent? content,
    LiteLength? length,
    LiteCaptions? captions,
    bool? music,
    String? editBrief,
    LiteZoom? zoom,
    LiteCreative? creative,
    String? creativeTitle,
    bool? creativeMusic,
    bool? creativeEffects,
    LiteDirector? director,
  }) => LiteAnswers(
    platform: platform ?? this.platform,
    content: content ?? this.content,
    length: length ?? this.length,
    captions: captions ?? this.captions,
    music: music ?? this.music,
    editBrief: editBrief ?? this.editBrief,
    zoom: zoom ?? this.zoom,
    creative: creative ?? this.creative,
    creativeTitle: creativeTitle ?? this.creativeTitle,
    creativeMusic: creativeMusic ?? this.creativeMusic,
    creativeEffects: creativeEffects ?? this.creativeEffects,
    director: director ?? this.director,
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

/// خريطة body.answers للمونتاج التلقائي لمقطع قصير واحد.
Map<String, dynamic> liteAnswersToMap(LiteAnswers a) {
  final aiDirected = a.director == LiteDirector.ai;
  return <String, dynamic>{
    'mode': 'short_auto',
    if (a.director != null) 'short_director': a.director!.name,
    if (!aiDirected) 'creative_style': a.creative.name,
    if (!aiDirected && a.creativeTitle.trim().isNotEmpty)
      'creative_title': a.creativeTitle.trim(),
    if (!aiDirected && a.creative != LiteCreative.clean) ...{
      'creative_music': a.creativeMusic,
      'creative_effects': a.creativeEffects,
    },
    if (a.editBrief.trim().isNotEmpty) 'edit_brief': a.editBrief.trim(),
    'zoom_policy': switch (a.zoom) {
      LiteZoom.requested => 'request_only',
      LiteZoom.auto => 'allow',
      LiteZoom.off => 'off',
    },
    'content_type': _contentApi(a.content),
    'platform': _platformApi(a.platform),
    'n_clips': 1,
    'clip_duration_sec': a.length.seconds.toDouble(),
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
  final extra = a.music ? ' مع موسيقى خلفية هادئة' : '';
  return 'مونتاج ${cont[a.content]} لمقطع واحد لمنصة ${plat[a.platform]}، '
      'المدة المستهدفة ${a.length.seconds} ثانية$extra.';
}

/// ملخص عربي للمنصة والمدة المستهدفة قبل التشغيل.
String liteSummaryAr(LiteAnswers a) =>
    'مقطع واحد لمنصة ${a.platform.labelAr} · ${a.length.seconds} ثانية';
