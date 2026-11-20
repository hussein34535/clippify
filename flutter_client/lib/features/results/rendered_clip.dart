/// نسخة محلية معزولة عن `RenderedClip` الصادرة من `lib/core/backend/auto_edit_api.dart`
/// (ملف الوكيل الشقيق). نُبقي النوع هنا حتى لا تعتمد شاشة النتائج على الباك إند مباشرة.
///
/// الحقول مطابقة 1:1 لأسماء حقول صنف الوكيل:
/// index, fileUrl, viralScore, hookText, hookStart, hookEnd, durationSec, captionTheme
///
/// typedef BackendRenderedClip = RenderedClip; // من auto_edit_api.dart عند توفره —
/// إذا وُجد الصنف بنفس أسماء الحقول يُبنى مباشرة عبر [RenderedClipData.fromBackend]
/// بدون أي duck-typing: تحويل يدوي صريح حقل-بحقل.
library;

class ClipDirectorNotes {
  const ClipDirectorNotes({
    required this.understanding,
    required this.purpose,
    required this.strategy,
  });

  final String understanding;
  final String purpose;
  final String strategy;

  static ClipDirectorNotes? fromJson(Object? value) {
    if (value case {
      'understanding': final String understanding,
      'purpose': final String purpose,
      'strategy': final String strategy,
    }) {
      return ClipDirectorNotes(
        understanding: understanding,
        purpose: purpose,
        strategy: strategy,
      );
    }
    return null;
  }

  Map<String, String> toJson() => {
    'understanding': understanding,
    'purpose': purpose,
    'strategy': strategy,
  };
}

class RenderedClipData {
  final int index;
  final String fileUrl;
  final double viralScore;
  final String hookText;
  final double hookStart;
  final double hookEnd;
  final double durationSec;
  final String captionTheme;
  final bool? hasCaptions;
  final ClipDirectorNotes? director;

  const RenderedClipData({
    required this.index,
    required this.fileUrl,
    required this.viralScore,
    this.hookText = '',
    this.hookStart = 0.0,
    this.hookEnd = 0.0,
    required this.durationSec,
    this.captionTheme = '',
    this.hasCaptions,
    this.director,
  });

  /// من JSON عقد الـ DoneEvent في docs/CONTRACTS.md:
  /// {"index":0,"file_url":"...","viral_score":0.87,
  ///  "hook":{"text":"...","start_sec":1.2,"end_sec":4.8},
  ///  "duration_sec":58.4,"caption_theme":"TikTok Yellow"}
  factory RenderedClipData.fromJson(Map<String, dynamic> json) {
    final hook = json['hook'];
    double numAt(String key) => (json[key] as num?)?.toDouble() ?? 0.0;
    String hookField(String key) =>
        hook is Map<String, dynamic> ? (hook[key] as String? ?? '') : '';
    double hookNum(String key) => hook is Map<String, dynamic>
        ? (hook[key] as num?)?.toDouble() ?? 0.0
        : 0.0;
    // Rust backend sends hook_text at top level; Python sends hook.text
    final hookText = hookField('text').isNotEmpty
        ? hookField('text')
        : (json['hook_text'] as String? ?? '');
    // Compute duration from start/end if duration_sec missing (Rust format)
    final startSec = numAt('start_sec');
    final endSec = numAt('end_sec');
    final duration = numAt('duration_sec') > 0
        ? numAt('duration_sec')
        : (endSec - startSec);
    return RenderedClipData(
      index: json['index'] as int? ?? 0,
      fileUrl:
          json['file_url'] as String? ?? json['rendered_path'] as String? ?? '',
      viralScore: numAt('viral_score'),
      hookText: hookText,
      hookStart: hookNum('start_sec') > 0 ? hookNum('start_sec') : startSec,
      hookEnd: hookNum('end_sec') > 0 ? hookNum('end_sec') : endSec,
      durationSec: duration,
      captionTheme: json['caption_theme'] as String? ?? '',
      hasCaptions: json['has_captions'] as bool?,
      director: ClipDirectorNotes.fromJson(json['director']),
    );
  }

  /// تحويل يدوي من صنف الوكيل (auto_edit_api.dart). نستقبل `dynamic` عمداً
  /// لأن ملف الوكيل قد لا يكون موجوداً بعد؛ الأسماء موثّقة أعلاه ويُبنى
  /// الكائن مباشرة من حقوله بنفس الترتيب — لا انعكاس ولا duck-typing.
  factory RenderedClipData.fromBackend(dynamic other) => RenderedClipData(
    index: other.index as int,
    fileUrl: other.fileUrl as String,
    viralScore: (other.viralScore as num).toDouble(),
    hookText: other.hookText as String,
    hookStart: (other.hookStart as num).toDouble(),
    hookEnd: (other.hookEnd as num).toDouble(),
    durationSec: (other.durationSec as num).toDouble(),
    captionTheme: other.captionTheme as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'file_url': fileUrl,
    'viral_score': viralScore,
    'hook': {'text': hookText, 'start_sec': hookStart, 'end_sec': hookEnd},
    'duration_sec': durationSec,
    'caption_theme': captionTheme,
    if (hasCaptions != null) 'has_captions': hasCaptions,
    if (director != null) 'director': director!.toJson(),
  };
}
