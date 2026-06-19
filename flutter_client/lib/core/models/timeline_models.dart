import 'pro_color_models.dart';

class Vector2D {
  final double x;
  final double y;

  Vector2D({required this.x, required this.y});

  factory Vector2D.fromJson(Map<String, dynamic> json) => Vector2D(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  Vector2D copyWith({double? x, double? y}) => Vector2D(
        x: x ?? this.x,
        y: y ?? this.y,
      );
}

class Keyframe {
  final double time;
  final String property;
  final dynamic value;
  final String easing;
  final double? bezierInX;
  final double? bezierInY;
  final double? bezierOutX;
  final double? bezierOutY;

  Keyframe({
    required this.time,
    required this.property,
    required this.value,
    this.easing = 'linear',
    this.bezierInX,
    this.bezierInY,
    this.bezierOutX,
    this.bezierOutY,
  });

  factory Keyframe.fromJson(Map<String, dynamic> json) => Keyframe(
        time: (json['time'] as num).toDouble(),
        property: json['property'] as String,
        value: json['value'],
        easing: json['easing'] as String? ?? 'linear',
        bezierInX: (json['bezier_in_x'] as num?)?.toDouble(),
        bezierInY: (json['bezier_in_y'] as num?)?.toDouble(),
        bezierOutX: (json['bezier_out_x'] as num?)?.toDouble(),
        bezierOutY: (json['bezier_out_y'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'property': property,
        'value': value,
        'easing': easing,
        if (bezierInX != null) 'bezier_in_x': bezierInX,
        if (bezierInY != null) 'bezier_in_y': bezierInY,
        if (bezierOutX != null) 'bezier_out_x': bezierOutX,
        if (bezierOutY != null) 'bezier_out_y': bezierOutY,
      };

  Keyframe copyWith({
    double? time,
    String? property,
    dynamic value,
    String? easing,
    double? bezierInX,
    double? bezierInY,
    double? bezierOutX,
    double? bezierOutY,
  }) =>
      Keyframe(
        time: time ?? this.time,
        property: property ?? this.property,
        value: value ?? this.value,
        easing: easing ?? this.easing,
        bezierInX: bezierInX ?? this.bezierInX,
        bezierInY: bezierInY ?? this.bezierInY,
        bezierOutX: bezierOutX ?? this.bezierOutX,
        bezierOutY: bezierOutY ?? this.bezierOutY,
      );
}

class CropState {
  final double left;
  final double right;
  final double top;
  final double bottom;

  CropState({this.left = 0.0, this.right = 0.0, this.top = 0.0, this.bottom = 0.0});

  factory CropState.fromJson(Map<String, dynamic> json) => CropState(
        left: (json['left'] as num? ?? 0.0).toDouble(),
        right: (json['right'] as num? ?? 0.0).toDouble(),
        top: (json['top'] as num? ?? 0.0).toDouble(),
        bottom: (json['bottom'] as num? ?? 0.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'left': left,
        'right': right,
        'top': top,
        'bottom': bottom,
      };

  CropState copyWith({double? left, double? right, double? top, double? bottom}) => CropState(
        left: left ?? this.left,
        right: right ?? this.right,
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
      );
}

class TransformState {
  final Vector2D position;
  final Vector2D scale;
  final double rotation;
  final CropState crop;
  final String? aspectRatio;
  final List<Keyframe> keyframes;

  TransformState({
    required this.position,
    required this.scale,
    required this.rotation,
    required this.crop,
    this.aspectRatio,
    required this.keyframes,
  });

  factory TransformState.defaultState() => TransformState(
        position: Vector2D(x: 0, y: 0),
        scale: Vector2D(x: 100, y: 100),
        rotation: 0.0,
        crop: CropState(),
        keyframes: [],
      );

  factory TransformState.fromJson(Map<String, dynamic> json) => TransformState(
        position: Vector2D.fromJson(json['position'] as Map<String, dynamic>),
        scale: Vector2D.fromJson(json['scale'] as Map<String, dynamic>),
        rotation: (json['rotation'] as num? ?? 0.0).toDouble(),
        crop: CropState.fromJson(json['crop'] as Map<String, dynamic>? ?? {}),
        aspectRatio: json['aspect_ratio'] as String?,
        keyframes: (json['keyframes'] as List<dynamic>?)
                ?.map((e) => Keyframe.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'position': position.toJson(),
        'scale': scale.toJson(),
        'rotation': rotation,
        'crop': crop.toJson(),
        'aspect_ratio': aspectRatio,
        'keyframes': keyframes.map((e) => e.toJson()).toList(),
      };

  TransformState copyWith({
    Vector2D? position,
    Vector2D? scale,
    double? rotation,
    CropState? crop,
    String? aspectRatio,
    List<Keyframe>? keyframes,
  }) =>
      TransformState(
        position: position ?? this.position,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        crop: crop ?? this.crop,
        aspectRatio: aspectRatio ?? this.aspectRatio,
        keyframes: keyframes ?? this.keyframes,
      );
}

class ColorGradingState {
  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;
  final double hue;
  final double hslSaturation;
  final String lutPath;

  ColorGradingState({
    this.brightness = 0.0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.temperature = 0.0,
    this.hue = 0.0,
    this.hslSaturation = 0.5,
    this.lutPath = '',
  });

  factory ColorGradingState.fromJson(Map<String, dynamic> json) =>
      ColorGradingState(
        brightness: (json['brightness'] as num? ?? 0.0).toDouble(),
        contrast: (json['contrast'] as num? ?? 1.0).toDouble(),
        saturation: (json['saturation'] as num? ?? 1.0).toDouble(),
        temperature: (json['temperature'] as num? ?? 0.0).toDouble(),
        hue: (json['hue'] as num? ?? 0.0).toDouble(),
        hslSaturation: (json['hsl_saturation'] as num? ?? 0.5).toDouble(),
        lutPath: json['lut_path'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'temperature': temperature,
        'hue': hue,
        'hsl_saturation': hslSaturation,
        'lut_path': lutPath,
      };

  ColorGradingState copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
    double? hue,
    double? hslSaturation,
    String? lutPath,
  }) =>
      ColorGradingState(
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
        saturation: saturation ?? this.saturation,
        temperature: temperature ?? this.temperature,
        hue: hue ?? this.hue,
        hslSaturation: hslSaturation ?? this.hslSaturation,
        lutPath: lutPath ?? this.lutPath,
      );
}

class FilterSpec {
  final String type; // 'blur' | 'vignette' | 'mosaic' | 'chromakey' | 'noise'
  final Map<String, dynamic> params;

  FilterSpec({required this.type, required this.params});

  factory FilterSpec.fromJson(Map<String, dynamic> json) => FilterSpec(
        type: json['type'] as String,
        params: json['params'] as Map<String, dynamic>? ?? {},
      );

  Map<String, dynamic> toJson() => {'type': type, 'params': params};
}

class AIFeatures {
  final bool faceTracking;
  final bool bgRemoved;
  final String bgRemoveMethod; // 'none' | 'chromakey' | 'sam' | 'rmbg'
  final String chromakeyColor;
  final bool vocalIsolation;
  final bool autoDucking;
  final double duckingLevel;

  AIFeatures({
    this.faceTracking = false,
    this.bgRemoved = false,
    this.bgRemoveMethod = 'none',
    this.chromakeyColor = '#00FF00',
    this.vocalIsolation = false,
    this.autoDucking = false,
    this.duckingLevel = 0.8,
  });

  factory AIFeatures.fromJson(Map<String, dynamic> json) => AIFeatures(
        faceTracking: json['face_tracking'] as bool? ?? false,
        bgRemoved: json['bg_removed'] as bool? ?? false,
        bgRemoveMethod: json['bg_remove_method'] as String? ?? 'none',
        chromakeyColor: json['chromakey_color'] as String? ?? '#00FF00',
        vocalIsolation: json['vocal_isolation'] as bool? ?? false,
        autoDucking: json['auto_ducking'] as bool? ?? false,
        duckingLevel: (json['ducking_level'] as num? ?? 0.8).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'face_tracking': faceTracking,
        'bg_removed': bgRemoved,
        'bg_remove_method': bgRemoveMethod,
        'chromakey_color': chromakeyColor,
        'vocal_isolation': vocalIsolation,
        'auto_ducking': autoDucking,
        'ducking_level': duckingLevel,
      };

  AIFeatures copyWith({
    bool? faceTracking,
    bool? bgRemoved,
    String? bgRemoveMethod,
    String? chromakeyColor,
    bool? vocalIsolation,
    bool? autoDucking,
    double? duckingLevel,
  }) =>
      AIFeatures(
        faceTracking: faceTracking ?? this.faceTracking,
        bgRemoved: bgRemoved ?? this.bgRemoved,
        bgRemoveMethod: bgRemoveMethod ?? this.bgRemoveMethod,
        chromakeyColor: chromakeyColor ?? this.chromakeyColor,
        vocalIsolation: vocalIsolation ?? this.vocalIsolation,
        autoDucking: autoDucking ?? this.autoDucking,
        duckingLevel: duckingLevel ?? this.duckingLevel,
      );
}

class Transition {
  final String type;
  final double duration;

  const Transition({required this.type, this.duration = 0.5});

  factory Transition.fromJson(Map<String, dynamic> json) => Transition(
        type: json['type'] as String,
        duration: (json['duration'] as num? ?? 0.5).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'duration': duration,
      };

  Transition copyWith({String? type, double? duration}) =>
      Transition(type: type ?? this.type, duration: duration ?? this.duration);

  static const List<String> availableTypes = [
    'none',
    'cross_dissolve',
    'fade_to_black',
    'fade_to_white',
    'wipe_left',
    'wipe_right',
    'wipe_up',
    'wipe_down',
    'zoom_in',
    'zoom_out',
    'spin',
    'blur',
  ];
}

class SpeedPoint {
  final double time;
  final double speed;

  const SpeedPoint({required this.time, required this.speed});

  factory SpeedPoint.fromJson(Map<String, dynamic> json) => SpeedPoint(
        time: (json['time'] as num).toDouble(),
        speed: (json['speed'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'speed': speed,
      };

  SpeedPoint copyWith({double? time, double? speed}) =>
      SpeedPoint(time: time ?? this.time, speed: speed ?? this.speed);
}

class SpeedRamp {
  final List<SpeedPoint> points;

  const SpeedRamp({this.points = const []});

  factory SpeedRamp.fromJson(Map<String, dynamic> json) => SpeedRamp(
        points: (json['points'] as List<dynamic>?)
                ?.map((e) => SpeedPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'points': points.map((e) => e.toJson()).toList(),
      };

  SpeedRamp copyWith({List<SpeedPoint>? points}) =>
      SpeedRamp(points: points ?? this.points);

  double getSpeedAtTime(double timeInClip, double clipDuration) {
    if (points.isEmpty) return 1.0;
    if (points.length == 1) return points.first.speed;
    if (timeInClip <= points.first.time) return points.first.speed;
    if (timeInClip >= points.last.time) return points.last.speed;

    for (int i = 0; i < points.length - 1; i++) {
      if (timeInClip >= points[i].time && timeInClip <= points[i + 1].time) {
        final t = (timeInClip - points[i].time) /
            (points[i + 1].time - points[i].time);
        final a = points[i].speed;
        final b = points[i + 1].speed;
        return a + (b - a) * t;
      }
    }
    return 1.0;
  }
}

class VideoClip {
  final String id;
  final String sourcePath;
  final double startTimeInTimeline;
  final double endTimeInTimeline;
  final double sourceTrimStart;
  final double sourceTrimEnd;
  final double sourceDuration;
  final double speed;
  final double volume;
  final double bass;
  final double mid;
  final double treble;
  final TransformState transform;
  final ColorGradingState colorGrading;
  final ProColorState proColor;
  final List<FilterSpec> filters;
  final AIFeatures aiFeatures;
  final Transition outTransition;
  final SpeedRamp speedRamp;
  final bool useProxy;
  final List<String> audioEffects;
  final double reverbAmount;
  final double delayAmount;
  final double compressorAmount;
  final List<Map<String, dynamic>> particleEffects;
  final List<Map<String, dynamic>> shapeOverlays;
  final List<String> shaderEffects;
  final int aiUpscaleFactor;
  final bool aiEnhanced;
  final bool useTracking;
  final List<Keyframe> trackedPosition;
  final String trackingType;
  final List<Map<String, dynamic>> effectChain;
  final List<Map<String, dynamic>> automationLanes;

  VideoClip({
    required this.id,
    required this.sourcePath,
    required this.startTimeInTimeline,
    required this.endTimeInTimeline,
    required this.sourceTrimStart,
    required this.sourceTrimEnd,
    this.sourceDuration = 0.0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.bass = 0.5,
    this.mid = 0.5,
    this.treble = 0.5,
    required this.transform,
    required this.colorGrading,
    this.proColor = const ProColorState(),
    required this.filters,
    required this.aiFeatures,
    this.outTransition = const Transition(type: 'none'),
    this.speedRamp = const SpeedRamp(),
    this.useProxy = false,
    this.audioEffects = const [],
    this.reverbAmount = 0.0,
    this.delayAmount = 0.0,
    this.compressorAmount = 0.0,
    this.particleEffects = const [],
    this.shapeOverlays = const [],
    this.shaderEffects = const [],
    this.aiUpscaleFactor = 1,
    this.aiEnhanced = false,
    this.useTracking = false,
    this.trackedPosition = const [],
    this.trackingType = 'none',
    this.effectChain = const [],
    this.automationLanes = const [],
  });

  factory VideoClip.fromJson(Map<String, dynamic> json) => VideoClip(
        id: json['id'] as String,
        sourcePath: json['source_path'] as String,
        startTimeInTimeline: (json['start_time_in_timeline'] as num).toDouble(),
        endTimeInTimeline: (json['end_time_in_timeline'] as num).toDouble(),
        sourceTrimStart: (json['source_trim_start'] as num).toDouble(),
        sourceTrimEnd: (json['source_trim_end'] as num).toDouble(),
        sourceDuration: (json['source_duration'] as num? ?? 0.0).toDouble(),
        speed: (json['speed'] as num? ?? 1.0).toDouble(),
        volume: (json['volume'] as num? ?? 1.0).toDouble(),
        bass: (json['bass'] as num? ?? 0.5).toDouble(),
        mid: (json['mid'] as num? ?? 0.5).toDouble(),
        treble: (json['treble'] as num? ?? 0.5).toDouble(),
        transform: TransformState.fromJson(json['transform'] as Map<String, dynamic>),
        colorGrading: ColorGradingState.fromJson(json['color_grading'] as Map<String, dynamic>),
        proColor: json['pro_color'] != null
            ? ProColorState.fromJson(json['pro_color'] as Map<String, dynamic>)
            : const ProColorState(),
        filters: (json['filters'] as List<dynamic>?)
                ?.map((e) => FilterSpec.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        aiFeatures: AIFeatures.fromJson(json['ai_features'] as Map<String, dynamic>),
        outTransition: json['out_transition'] != null
            ? Transition.fromJson(json['out_transition'] as Map<String, dynamic>)
            : const Transition(type: 'none'),
        speedRamp: json['speed_ramp'] != null
            ? SpeedRamp.fromJson(json['speed_ramp'] as Map<String, dynamic>)
            : const SpeedRamp(),
        useProxy: json['use_proxy'] as bool? ?? false,
        audioEffects: (json['audio_effects'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        reverbAmount: (json['reverb_amount'] as num? ?? 0.0).toDouble(),
        delayAmount: (json['delay_amount'] as num? ?? 0.0).toDouble(),
        compressorAmount: (json['compressor_amount'] as num? ?? 0.0).toDouble(),
        particleEffects: (json['particle_effects'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        shapeOverlays: (json['shape_overlays'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            [],
        shaderEffects: (json['shader_effects'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        aiUpscaleFactor: json['ai_upscale_factor'] as int? ?? 1,
        aiEnhanced: json['ai_enhanced'] as bool? ?? false,
        useTracking: json['use_tracking'] as bool? ?? false,
        trackedPosition: (json['tracked_position'] as List<dynamic>?)
                ?.map((e) => Keyframe.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        trackingType: json['tracking_type'] as String? ?? 'none',
        effectChain: (json['effect_chain'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            const [],
        automationLanes: (json['automation_lanes'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            const [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_path': sourcePath,
        'start_time_in_timeline': startTimeInTimeline,
        'end_time_in_timeline': endTimeInTimeline,
        'source_trim_start': sourceTrimStart,
        'source_trim_end': sourceTrimEnd,
        'source_duration': sourceDuration,
        'speed': speed,
        'volume': volume,
        'bass': bass,
        'mid': mid,
        'treble': treble,
        'transform': transform.toJson(),
        'color_grading': colorGrading.toJson(),
        'pro_color': proColor.toJson(),
        'filters': filters.map((e) => e.toJson()).toList(),
        'ai_features': aiFeatures.toJson(),
        'out_transition': outTransition.toJson(),
        'speed_ramp': speedRamp.toJson(),
        'use_proxy': useProxy,
        'audio_effects': audioEffects,
        'reverb_amount': reverbAmount,
        'delay_amount': delayAmount,
        'compressor_amount': compressorAmount,
        'particle_effects': particleEffects,
        'shape_overlays': shapeOverlays,
        'shader_effects': shaderEffects,
        'ai_upscale_factor': aiUpscaleFactor,
        'ai_enhanced': aiEnhanced,
        'use_tracking': useTracking,
        'tracked_position': trackedPosition.map((e) => e.toJson()).toList(),
        'tracking_type': trackingType,
        'effect_chain': effectChain,
        'automation_lanes': automationLanes,
      };

  VideoClip copyWith({
    String? id,
    String? sourcePath,
    double? startTimeInTimeline,
    double? endTimeInTimeline,
    double? sourceTrimStart,
    double? sourceTrimEnd,
    double? sourceDuration,
    double? speed,
    double? volume,
    double? bass,
    double? mid,
    double? treble,
    TransformState? transform,
    ColorGradingState? colorGrading,
    ProColorState? proColor,
    List<FilterSpec>? filters,
    AIFeatures? aiFeatures,
    Transition? outTransition,
    SpeedRamp? speedRamp,
    bool? useProxy,
    List<String>? audioEffects,
    double? reverbAmount,
    double? delayAmount,
    double? compressorAmount,
    List<Map<String, dynamic>>? particleEffects,
    List<Map<String, dynamic>>? shapeOverlays,
    List<String>? shaderEffects,
    int? aiUpscaleFactor,
    bool? aiEnhanced,
    bool? useTracking,
    List<Keyframe>? trackedPosition,
    String? trackingType,
    List<Map<String, dynamic>>? effectChain,
    List<Map<String, dynamic>>? automationLanes,
  }) =>
      VideoClip(
        id: id ?? this.id,
        sourcePath: sourcePath ?? this.sourcePath,
        startTimeInTimeline: startTimeInTimeline ?? this.startTimeInTimeline,
        endTimeInTimeline: endTimeInTimeline ?? this.endTimeInTimeline,
        sourceTrimStart: sourceTrimStart ?? this.sourceTrimStart,
        sourceTrimEnd: sourceTrimEnd ?? this.sourceTrimEnd,
        sourceDuration: sourceDuration ?? this.sourceDuration,
        speed: speed ?? this.speed,
        volume: volume ?? this.volume,
        bass: bass ?? this.bass,
        mid: mid ?? this.mid,
        treble: treble ?? this.treble,
        transform: transform ?? this.transform,
        colorGrading: colorGrading ?? this.colorGrading,
        proColor: proColor ?? this.proColor,
        filters: filters ?? this.filters,
        aiFeatures: aiFeatures ?? this.aiFeatures,
        outTransition: outTransition ?? this.outTransition,
        speedRamp: speedRamp ?? this.speedRamp,
        useProxy: useProxy ?? this.useProxy,
        audioEffects: audioEffects ?? this.audioEffects,
        reverbAmount: reverbAmount ?? this.reverbAmount,
        delayAmount: delayAmount ?? this.delayAmount,
        compressorAmount: compressorAmount ?? this.compressorAmount,
        particleEffects: particleEffects ?? this.particleEffects,
        shapeOverlays: shapeOverlays ?? this.shapeOverlays,
        shaderEffects: shaderEffects ?? this.shaderEffects,
        aiUpscaleFactor: aiUpscaleFactor ?? this.aiUpscaleFactor,
        aiEnhanced: aiEnhanced ?? this.aiEnhanced,
        useTracking: useTracking ?? this.useTracking,
        trackedPosition: trackedPosition ?? this.trackedPosition,
        trackingType: trackingType ?? this.trackingType,
        effectChain: effectChain ?? this.effectChain,
        automationLanes: automationLanes ?? this.automationLanes,
      );
}

class AudioClip {
  final String id;
  final String sourcePath;
  final double startTimeInTimeline;
  final double endTimeInTimeline;
  final double sourceTrimStart;
  final double sourceTrimEnd;
  final double sourceDuration;
  final double volume;
  final double bass;
  final double mid;
  final double treble;
  final double fadeIn;
  final double fadeOut;
  final List<FilterSpec> effects;
  final List<String> audioEffects;
  final double reverbAmount;
  final double delayAmount;
  final double compressorAmount;
  final List<Map<String, dynamic>> effectChain;
  final double pan;
  final bool solo;
  final List<Map<String, dynamic>> automationLanes;
  final double? sidechainSourceTrack;

  AudioClip({
    required this.id,
    required this.sourcePath,
    required this.startTimeInTimeline,
    required this.endTimeInTimeline,
    required this.sourceTrimStart,
    required this.sourceTrimEnd,
    this.sourceDuration = 0.0,
    this.volume = 1.0,
    this.bass = 0.5,
    this.mid = 0.5,
    this.treble = 0.5,
    this.fadeIn = 0.0,
    this.fadeOut = 0.0,
    required this.effects,
    this.audioEffects = const [],
    this.reverbAmount = 0.0,
    this.delayAmount = 0.0,
    this.compressorAmount = 0.0,
    this.effectChain = const [],
    this.pan = 0.0,
    this.solo = false,
    this.automationLanes = const [],
    this.sidechainSourceTrack,
  });

  factory AudioClip.fromJson(Map<String, dynamic> json) => AudioClip(
        id: json['id'] as String,
        sourcePath: json['source_path'] as String,
        startTimeInTimeline: (json['start_time_in_timeline'] as num).toDouble(),
        endTimeInTimeline: (json['end_time_in_timeline'] as num).toDouble(),
        sourceTrimStart: (json['source_trim_start'] as num).toDouble(),
        sourceTrimEnd: (json['source_trim_end'] as num).toDouble(),
        sourceDuration: (json['source_duration'] as num? ?? 0.0).toDouble(),
        volume: (json['volume'] as num? ?? 1.0).toDouble(),
        bass: (json['bass'] as num? ?? 0.5).toDouble(),
        mid: (json['mid'] as num? ?? 0.5).toDouble(),
        treble: (json['treble'] as num? ?? 0.5).toDouble(),
        fadeIn: (json['fade_in'] as num? ?? 0.0).toDouble(),
        fadeOut: (json['fade_out'] as num? ?? 0.0).toDouble(),
        effects: (json['effects'] as List<dynamic>?)
                ?.map((e) => FilterSpec.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        audioEffects: (json['audio_effects'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        reverbAmount: (json['reverb_amount'] as num? ?? 0.0).toDouble(),
        delayAmount: (json['delay_amount'] as num? ?? 0.0).toDouble(),
        compressorAmount: (json['compressor_amount'] as num? ?? 0.0).toDouble(),
        effectChain: (json['effect_chain'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            const [],
        pan: (json['pan'] as num? ?? 0.0).toDouble(),
        solo: json['solo'] as bool? ?? false,
        automationLanes: (json['automation_lanes'] as List<dynamic>?)
                ?.map((e) => e as Map<String, dynamic>)
                .toList() ??
            const [],
        sidechainSourceTrack: (json['sidechain_source_track'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source_path': sourcePath,
        'start_time_in_timeline': startTimeInTimeline,
        'end_time_in_timeline': endTimeInTimeline,
        'source_trim_start': sourceTrimStart,
        'source_trim_end': sourceTrimEnd,
        'source_duration': sourceDuration,
        'volume': volume,
        'bass': bass,
        'mid': mid,
        'treble': treble,
        'fade_in': fadeIn,
        'fade_out': fadeOut,
        'effects': effects.map((e) => e.toJson()).toList(),
        'audio_effects': audioEffects,
        'reverb_amount': reverbAmount,
        'delay_amount': delayAmount,
        'compressor_amount': compressorAmount,
        'effect_chain': effectChain,
        'pan': pan,
        'solo': solo,
        'automation_lanes': automationLanes,
        'sidechain_source_track': sidechainSourceTrack,
      };

  AudioClip copyWith({
    String? id,
    String? sourcePath,
    double? startTimeInTimeline,
    double? endTimeInTimeline,
    double? sourceTrimStart,
    double? sourceTrimEnd,
    double? sourceDuration,
    double? volume,
    double? bass,
    double? mid,
    double? treble,
    double? fadeIn,
    double? fadeOut,
    List<FilterSpec>? effects,
    List<String>? audioEffects,
    double? reverbAmount,
    double? delayAmount,
    double? compressorAmount,
    List<Map<String, dynamic>>? effectChain,
    double? pan,
    bool? solo,
    List<Map<String, dynamic>>? automationLanes,
    double? sidechainSourceTrack,
  }) {
    return AudioClip(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      startTimeInTimeline: startTimeInTimeline ?? this.startTimeInTimeline,
      endTimeInTimeline: endTimeInTimeline ?? this.endTimeInTimeline,
      sourceTrimStart: sourceTrimStart ?? this.sourceTrimStart,
      sourceTrimEnd: sourceTrimEnd ?? this.sourceTrimEnd,
      sourceDuration: sourceDuration ?? this.sourceDuration,
      volume: volume ?? this.volume,
      bass: bass ?? this.bass,
      mid: mid ?? this.mid,
      treble: treble ?? this.treble,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      effects: effects ?? this.effects,
      audioEffects: audioEffects ?? this.audioEffects,
      reverbAmount: reverbAmount ?? this.reverbAmount,
      delayAmount: delayAmount ?? this.delayAmount,
      compressorAmount: compressorAmount ?? this.compressorAmount,
      effectChain: effectChain ?? this.effectChain,
      pan: pan ?? this.pan,
      solo: solo ?? this.solo,
      automationLanes: automationLanes ?? this.automationLanes,
      sidechainSourceTrack: sidechainSourceTrack ?? this.sidechainSourceTrack,
    );
  }
}

class SubtitleClipStyle {
  final String fontName;
  final double fontSize;
  final String primaryColor;
  final String strokeColor;
  final double strokeWidth;
  final String animation; // 'none' | 'pop_in' | 'karaoke' | 'fade'
  final String alignment; // 'center_bottom' | 'center_top' | 'center_middle'

  SubtitleClipStyle({
    this.fontName = 'Impact',
    this.fontSize = 28,
    this.primaryColor = '#FFFF00',
    this.strokeColor = '#000000',
    this.strokeWidth = 2.0,
    this.animation = 'pop_in',
    this.alignment = 'center_bottom',
  });

  factory SubtitleClipStyle.fromJson(Map<String, dynamic> json) =>
      SubtitleClipStyle(
        fontName: json['font_name'] as String? ?? 'Impact',
        fontSize: (json['font_size'] as num? ?? 28).toDouble(),
        primaryColor: json['primary_color'] as String? ?? '#FFFF00',
        strokeColor: json['stroke_color'] as String? ?? '#000000',
        strokeWidth: (json['stroke_width'] as num? ?? 2.0).toDouble(),
        animation: json['animation'] as String? ?? 'pop_in',
        alignment: json['alignment'] as String? ?? 'center_bottom',
      );

  Map<String, dynamic> toJson() => {
        'font_name': fontName,
        'font_size': fontSize,
        'primary_color': primaryColor,
        'stroke_color': strokeColor,
        'stroke_width': strokeWidth,
        'animation': animation,
        'alignment': alignment,
      };
}

class SubtitleClip {
  final String id;
  final String text;
  final double startTime;
  final double endTime;
  final SubtitleClipStyle style;

  SubtitleClip({
    required this.id,
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.style,
  });

  factory SubtitleClip.fromJson(Map<String, dynamic> json) => SubtitleClip(
        id: json['id'] as String,
        text: json['text'] as String,
        startTime: (json['start_time'] as num).toDouble(),
        endTime: (json['end_time'] as num).toDouble(),
        style: SubtitleClipStyle.fromJson(json['style'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'start_time': startTime,
        'end_time': endTime,
        'style': style.toJson(),
      };

  SubtitleClip copyWith({
    String? id,
    String? text,
    double? startTime,
    double? endTime,
    SubtitleClipStyle? style,
  }) =>
      SubtitleClip(
        id: id ?? this.id,
        text: text ?? this.text,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        style: style ?? this.style,
      );
}

class OverlayClip {
  final String id;
  final String type; // 'broll' | 'image' | 'text_sticker' | 'effect_overlay'
  final String sourcePath;
  final double startTimeInTimeline;
  final double endTimeInTimeline;
  final double sourceTrimStart;
  final double sourceTrimEnd;
  final double sourceDuration;
  final TransformState transform;

  OverlayClip({
    required this.id,
    required this.type,
    required this.sourcePath,
    required this.startTimeInTimeline,
    required this.endTimeInTimeline,
    required this.sourceTrimStart,
    required this.sourceTrimEnd,
    this.sourceDuration = 0.0,
    required this.transform,
  });

  factory OverlayClip.fromJson(Map<String, dynamic> json) => OverlayClip(
        id: json['id'] as String,
        type: json['type'] as String,
        sourcePath: json['source_path'] as String,
        startTimeInTimeline: (json['start_time_in_timeline'] as num).toDouble(),
        endTimeInTimeline: (json['end_time_in_timeline'] as num).toDouble(),
        sourceTrimStart: (json['source_trim_start'] as num).toDouble(),
        sourceTrimEnd: (json['source_trim_end'] as num).toDouble(),
        sourceDuration: (json['source_duration'] as num? ?? 0.0).toDouble(),
        transform: TransformState.fromJson(json['transform'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'source_path': sourcePath,
        'start_time_in_timeline': startTimeInTimeline,
        'end_time_in_timeline': endTimeInTimeline,
        'source_trim_start': sourceTrimStart,
        'source_trim_end': sourceTrimEnd,
        'source_duration': sourceDuration,
        'transform': transform.toJson(),
      };

  OverlayClip copyWith({
    String? id,
    String? type,
    String? sourcePath,
    double? startTimeInTimeline,
    double? endTimeInTimeline,
    double? sourceTrimStart,
    double? sourceTrimEnd,
    double? sourceDuration,
    TransformState? transform,
  }) =>
      OverlayClip(
        id: id ?? this.id,
        type: type ?? this.type,
        sourcePath: sourcePath ?? this.sourcePath,
        startTimeInTimeline: startTimeInTimeline ?? this.startTimeInTimeline,
        endTimeInTimeline: endTimeInTimeline ?? this.endTimeInTimeline,
        sourceTrimStart: sourceTrimStart ?? this.sourceTrimStart,
        sourceTrimEnd: sourceTrimEnd ?? this.sourceTrimEnd,
        sourceDuration: sourceDuration ?? this.sourceDuration,
        transform: transform ?? this.transform,
      );
}

class VideoTrack {
  final String id;
  final String name;
  final int index;
  final List<VideoClip> clips;

  VideoTrack({
    required this.id,
    required this.name,
    required this.index,
    required this.clips,
  });

  factory VideoTrack.fromJson(Map<String, dynamic> json) => VideoTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        index: json['index'] as int,
        clips: (json['clips'] as List<dynamic>)
            .map((e) => VideoClip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'index': index,
        'clips': clips.map((e) => e.toJson()).toList(),
      };

  VideoTrack copyWith({
    String? id,
    String? name,
    int? index,
    List<VideoClip>? clips,
  }) =>
      VideoTrack(
        id: id ?? this.id,
        name: name ?? this.name,
        index: index ?? this.index,
        clips: clips ?? this.clips,
      );
}

class AudioTrack {
  final String id;
  final String name;
  final int index;
  final List<AudioClip> clips;

  AudioTrack({
    required this.id,
    required this.name,
    required this.index,
    required this.clips,
  });

  factory AudioTrack.fromJson(Map<String, dynamic> json) => AudioTrack(
        id: json['id'] as String,
        name: json['name'] as String,
        index: json['index'] as int,
        clips: (json['clips'] as List<dynamic>)
            .map((e) => AudioClip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'index': index,
        'clips': clips.map((e) => e.toJson()).toList(),
      };

  AudioTrack copyWith({
    String? id,
    String? name,
    int? index,
    List<AudioClip>? clips,
  }) =>
      AudioTrack(
        id: id ?? this.id,
        name: name ?? this.name,
        index: index ?? this.index,
        clips: clips ?? this.clips,
      );
}

class SubtitleTrack {
  final String id;
  final List<SubtitleClip> clips;

  SubtitleTrack({required this.id, required this.clips});

  factory SubtitleTrack.fromJson(Map<String, dynamic> json) => SubtitleTrack(
        id: json['id'] as String,
        clips: (json['clips'] as List<dynamic>)
            .map((e) => SubtitleClip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clips': clips.map((e) => e.toJson()).toList(),
      };

  SubtitleTrack copyWith({String? id, List<SubtitleClip>? clips}) =>
      SubtitleTrack(
        id: id ?? this.id,
        clips: clips ?? this.clips,
      );
}

class OverlayTrack {
  final String id;
  final List<OverlayClip> clips;

  OverlayTrack({required this.id, required this.clips});

  factory OverlayTrack.fromJson(Map<String, dynamic> json) => OverlayTrack(
        id: json['id'] as String,
        clips: (json['clips'] as List<dynamic>)
            .map((e) => OverlayClip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clips': clips.map((e) => e.toJson()).toList(),
      };

  OverlayTrack copyWith({String? id, List<OverlayClip>? clips}) =>
      OverlayTrack(
        id: id ?? this.id,
        clips: clips ?? this.clips,
      );
}

class TextClip {
  final String id;
  final String text;
  final double startTime;
  final double endTime;
  final String fontFamily;
  final double fontSize;
  final int colorValue;
  final int? backgroundColorValue;
  final int? strokeColorValue;
  final double strokeWidth;
  final String alignment;
  final bool isBold;
  final bool isItalic;
  final double shadowBlur;
  final int? shadowColorValue;
  final double shadowOffsetX;
  final double shadowOffsetY;
  final String? animationType;
  final double animationDuration;

  TextClip({
    required this.id,
    required this.text,
    required this.startTime,
    required this.endTime,
    this.fontFamily = 'Roboto',
    this.fontSize = 48.0,
    this.colorValue = 0xFFFFFFFF,
    this.backgroundColorValue,
    this.strokeColorValue,
    this.strokeWidth = 0.0,
    this.alignment = 'center',
    this.isBold = false,
    this.isItalic = false,
    this.shadowBlur = 0.0,
    this.shadowColorValue,
    this.shadowOffsetX = 0.0,
    this.shadowOffsetY = 0.0,
    this.animationType,
    this.animationDuration = 0.5,
  });

  factory TextClip.fromJson(Map<String, dynamic> json) => TextClip(
        id: json['id'] as String,
        text: json['text'] as String,
        startTime: (json['start_time'] as num).toDouble(),
        endTime: (json['end_time'] as num).toDouble(),
        fontFamily: json['font_family'] as String? ?? 'Roboto',
        fontSize: (json['font_size'] as num?)?.toDouble() ?? 48.0,
        colorValue: json['color_value'] as int? ?? 0xFFFFFFFF,
        backgroundColorValue: json['background_color_value'] as int?,
        strokeColorValue: json['stroke_color_value'] as int?,
        strokeWidth: (json['stroke_width'] as num?)?.toDouble() ?? 0.0,
        alignment: json['alignment'] as String? ?? 'center',
        isBold: json['is_bold'] as bool? ?? false,
        isItalic: json['is_italic'] as bool? ?? false,
        shadowBlur: (json['shadow_blur'] as num?)?.toDouble() ?? 0.0,
        shadowColorValue: json['shadow_color_value'] as int?,
        shadowOffsetX: (json['shadow_offset_x'] as num?)?.toDouble() ?? 0.0,
        shadowOffsetY: (json['shadow_offset_y'] as num?)?.toDouble() ?? 0.0,
        animationType: json['animation_type'] as String?,
        animationDuration: (json['animation_duration'] as num?)?.toDouble() ?? 0.5,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'start_time': startTime,
        'end_time': endTime,
        'font_family': fontFamily,
        'font_size': fontSize,
        'color_value': colorValue,
        'background_color_value': backgroundColorValue,
        'stroke_color_value': strokeColorValue,
        'stroke_width': strokeWidth,
        'alignment': alignment,
        'is_bold': isBold,
        'is_italic': isItalic,
        'shadow_blur': shadowBlur,
        'shadow_color_value': shadowColorValue,
        'shadow_offset_x': shadowOffsetX,
        'shadow_offset_y': shadowOffsetY,
        'animation_type': animationType,
        'animation_duration': animationDuration,
      };

  TextClip copyWith({
    String? id,
    String? text,
    double? startTime,
    double? endTime,
    String? fontFamily,
    double? fontSize,
    int? colorValue,
    int? backgroundColorValue,
    int? strokeColorValue,
    double? strokeWidth,
    String? alignment,
    bool? isBold,
    bool? isItalic,
    double? shadowBlur,
    int? shadowColorValue,
    double? shadowOffsetX,
    double? shadowOffsetY,
    String? animationType,
    double? animationDuration,
  }) =>
      TextClip(
        id: id ?? this.id,
        text: text ?? this.text,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        colorValue: colorValue ?? this.colorValue,
        backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
        strokeColorValue: strokeColorValue ?? this.strokeColorValue,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        alignment: alignment ?? this.alignment,
        isBold: isBold ?? this.isBold,
        isItalic: isItalic ?? this.isItalic,
        shadowBlur: shadowBlur ?? this.shadowBlur,
        shadowColorValue: shadowColorValue ?? this.shadowColorValue,
        shadowOffsetX: shadowOffsetX ?? this.shadowOffsetX,
        shadowOffsetY: shadowOffsetY ?? this.shadowOffsetY,
        animationType: animationType ?? this.animationType,
        animationDuration: animationDuration ?? this.animationDuration,
      );
}

class TextTrack {
  final String id;
  final List<TextClip> clips;

  TextTrack({required this.id, required this.clips});

  factory TextTrack.fromJson(Map<String, dynamic> json) => TextTrack(
        id: json['id'] as String,
        clips: (json['clips'] as List<dynamic>)
            .map((e) => TextClip.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'clips': clips.map((e) => e.toJson()).toList(),
      };

  TextTrack copyWith({String? id, List<TextClip>? clips}) =>
      TextTrack(
        id: id ?? this.id,
        clips: clips ?? this.clips,
      );
}

class Tracks {
  final List<VideoTrack> video;
  final List<AudioTrack> audio;
  final List<SubtitleTrack> subtitles;
  final List<OverlayTrack> overlays;
  final List<TextTrack> text;
  final List<String> nestedSequenceIds;

  Tracks({
    required this.video,
    required this.audio,
    required this.subtitles,
    required this.overlays,
    required this.text,
    this.nestedSequenceIds = const [],
  });

  factory Tracks.empty() => Tracks(
        video: [VideoTrack(id: 'v_main', name: 'Video 1', index: 0, clips: [])],
        audio: [AudioTrack(id: 'a_main', name: 'Audio 1', index: 0, clips: [])],
        subtitles: [SubtitleTrack(id: 'sub_main', clips: [])],
        overlays: [OverlayTrack(id: 'ov_main', clips: [])],
        text: [TextTrack(id: 'txt_main', clips: [])],
        nestedSequenceIds: const [],
      );

  factory Tracks.fromJson(Map<String, dynamic> json) => Tracks(
        video: (json['video'] as List<dynamic>)
            .map((e) => VideoTrack.fromJson(e as Map<String, dynamic>))
            .toList(),
        audio: (json['audio'] as List<dynamic>)
            .map((e) => AudioTrack.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtitles: (json['subtitles'] as List<dynamic>)
            .map((e) => SubtitleTrack.fromJson(e as Map<String, dynamic>))
            .toList(),
        overlays: (json['overlays'] as List<dynamic>)
            .map((e) => OverlayTrack.fromJson(e as Map<String, dynamic>))
            .toList(),
        text: (json['text'] as List<dynamic>?)
                ?.map((e) => TextTrack.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        nestedSequenceIds: (json['nestedSequenceIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'video': video.map((e) => e.toJson()).toList(),
        'audio': audio.map((e) => e.toJson()).toList(),
        'subtitles': subtitles.map((e) => e.toJson()).toList(),
        'overlays': overlays.map((e) => e.toJson()).toList(),
        'text': text.map((e) => e.toJson()).toList(),
        'nestedSequenceIds': nestedSequenceIds,
      };

  Tracks copyWith({
    List<VideoTrack>? video,
    List<AudioTrack>? audio,
    List<SubtitleTrack>? subtitles,
    List<OverlayTrack>? overlays,
    List<TextTrack>? text,
    List<String>? nestedSequenceIds,
  }) =>
      Tracks(
        video: video ?? this.video,
        audio: audio ?? this.audio,
        subtitles: subtitles ?? this.subtitles,
        overlays: overlays ?? this.overlays,
        text: text ?? this.text,
        nestedSequenceIds: nestedSequenceIds ?? this.nestedSequenceIds,
      );
}

class NestedSequence {
  final String id;
  final String name;
  final Tracks tracks;
  final TimelineSettings settings;
  final double duration;
  final double startTimeInTimeline;

  NestedSequence({
    required this.id,
    required this.name,
    required this.tracks,
    required this.settings,
    this.duration = 0,
    this.startTimeInTimeline = 0,
  });

  factory NestedSequence.empty(String id, String name) => NestedSequence(
        id: id,
        name: name,
        tracks: Tracks.empty(),
        settings: TimelineSettings(),
      );

  factory NestedSequence.fromTimeline(TimelineState state, {double startTime = 0}) =>
      NestedSequence(
        id: 'nested_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Nested Sequence',
        tracks: state.tracks,
        settings: state.settings,
        duration: state.playheadSec,
        startTimeInTimeline: startTime,
      );

  TimelineState toTimelineState() => TimelineState(
        projectId: id,
        projectName: name,
        settings: settings,
        tracks: tracks,
        playheadSec: 0,
        zoomLevel: 30,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tracks': tracks.toJson(),
        'settings': settings.toJson(),
        'duration': duration,
        'startTimeInTimeline': startTimeInTimeline,
      };

  factory NestedSequence.fromJson(Map<String, dynamic> json) => NestedSequence(
        id: json['id'] as String,
        name: json['name'] as String,
        tracks: Tracks.fromJson(json['tracks'] as Map<String, dynamic>),
        settings: TimelineSettings.fromJson(json['settings'] as Map<String, dynamic>),
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        startTimeInTimeline: (json['startTimeInTimeline'] as num?)?.toDouble() ?? 0,
      );
}

class TimelineSettings {
  final int width;
  final int height;
  final int fps;
  final int sampleRate;
  final String aspectRatio; // '9:16' | '16:9' | '1:1'

  TimelineSettings({
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.sampleRate = 44100,
    this.aspectRatio = '9:16',
  });

  factory TimelineSettings.fromJson(Map<String, dynamic> json) =>
      TimelineSettings(
        width: json['width'] as int? ?? 1080,
        height: json['height'] as int? ?? 1920,
        fps: json['fps'] as int? ?? 30,
        sampleRate: json['sample_rate'] as int? ?? 44100,
        aspectRatio: json['aspect_ratio'] as String? ?? '9:16',
      );

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'fps': fps,
        'sample_rate': sampleRate,
        'aspect_ratio': aspectRatio,
      };

  TimelineSettings copyWith({
    int? width,
    int? height,
    int? fps,
    int? sampleRate,
    String? aspectRatio,
  }) =>
      TimelineSettings(
        width: width ?? this.width,
        height: height ?? this.height,
        fps: fps ?? this.fps,
        sampleRate: sampleRate ?? this.sampleRate,
        aspectRatio: aspectRatio ?? this.aspectRatio,
      );
}

class MulticamAngle {
  final String angleId;
  final String name;
  final String sourcePath;
  final double startOffset;
  final int colorValue;
  final String? audioSource;

  MulticamAngle({
    required this.angleId,
    required this.name,
    required this.sourcePath,
    this.startOffset = 0.0,
    this.colorValue = 0xFF0A84FF,
    this.audioSource,
  });

  factory MulticamAngle.fromJson(Map<String, dynamic> json) => MulticamAngle(
        angleId: json['angleId'] as String,
        name: json['name'] as String,
        sourcePath: json['source_path'] as String,
        startOffset: (json['start_offset'] as num?)?.toDouble() ?? 0.0,
        colorValue: json['colorValue'] as int? ?? 0xFF0A84FF,
        audioSource: json['audio_source'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'angleId': angleId,
        'name': name,
        'source_path': sourcePath,
        'start_offset': startOffset,
        'colorValue': colorValue,
        'audio_source': audioSource,
      };

  MulticamAngle copyWith({
    String? angleId,
    String? name,
    String? sourcePath,
    double? startOffset,
    int? colorValue,
    String? audioSource,
  }) =>
      MulticamAngle(
        angleId: angleId ?? this.angleId,
        name: name ?? this.name,
        sourcePath: sourcePath ?? this.sourcePath,
        startOffset: startOffset ?? this.startOffset,
        colorValue: colorValue ?? this.colorValue,
        audioSource: audioSource ?? this.audioSource,
      );
}

class AngleSwitch {
  final double time;
  final String angleId;

  const AngleSwitch({required this.time, required this.angleId});

  factory AngleSwitch.fromJson(Map<String, dynamic> json) => AngleSwitch(
        time: (json['time'] as num).toDouble(),
        angleId: json['angleId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'time': time,
        'angleId': angleId,
      };

  AngleSwitch copyWith({double? time, String? angleId}) =>
      AngleSwitch(time: time ?? this.time, angleId: angleId ?? this.angleId);
}

class MulticamClip {
  final String id;
  final List<MulticamAngle> angles;
  final double syncOffset;
  final List<AngleSwitch> switches;

  MulticamClip({
    required this.id,
    required this.angles,
    this.syncOffset = 0.0,
    this.switches = const [],
  });

  double get duration {
    if (angles.isEmpty) return 0.0;
    return angles.fold(0.0, (max, a) => a.startOffset > max ? a.startOffset : max);
  }

  String getActiveAngleIdAtTime(double timeSec) {
    AngleSwitch? lastSwitch;
    for (final sw in switches) {
      if (sw.time <= timeSec) lastSwitch = sw;
    }
    return lastSwitch?.angleId ?? (angles.isNotEmpty ? angles.first.angleId : '');
  }

  MulticamAngle? getAngleById(String angleId) {
    for (final a in angles) {
      if (a.angleId == angleId) return a;
    }
    return null;
  }

  int getActiveAngleIndexAtTime(double timeSec) {
    final id = getActiveAngleIdAtTime(timeSec);
    for (int i = 0; i < angles.length; i++) {
      if (angles[i].angleId == id) return i;
    }
    return 0;
  }

  factory MulticamClip.fromJson(Map<String, dynamic> json) => MulticamClip(
        id: json['id'] as String,
        angles: (json['angles'] as List<dynamic>)
            .map((e) => MulticamAngle.fromJson(e as Map<String, dynamic>))
            .toList(),
        syncOffset: (json['sync_offset'] as num?)?.toDouble() ?? 0.0,
        switches: (json['switches'] as List<dynamic>?)
                ?.map((e) => AngleSwitch.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'angles': angles.map((e) => e.toJson()).toList(),
        'sync_offset': syncOffset,
        'switches': switches.map((e) => e.toJson()).toList(),
      };

  MulticamClip copyWith({
    String? id,
    List<MulticamAngle>? angles,
    double? syncOffset,
    List<AngleSwitch>? switches,
  }) =>
      MulticamClip(
        id: id ?? this.id,
        angles: angles ?? this.angles,
        syncOffset: syncOffset ?? this.syncOffset,
        switches: switches ?? this.switches,
      );
}

class TimelineState {
  final String projectId;
  final String projectName;
  final TimelineSettings settings;
  final Tracks tracks;
  final double playheadSec;
  final double zoomLevel;
  final List<NestedSequence> nestedSequences;
  final bool collaborationEnabled;
  final MulticamClip? activeMulticam;

  TimelineState({
    required this.projectId,
    required this.projectName,
    required this.settings,
    required this.tracks,
    this.playheadSec = 0.0,
    this.zoomLevel = 30.0,
    this.nestedSequences = const [],
    this.collaborationEnabled = false,
    this.activeMulticam,
  });

  factory TimelineState.empty() => TimelineState(
        projectId: 'project_new',
        projectName: 'مشروع جديد',
        settings: TimelineSettings(),
        tracks: Tracks.empty(),
        playheadSec: 0.0,
        zoomLevel: 30.0,
        nestedSequences: const [],
        collaborationEnabled: false,
        activeMulticam: null,
      );

  factory TimelineState.fromJson(Map<String, dynamic> json) => TimelineState(
        projectId: json['project_id'] as String? ?? 'project_new',
        projectName: json['project_name'] as String? ?? 'مشروع جديد',
        settings: TimelineSettings.fromJson(json['settings'] as Map<String, dynamic>),
        tracks: Tracks.fromJson(json['tracks'] as Map<String, dynamic>),
        playheadSec: (json['playheadSec'] as num? ?? 0.0).toDouble(),
        zoomLevel: (json['zoomLevel'] as num? ?? 30.0).toDouble(),
        nestedSequences: (json['nestedSequences'] as List<dynamic>?)
                ?.map((e) => NestedSequence.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        collaborationEnabled: json['collaborationEnabled'] as bool? ?? false,
        activeMulticam: json['activeMulticam'] != null
            ? MulticamClip.fromJson(json['activeMulticam'] as Map<String, dynamic>)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'project_id': projectId,
        'project_name': projectName,
        'settings': settings.toJson(),
        'tracks': tracks.toJson(),
        'playheadSec': playheadSec,
        'zoomLevel': zoomLevel,
        'nestedSequences': nestedSequences.map((e) => e.toJson()).toList(),
        'collaborationEnabled': collaborationEnabled,
        if (activeMulticam != null) 'activeMulticam': activeMulticam!.toJson(),
      };

  TimelineState copyWith({
    String? projectId,
    String? projectName,
    TimelineSettings? settings,
    Tracks? tracks,
    double? playheadSec,
    double? zoomLevel,
    List<NestedSequence>? nestedSequences,
    bool? collaborationEnabled,
    MulticamClip? activeMulticam,
  }) =>
      TimelineState(
        projectId: projectId ?? this.projectId,
        projectName: projectName ?? this.projectName,
        settings: settings ?? this.settings,
        tracks: tracks ?? this.tracks,
        playheadSec: playheadSec ?? this.playheadSec,
        zoomLevel: zoomLevel ?? this.zoomLevel,
        nestedSequences: nestedSequences ?? this.nestedSequences,
        collaborationEnabled: collaborationEnabled ?? this.collaborationEnabled,
        activeMulticam: activeMulticam ?? this.activeMulticam,
      );
}

class Word {
  final String text;
  final double start;
  final double end;

  Word({required this.text, required this.start, required this.end});

  factory Word.fromJson(Map<String, dynamic> json) => Word(
        text: json['text'] as String,
        start: (json['start'] as num).toDouble(),
        end: (json['end'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'text': text, 'start': start, 'end': end};
}

class SemanticClip {
  final int index;
  final double startSec;
  final double endSec;
  final String hook;
  final String reason;
  final String captionTheme;
  final String zoomStyle;
  final String colorGrade;
  final List<String> emphasisWords;
  final List<String> sfxQueries;
  final List<dynamic> plannedBrolls;
  final List<String> hookOptions;
  final double slowMotionStart;
  final double slowMotionEnd;
  final double slowMotionSpeed;

  SemanticClip({
    required this.index,
    required this.startSec,
    required this.endSec,
    required this.hook,
    required this.reason,
    this.captionTheme = 'TikTok',
    this.zoomStyle = 'none',
    this.colorGrade = 'original',
    required this.emphasisWords,
    required this.sfxQueries,
    required this.plannedBrolls,
    required this.hookOptions,
    this.slowMotionStart = 0.0,
    this.slowMotionEnd = 0.0,
    this.slowMotionSpeed = 1.0,
  });

  factory SemanticClip.fromJson(Map<String, dynamic> json) => SemanticClip(
        index: json['index'] as int,
        startSec: (json['start_sec'] as num).toDouble(),
        endSec: (json['end_sec'] as num).toDouble(),
        hook: json['hook'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        captionTheme: json['caption_theme'] as String? ?? 'TikTok',
        zoomStyle: json['zoom_style'] as String? ?? 'none',
        colorGrade: json['color_grade'] as String? ?? 'original',
        emphasisWords: (json['emphasis_words'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        sfxQueries: (json['sfx_queries'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        plannedBrolls: json['planned_brolls'] as List<dynamic>? ?? [],
        hookOptions: (json['hook_options'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        slowMotionStart: (json['slow_motion_start'] as num? ?? 0.0).toDouble(),
        slowMotionEnd: (json['slow_motion_end'] as num? ?? 0.0).toDouble(),
        slowMotionSpeed: (json['slow_motion_speed'] as num? ?? 1.0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'start_sec': startSec,
        'end_sec': endSec,
        'hook': hook,
        'reason': reason,
        'caption_theme': captionTheme,
        'zoom_style': zoomStyle,
        'color_grade': colorGrade,
        'emphasis_words': emphasisWords,
        'sfx_queries': sfxQueries,
        'planned_brolls': plannedBrolls,
        'hook_options': hookOptions,
        'slow_motion_start': slowMotionStart,
        'slow_motion_end': slowMotionEnd,
        'slow_motion_speed': slowMotionSpeed,
      };
}
