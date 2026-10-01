import 'dart:convert';

/// Style DNA موسّع مستخرج من فيديو مرجعي (قناة ما) — انظر
/// `docs/STYLE_DNA_REFERENCE.md`.
///
/// كله مقاسات (لا أفكار): إيقاع، انتقالات، أصوات، موسيقى (دور لا أغنية)،
/// ألوان، كابشن (مواصفات)، مقدمة/نهاية، هوك. JSON خالص قابل للحفظ.
class ReferenceDna {
  final String version;
  final String channel;
  final String videoId;
  final double sourceDuration;

  final RhythmDna rhythm;
  final TransitionDna transitions;
  final SfxDna sfx;
  final MusicDna music;
  final ColorDna color;
  final CaptionDna captions;
  final BookendsDna bookends;
  final HookDna hook;

  const ReferenceDna({
    this.version = '1',
    this.channel = '',
    this.videoId = '',
    this.sourceDuration = 0,
    this.rhythm = const RhythmDna(),
    this.transitions = const TransitionDna(),
    this.sfx = const SfxDna(),
    this.music = const MusicDna(),
    this.color = const ColorDna(),
    this.captions = const CaptionDna(),
    this.bookends = const BookendsDna(),
    this.hook = const HookDna(),
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'source': {
          'channel': channel,
          'video_id': videoId,
          'duration': sourceDuration,
        },
        'rhythm': rhythm.toJson(),
        'transitions': transitions.toJson(),
        'sfx': sfx.toJson(),
        'music': music.toJson(),
        'color': color.toJson(),
        'captions': captions.toJson(),
        'bookends': bookends.toJson(),
        'hook': hook.toJson(),
      };

  factory ReferenceDna.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> m(Object? v) =>
        v is Map<String, dynamic> ? v : const {};
    final src = m(json['source']);
    return ReferenceDna(
      version: json['version'] as String? ?? '1',
      channel: src['channel'] as String? ?? '',
      videoId: src['video_id'] as String? ?? '',
      sourceDuration: (src['duration'] as num?)?.toDouble() ?? 0,
      rhythm: RhythmDna.fromJson(m(json['rhythm'])),
      transitions: TransitionDna.fromJson(m(json['transitions'])),
      sfx: SfxDna.fromJson(m(json['sfx'])),
      music: MusicDna.fromJson(m(json['music'])),
      color: ColorDna.fromJson(m(json['color'])),
      captions: CaptionDna.fromJson(m(json['captions'])),
      bookends: BookendsDna.fromJson(m(json['bookends'])),
      hook: HookDna.fromJson(m(json['hook'])),
    );
  }

  String encode() => jsonEncode(toJson());

  factory ReferenceDna.decode(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('not a StyleDNA document');
    }
    return ReferenceDna.fromJson(data);
  }
}

class RhythmDna {
  final double avgShot;
  final double cutsPerMin;
  final bool accelerating;
  const RhythmDna(
      {this.avgShot = 0, this.cutsPerMin = 0, this.accelerating = false});

  Map<String, dynamic> toJson() => {
        'avg_shot': avgShot,
        'cuts_per_min': cutsPerMin,
        'accelerating': accelerating,
      };

  factory RhythmDna.fromJson(Map<String, dynamic> json) => RhythmDna(
        avgShot: (json['avg_shot'] as num?)?.toDouble() ?? 0,
        cutsPerMin: (json['cuts_per_min'] as num?)?.toDouble() ?? 0,
        accelerating: json['accelerating'] as bool? ?? false,
      );
}

class TransitionDna {
  /// نسب الأنواع — مجموعها ≈ 1 (cut/dissolve/fade/wipe).
  final double cut;
  final double dissolve;
  final double fade;
  final double wipe;
  const TransitionDna(
      {this.cut = 1, this.dissolve = 0, this.fade = 0, this.wipe = 0});

  Map<String, dynamic> toJson() => {
        'cut': cut,
        'dissolve': dissolve,
        'fade': fade,
        'wipe': wipe,
      };

  factory TransitionDna.fromJson(Map<String, dynamic> json) {
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    return TransitionDna(
      cut: d(json['cut']),
      dissolve: d(json['dissolve']),
      fade: d(json['fade']),
      wipe: d(json['wipe']),
    );
  }

  /// النوع الغالب (يُستخدم عند التطبيق).
  String get dominant {
    final entries = {'cut': cut, 'dissolve': dissolve, 'fade': fade, 'wipe': wipe};
    var best = 'cut';
    var bestV = -1.0;
    entries.forEach((k, v) {
      if (v > bestV) {
        bestV = v;
        best = k;
      }
    });
    return best;
  }
}

