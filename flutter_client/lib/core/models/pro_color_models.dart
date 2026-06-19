class LiftGammaGain {
  final double hue;
  final double saturation;
  final double luminance;

  const LiftGammaGain({
    this.hue = 0.0,
    this.saturation = 0.0,
    this.luminance = 0.5,
  });

  factory LiftGammaGain.fromJson(Map<String, dynamic> json) => LiftGammaGain(
        hue: (json['hue'] as num? ?? 0.0).toDouble(),
        saturation: (json['saturation'] as num? ?? 0.0).toDouble(),
        luminance: (json['luminance'] as num? ?? 0.5).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'hue': hue,
        'saturation': saturation,
        'luminance': luminance,
      };

  LiftGammaGain copyWith({double? hue, double? saturation, double? luminance}) =>
      LiftGammaGain(
        hue: hue ?? this.hue,
        saturation: saturation ?? this.saturation,
        luminance: luminance ?? this.luminance,
      );
}

class ProColorState {
  final LiftGammaGain lift;
  final LiftGammaGain gamma;
  final LiftGammaGain gain;
  final double offset;
  final double contrast;
  final double pivot;
  final double shadowClip;
  final double highlightClip;
  final String lutPath;
  final double lutIntensity;
  final bool hdrEnabled;

  const ProColorState({
    this.lift = const LiftGammaGain(),
    this.gamma = const LiftGammaGain(),
    this.gain = const LiftGammaGain(),
    this.offset = 0.0,
    this.contrast = 1.0,
    this.pivot = 0.5,
    this.shadowClip = 0.0,
    this.highlightClip = 0.0,
    this.lutPath = '',
    this.lutIntensity = 1.0,
    this.hdrEnabled = false,
  });

  factory ProColorState.fromJson(Map<String, dynamic> json) => ProColorState(
        lift: json['lift'] != null
            ? LiftGammaGain.fromJson(json['lift'] as Map<String, dynamic>)
            : const LiftGammaGain(),
        gamma: json['gamma'] != null
            ? LiftGammaGain.fromJson(json['gamma'] as Map<String, dynamic>)
            : const LiftGammaGain(),
        gain: json['gain'] != null
            ? LiftGammaGain.fromJson(json['gain'] as Map<String, dynamic>)
            : const LiftGammaGain(),
        offset: (json['offset'] as num? ?? 0.0).toDouble(),
        contrast: (json['contrast'] as num? ?? 1.0).toDouble(),
        pivot: (json['pivot'] as num? ?? 0.5).toDouble(),
        shadowClip: (json['shadow_clip'] as num? ?? 0.0).toDouble(),
        highlightClip: (json['highlight_clip'] as num? ?? 0.0).toDouble(),
        lutPath: json['lut_path'] as String? ?? '',
        lutIntensity: (json['lut_intensity'] as num? ?? 1.0).toDouble(),
        hdrEnabled: json['hdr_enabled'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'lift': lift.toJson(),
        'gamma': gamma.toJson(),
        'gain': gain.toJson(),
        'offset': offset,
        'contrast': contrast,
        'pivot': pivot,
        'shadow_clip': shadowClip,
        'highlight_clip': highlightClip,
        'lut_path': lutPath,
        'lut_intensity': lutIntensity,
        'hdr_enabled': hdrEnabled,
      };

  ProColorState copyWith({
    LiftGammaGain? lift,
    LiftGammaGain? gamma,
    LiftGammaGain? gain,
    double? offset,
    double? contrast,
    double? pivot,
    double? shadowClip,
    double? highlightClip,
    String? lutPath,
    double? lutIntensity,
    bool? hdrEnabled,
  }) =>
      ProColorState(
        lift: lift ?? this.lift,
        gamma: gamma ?? this.gamma,
        gain: gain ?? this.gain,
        offset: offset ?? this.offset,
        contrast: contrast ?? this.contrast,
        pivot: pivot ?? this.pivot,
        shadowClip: shadowClip ?? this.shadowClip,
        highlightClip: highlightClip ?? this.highlightClip,
        lutPath: lutPath ?? this.lutPath,
        lutIntensity: lutIntensity ?? this.lutIntensity,
        hdrEnabled: hdrEnabled ?? this.hdrEnabled,
      );
}