class SfxDna {
  final double eventsPerMin;
  final double onCutRatio;
  final List<String> types;
  const SfxDna(
      {this.eventsPerMin = 0, this.onCutRatio = 0, this.types = const []});

  Map<String, dynamic> toJson() => {
        'events_per_min': eventsPerMin,
        'on_cut_ratio': onCutRatio,
        'types': types,
      };

  factory SfxDna.fromJson(Map<String, dynamic> json) => SfxDna(
        eventsPerMin: (json['events_per_min'] as num?)?.toDouble() ?? 0,
        onCutRatio: (json['on_cut_ratio'] as num?)?.toDouble() ?? 0,
        types: (json['types'] as List?)?.whereType<String>().toList() ??
            const [],
      );
}

class MusicDna {
  final bool hasBed;
  final double bedDb;
  final double tempoBpm;
  final String mood;
  final bool hasIntroSting;
  final bool hasOutro;
  const MusicDna({
    this.hasBed = false,
    this.bedDb = -20,
    this.tempoBpm = 0,
    this.mood = 'neutral',
    this.hasIntroSting = false,
    this.hasOutro = false,
  });

  Map<String, dynamic> toJson() => {
        'has_bed': hasBed,
        'bed_db': bedDb,
        'tempo_bpm': tempoBpm,
        'mood': mood,
        'has_intro_sting': hasIntroSting,
        'has_outro': hasOutro,
      };

  factory MusicDna.fromJson(Map<String, dynamic> json) => MusicDna(
        hasBed: json['has_bed'] as bool? ?? false,
        bedDb: (json['bed_db'] as num?)?.toDouble() ?? -20,
        tempoBpm: (json['tempo_bpm'] as num?)?.toDouble() ?? 0,
        mood: json['mood'] as String? ?? 'neutral',
        hasIntroSting: json['has_intro_sting'] as bool? ?? false,
        hasOutro: json['has_outro'] as bool? ?? false,
      );
}

class ColorDna {
  final String mood;
  final double saturation;
  final double temperature;
  final double contrast;
  const ColorDna(
      {this.mood = 'neutral',
      this.saturation = 1.0,
      this.temperature = 5600,
      this.contrast = 1.0});

  Map<String, dynamic> toJson() => {
        'mood': mood,
        'saturation': saturation,
        'temperature': temperature,
        'contrast': contrast,
      };

  factory ColorDna.fromJson(Map<String, dynamic> json) => ColorDna(
        mood: json['mood'] as String? ?? 'neutral',
        saturation: (json['saturation'] as num?)?.toDouble() ?? 1.0,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 5600,
        contrast: (json['contrast'] as num?)?.toDouble() ?? 1.0,
      );
}

class CaptionDna {
  final double density;
  final String casing;
  final String position;
  final double wordsPerCaption;
  const CaptionDna(
      {this.density = 0,
      this.casing = 'mixed',
      this.position = 'bottom',
      this.wordsPerCaption = 3});

  Map<String, dynamic> toJson() => {
        'density': density,
        'case': casing,
        'position': position,
        'words_per_caption': wordsPerCaption,
      };

  factory CaptionDna.fromJson(Map<String, dynamic> json) => CaptionDna(
        density: (json['density'] as num?)?.toDouble() ?? 0,
        casing: json['case'] as String? ?? 'mixed',
        position: json['position'] as String? ?? 'bottom',
        wordsPerCaption:
            (json['words_per_caption'] as num?)?.toDouble() ?? 3,
      );
}

class BookendsDna {
  final bool hasIntro;
  final double introSec;
  final bool hasOutro;
  final double outroSec;
  const BookendsDna(
      {this.hasIntro = false,
      this.introSec = 0,
      this.hasOutro = false,
      this.outroSec = 0});

  Map<String, dynamic> toJson() => {
        'has_intro': hasIntro,
        'intro_sec': introSec,
        'has_outro': hasOutro,
        'outro_sec': outroSec,
      };

  factory BookendsDna.fromJson(Map<String, dynamic> json) => BookendsDna(
        hasIntro: json['has_intro'] as bool? ?? false,
        introSec: (json['intro_sec'] as num?)?.toDouble() ?? 0,
        hasOutro: json['has_outro'] as bool? ?? false,
        outroSec: (json['outro_sec'] as num?)?.toDouble() ?? 0,
      );
}

class HookDna {
  final String style;
  final double firstShotSec;
  const HookDna({this.style = 'statement', this.firstShotSec = 0});

  Map<String, dynamic> toJson() => {
        'style': style,
        'first_shot_sec': firstShotSec,
      };

  factory HookDna.fromJson(Map<String, dynamic> json) => HookDna(
        style: json['style'] as String? ?? 'statement',
        firstShotSec: (json['first_shot_sec'] as num?)?.toDouble() ?? 0,
      );
}
