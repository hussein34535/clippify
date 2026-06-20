import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ignore_for_file: deprecated_member_use

import '../../timeline/providers/timeline_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/timeline_models.dart';
import '../../../core/models/pro_color_models.dart';
import '../../../shared/providers/playback_provider.dart';
import '../../../shared/utils/keyframe_interpolation.dart';
import '../../audio/effects/audio_engine.dart';
import '../../motion/particles/particle_system.dart';
import '../../motion/shapes/shape_system.dart';
import '../../../core/rendering/shader_system.dart';
import '../../capture/capture_suite.dart';
import '../../../core/rendering/color_matrix_utils.dart';

class VideoPlayerWidget extends ConsumerStatefulWidget {
  final String? videoPath;

  const VideoPlayerWidget({
    super.key,
    required this.videoPath,
  });

  @override
  ConsumerState<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends ConsumerState<VideoPlayerWidget> {
  late final Player _player;
  late final VideoController _controller;
  bool _isPlaying = false;
  double _volume = 1.0;
  bool _isMuted = false;
  bool _isSeeking = false;
  int? _pendingSeekPos;

  VideoClip? _currentClip;
  // ignore: unused_field
  AudioEffectChain? _effectChain;

  ProviderSubscription? _isPlayingSub;
  ProviderSubscription? _playheadSub;
  ProviderSubscription? _scrubSub;

  Future<void> _safeSeek(int targetPosMs) async {
    if (_isSeeking) {
      _pendingSeekPos = targetPosMs;
      return;
    }
    _isSeeking = true;
    try {
      await _player.seek(Duration(milliseconds: targetPosMs));
    } catch (_) {}
    _isSeeking = false;
    if (_pendingSeekPos != null) {
      final nextPos = _pendingSeekPos!;
      _pendingSeekPos = null;
      _safeSeek(nextPos);
    }
  }

  VideoClip? _findClipAtPlayhead(double playheadSec) {
    final state = ref.read(timelineProvider).timeline;
    for (final track in state.tracks.video) {
      for (final clip in track.clips) {
        if (playheadSec >= clip.startTimeInTimeline && playheadSec < clip.endTimeInTimeline) {
          return clip;
        }
      }
    }
    return null;
  }

  double _getTransitionProgress() {
    if (_currentClip == null) return 0.0;
    final clip = _currentClip!;
    if (clip.outTransition.type == 'none') return 0.0;

    final transitionDuration = clip.outTransition.duration;
    final clipDuration = clip.endTimeInTimeline - clip.startTimeInTimeline;
    final transitionStart = clipDuration - transitionDuration;
    final currentTimeInClip = ref.read(timelineProvider).timeline.playheadSec - clip.startTimeInTimeline;

    if (currentTimeInClip >= transitionStart && currentTimeInClip < clipDuration) {
      return (currentTimeInClip - transitionStart) / transitionDuration;
    }
    return 0.0;
  }

  Widget _applyTransition(Widget child, String type, double progress) {
    switch (type) {
      case 'fade_to_black':
        return Opacity(
          opacity: 1.0 - progress,
          child: Container(
            color: Colors.black,
            child: child,
          ),
        );
      case 'fade_to_white':
        return Opacity(
          opacity: 1.0 - progress,
          child: Container(
            color: Colors.white,
            child: child,
          ),
        );
      case 'cross_dissolve':
        return Opacity(
          opacity: 1.0 - progress,
          child: child,
        );
      case 'wipe_left':
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(-progress, 0),
            child: child,
          ),
        );
      case 'wipe_right':
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(progress, 0),
            child: child,
          ),
        );
      case 'wipe_up':
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(0, -progress),
            child: child,
          ),
        );
      case 'wipe_down':
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(0, progress),
            child: child,
          ),
        );
      case 'zoom_in':
        return Transform.scale(
          scale: 1.0 + progress,
          child: Opacity(
            opacity: 1.0 - progress,
            child: child,
          ),
        );
      case 'zoom_out':
        return Transform.scale(
          scale: 1.0 - progress,
          child: Opacity(
            opacity: 1.0 - progress,
            child: child,
          ),
        );
      case 'spin':
        return Transform.rotate(
          angle: progress * math.pi * 2,
          child: Opacity(
            opacity: 1.0 - progress,
            child: child,
          ),
        );
      case 'blur':
        return ColorFiltered(
          colorFilter: ColorFilter.matrix([
            1.0 - progress, 0, 0, 0, 0,
            0, 1.0 - progress, 0, 0, 0,
            0, 0, 1.0 - progress, 0, 0,
            0, 0, 0, 1, 0,
          ]),
          child: Opacity(
            opacity: 1.0 - progress,
            child: child,
          ),
        );
      default:
        return child;
    }
  }

  void _applyClipSettings() {
    if (_currentClip == null) return;
    final clip = _currentClip!;

    // Apply speed ramping if available
    final playhead = ref.read(timelineProvider).timeline.playheadSec;
    final timeInClip = playhead - clip.startTimeInTimeline;
    if (clip.speedRamp.points.isNotEmpty) {
      final rampSpeed = clip.speedRamp.getSpeedAtTime(timeInClip, clip.endTimeInTimeline - clip.startTimeInTimeline);
      _player.setRate(rampSpeed);
    } else {
      _player.setRate(clip.speed);
    }

    // Apply EQ-based volume: bass/mid/treble averaged then scaled by volume
    final eqMultiplier = (clip.bass + clip.mid + clip.treble) / 3.0;
    _player.setVolume((eqMultiplier * clip.volume * _volume * (_isMuted ? 0.0 : 1.0)).clamp(0.0, 100.0));

    // Build AudioEffectChain from clip.audioEffects
    final chain = AudioEffectChain();
    if (clip.audioEffects.contains('reverb')) {
      final reverb = ReverbEffect(decay: clip.reverbAmount.clamp(0.0, 0.99));
      reverb.mix = clip.reverbAmount;
      chain.add(reverb);
    }
    if (clip.audioEffects.contains('delay')) {
      final delay = DelayEffect(feedback: clip.delayAmount.clamp(0.0, 0.99));
      delay.mix = clip.delayAmount;
      chain.add(delay);
    }
    if (clip.audioEffects.contains('compressor')) {
      chain.add(CompressorEffect(
        threshold: 1.0 - clip.compressorAmount.clamp(0.0, 1.0),
        ratio: 2.0 + clip.compressorAmount * 18.0,
      ));
    }
    if (clip.audioEffects.contains('noise_gate')) {
      final gate = CompressorEffect(threshold: 0.05, ratio: 20, attack: 0.001, release: 0.05);
      chain.add(gate);
    }
    if (clip.audioEffects.contains('distortion')) {
      chain.add(DistortionEffect(drive: 1.0 + clip.compressorAmount * 3.0));
    }
    if (clip.audioEffects.contains('low_pass')) {
      chain.add(FilterEffect(filterType: 'lowpass', cutoff: 0.3));
    }
    if (clip.audioEffects.contains('high_pass')) {
      chain.add(FilterEffect(filterType: 'highpass', cutoff: 0.7));
    }
    // Note: chain.process() requires raw audio samples. For media_kit playback
    // the effect parameters are ready for when a sample-level pipeline is connected.
    _effectChain = chain;
  }

  List<TextClip> _getActiveTextClips(double playhead) {
    final state = ref.read(timelineProvider).timeline;
    final activeClips = <TextClip>[];
    for (final track in state.tracks.text) {
      for (final clip in track.clips) {
        if (playhead >= clip.startTime && playhead < clip.endTime) {
          activeClips.add(clip);
        }
      }
    }
    return activeClips;
  }

  Widget _buildTextOverlay(TextClip clip, double playhead) {
    final timeInClip = playhead - clip.startTime;
    final clipDuration = clip.endTime - clip.startTime;
    final progress = (timeInClip / clipDuration).clamp(0.0, 1.0);

    double opacity = 1.0;
    Offset offset = Offset.zero;
    double scale = 1.0;

    if (clip.animationType != null) {
      final animProgress = (timeInClip / clip.animationDuration).clamp(0.0, 1.0);
      switch (clip.animationType) {
        case 'fade_in':
          opacity = animProgress;
          break;
        case 'fade_out':
          opacity = 1.0 - animProgress;
          break;
        case 'slide_up':
          offset = Offset(0, 50 * (1.0 - animProgress));
          break;
        case 'slide_down':
          offset = Offset(0, -50 * (1.0 - animProgress));
          break;
        case 'slide_left':
          offset = Offset(50 * (1.0 - animProgress), 0);
          break;
        case 'slide_right':
          offset = Offset(-50 * (1.0 - animProgress), 0);
          break;
        case 'scale_in':
          scale = animProgress;
          break;
        case 'scale_out':
          scale = 1.0 - animProgress;
          break;
      }
    }

    TextAlign textAlign;
    switch (clip.alignment) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      default:
        textAlign = TextAlign.center;
    }

    Alignment alignment;
    switch (clip.alignment) {
      case 'left':
        alignment = Alignment.centerLeft;
        break;
      case 'right':
        alignment = Alignment.centerRight;
        break;
      default:
        alignment = Alignment.center;
    }

    String displayText = clip.text;
    if (clip.animationType == 'typewriter') {
      final charCount = (clip.text.length * progress).floor();
      displayText = clip.text.substring(0, charCount);
    }

    return Positioned.fill(
      child: Transform.translate(
        offset: offset,
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity,
            child: Container(
              alignment: alignment,
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: clip.backgroundColorValue != null
                    ? BoxDecoration(
                        color: Color(clip.backgroundColorValue!),
                        borderRadius: BorderRadius.circular(4),
                      )
                    : null,
                child: Text(
                  displayText,
                  style: TextStyle(
                    fontFamily: clip.fontFamily,
                    fontSize: clip.fontSize,
                    color: Color(clip.colorValue),
                    fontWeight: clip.isBold ? FontWeight.bold : FontWeight.normal,
                    fontStyle: clip.isItalic ? FontStyle.italic : FontStyle.normal,
                    shadows: clip.shadowColorValue != null
                        ? [
                            Shadow(
                              blurRadius: clip.shadowBlur,
                              color: Color(clip.shadowColorValue!),
                              offset: Offset(clip.shadowOffsetX, clip.shadowOffsetY),
                            ),
                          ]
                        : null,
                  ),
                  textAlign: textAlign,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParticleOverlays(BoxConstraints constraints, VideoClip clip) {
    final widgets = <Widget>[];
    for (final effect in clip.particleEffects) {
      if (effect['enabled'] != true) continue;
      final type = effect['type'] as String? ?? 'fire';
      final cx = constraints.maxWidth / 2;
      final cy = constraints.maxHeight / 2;
      final position = switch (type) {
        'rain' || 'snow' || 'smoke' => Offset(cx, -20),
        _ => Offset(cx, cy),
      };
      final emitter = switch (type) {
        'smoke' => ParticleEmitter.smoke(position),
        'sparkles' => ParticleEmitter.sparkles(position),
        'rain' => ParticleEmitter.rain(position),
        'snow' => ParticleEmitter.snow(position),
        'explosion' => ParticleEmitter.explosion(position),
        _ => ParticleEmitter.fire(position),
      };
      widgets.add(Positioned.fill(
        child: IgnorePointer(child: ParticleWidget(emitter: emitter)),
      ));
    }
    return widgets;
  }

  Widget _buildShapeOverlay(BoxConstraints constraints, VideoClip clip, double playheadSec) {
    final shapes = <ShapeLayer>[];
    for (int i = 0; i < clip.shapeOverlays.length; i++) {
      final s = clip.shapeOverlays[i];
      if (s['opacity'] == 0) continue;
      final type = s['type'] as String? ?? 'rectangle';
      final color = Color(s['color'] as int? ?? 0xFFFFFFFF);
      final posX = (s['position_x'] as num?)?.toDouble() ?? constraints.maxWidth / 2;
      final posY = (s['position_y'] as num?)?.toDouble() ?? constraints.maxHeight / 2;
      final rotation = (s['rotation'] as num?)?.toDouble() ?? 0.0;
      final opacity = (s['opacity'] as num?)?.toDouble() ?? 1.0;
      final w = (s['width'] as num?)?.toDouble() ?? 100;
      final h = (s['height'] as num?)?.toDouble() ?? 100;
      shapes.add(switch (type) {
        'ellipse' => EllipseShape(
            id: 'shape_$i', position: Offset(posX, posY), color: color,
            radiusX: w / 2, radiusY: h / 2, rotation: rotation, opacity: opacity,
          ),
        'polygon' => PolygonShape(
            id: 'shape_$i', position: Offset(posX, posY), color: color,
            radius: w / 2, rotation: rotation, opacity: opacity,
          ),
        'star' => StarShape(
            id: 'shape_$i', position: Offset(posX, posY), color: color,
            outerRadius: w / 2, innerRadius: w / 4, rotation: rotation, opacity: opacity,
          ),
        'line' => LineShape(
            id: 'shape_$i', position: Offset(posX, posY), color: color,
            endPoint: Offset(posX + w, posY + h), rotation: rotation, opacity: opacity,
          ),
        _ => RectangleShape(
            id: 'shape_$i', position: Offset(posX, posY), color: color,
            width: w, height: h, rotation: rotation, opacity: opacity,
          ),
      });
    }
    return Positioned.fill(
      child: IgnorePointer(child: ShapeLayerWidget(shapes: shapes, time: playheadSec)),
    );
  }

  Widget _wrapWithShaderEffects(Widget child, List<String> effects) {
    var result = child;
    for (final effect in effects) {
      result = switch (effect.toLowerCase()) {
        'vignette' => VignetteEffect(child: result),
        'sepia' => SepiaEffect(child: result),
        'invert' => InvertEffect(child: result),
        'pixelate' => PixelateEffect(child: result),
        'sharpen' => SharpenEffect(child: result),
        'brightness_contrast' => BrightnessContrastEffect(child: result),
        'saturation' => SaturationEffect(child: result),
        'blur' => BlurEffect(child: result),
        _ => result,
      };
    }
    return result;
  }

  @override
  void initState() {
    super.initState();

    _player = Player();

    if (_player.platform is NativePlayer) {
      final nativePlayer = _player.platform as NativePlayer;
      nativePlayer.setProperty('cache', 'yes');
      nativePlayer.setProperty('demuxer-max-bytes', '524288000');
      nativePlayer.setProperty('demuxer-max-back-bytes', '262144000');
    }

    _controller = VideoController(_player);

    _player.stream.position.listen((pos) {
      if (_isPlaying) {
        ref.read(timelineProvider.notifier).setPlayhead(pos.inMilliseconds / 1000.0);
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
        });
        if (ref.read(isPlayingProvider) != playing) {
          ref.read(isPlayingProvider.notifier).state = playing;
        }
      }
    });

    _loadVideo();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _isPlayingSub = ref.listenManual<bool>(isPlayingProvider, (oldVal, newVal) {
        if (newVal != _isPlaying) {
          if (newVal) {
            _player.play();
          } else {
            _player.pause();
          }
        }
      });

      _playheadSub = ref.listenManual(
        timelineProvider.select((value) => value.timeline.playheadSec),
        (oldSec, newSec) {
          _currentClip = _findClipAtPlayhead(newSec);
          _applyClipSettings();
          if (!_isPlaying) {
            final targetPosMs = (newSec * 1000.0).round();
            _safeSeek(targetPosMs);
          }
        },
      );

      _scrubSub = ref.listenManual<double>(scrubPlayheadProvider, (oldVal, newVal) {
        if (!_isPlaying) {
          _currentClip = _findClipAtPlayhead(newVal);
          _applyClipSettings();
          _safeSeek((newVal * 1000.0).round());
        }
      });

      _currentClip = _findClipAtPlayhead(ref.read(timelineProvider).timeline.playheadSec);
      _applyClipSettings();
    });
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoPath != oldWidget.videoPath) {
      _loadVideo();
    }
  }

  void _loadVideo() {
    if (widget.videoPath != null && widget.videoPath!.isNotEmpty) {
      final file = File(widget.videoPath!);
      if (file.existsSync()) {
        _player.open(Media(file.path));
        _player.pause();
      }
    }
  }

  @override
  void dispose() {
    _isPlayingSub?.close();
    _playheadSub?.close();
    _scrubSub?.close();
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() {
    ref.read(isPlayingProvider.notifier).update((state) => !state);
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _player.setVolume(_isMuted ? 0.0 : _volume * 100.0);
    });
  }

  void _changeVolume(double val) {
    setState(() {
      _volume = val;
      _isMuted = false;
      _player.setVolume(_volume * 100.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final timelineData = ref.watch(timelineProvider);
    final playhead = timelineData.timeline.playheadSec;
    final maxDuration = ref.read(timelineProvider.notifier).totalDuration;

    _currentClip = _findClipAtPlayhead(playhead);

    // Keyframe animation interpolation
    TransformState animatedTransform = _currentClip?.transform ?? TransformState.defaultState();

    if (_currentClip != null && _currentClip!.transform.keyframes.isNotEmpty) {
      final timeInClip = playhead - _currentClip!.startTimeInTimeline;
      final kfs = _currentClip!.transform.keyframes;

      final posX = KeyframeAnimationEngine.interpolate(kfs, 'position_x', timeInClip);
      final posY = KeyframeAnimationEngine.interpolate(kfs, 'position_y', timeInClip);
      final scaleX = KeyframeAnimationEngine.interpolate(kfs, 'scale_x', timeInClip);
      final scaleY = KeyframeAnimationEngine.interpolate(kfs, 'scale_y', timeInClip);
      final rot = KeyframeAnimationEngine.interpolate(kfs, 'rotation', timeInClip);

      if (kfs.any((k) => k.property.startsWith('position'))) {
        animatedTransform = animatedTransform.copyWith(
          position: Vector2D(x: posX, y: posY),
        );
      }
      if (kfs.any((k) => k.property.startsWith('scale'))) {
        animatedTransform = animatedTransform.copyWith(
          scale: Vector2D(x: scaleX, y: scaleY),
        );
      }
      if (kfs.any((k) => k.property == 'rotation')) {
        animatedTransform = animatedTransform.copyWith(rotation: rot);
      }
    }

    if (_currentClip != null &&
        _currentClip!.useTracking &&
        _currentClip!.trackedPosition.isNotEmpty) {
      final timeInClip = playhead - _currentClip!.startTimeInTimeline;
      final trackedX = KeyframeAnimationEngine.interpolate(
          _currentClip!.trackedPosition, 'tracked_x', timeInClip);
      final trackedY = KeyframeAnimationEngine.interpolate(
          _currentClip!.trackedPosition, 'tracked_y', timeInClip);

      if (_currentClip!.trackingType == 'crop') {
        final croppedX = -(trackedX - 960);
        animatedTransform = animatedTransform.copyWith(
          position: Vector2D(x: croppedX, y: 0),
        );
      } else {
        animatedTransform = animatedTransform.copyWith(
          position: Vector2D(x: trackedX - 960, y: trackedY - 540),
        );
      }
    }

    final clipTransform = animatedTransform;
    final clipColor = _currentClip?.colorGrading ?? ColorGradingState();
    final clipProColor = _currentClip?.proColor ?? const ProColorState();

    final bool hasColorGrading =
        clipColor.brightness != 0.0 || clipColor.contrast != 1.0 || clipColor.saturation != 1.0 ||
        clipProColor.lift.saturation > 0.0 || clipProColor.gamma.saturation > 0.0 ||
        clipProColor.gain.saturation > 0.0 || clipProColor.offset != 0.0 ||
        clipProColor.contrast != 1.0 || clipProColor.shadowClip > 0.0 ||
        clipProColor.highlightClip > 0.0;

    final bool hasTransform =
        clipTransform.position.x != 0 || clipTransform.position.y != 0 ||
        clipTransform.scale.x != 100 || clipTransform.scale.y != 100 ||
        clipTransform.rotation != 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget videoContent = widget.videoPath != null && widget.videoPath!.isNotEmpty
            ? ClipRect(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              )
            : const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.video_library_rounded, size: 48, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'قم باستيراد فيديو للمعاينة',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              );

        if (hasColorGrading) {
          final colorMatrix = buildCombinedColorMatrix(clipColor, clipProColor);
          videoContent = ColorFiltered(
            colorFilter: ColorFilter.matrix(colorMatrix),
            child: videoContent,
          );
        }

        if (hasTransform) {
          final double scaleX = clipTransform.scale.x / 100.0;
          final double scaleY = clipTransform.scale.y / 100.0;
          final double rot = clipTransform.rotation * math.pi / 180.0;
          final Offset translate =
              Offset(clipTransform.position.x, clipTransform.position.y);

          videoContent = Transform(
            transform: Matrix4.identity()
              ..translate(translate.dx, translate.dy)
              ..rotateZ(rot)
              ..scale(scaleX, scaleY),
            alignment: Alignment.center,
            child: videoContent,
          );
        }

        final transitionProgress = _getTransitionProgress();
        if (transitionProgress > 0.0 && _currentClip != null) {
          final transitionType = _currentClip!.outTransition.type;
          videoContent = _applyTransition(videoContent, transitionType, transitionProgress);
        }

        if (_currentClip != null && _currentClip!.shaderEffects.isNotEmpty) {
          videoContent = _wrapWithShaderEffects(videoContent, _currentClip!.shaderEffects);
        }

        final activeTextClips = _getActiveTextClips(playhead);
        final hasText = activeTextClips.isNotEmpty;
        final hasParticles = _currentClip != null && _currentClip!.particleEffects.isNotEmpty;
        final hasShapes = _currentClip != null && _currentClip!.shapeOverlays.isNotEmpty;
        if (hasText || hasParticles || hasShapes) {
          final stackChildren = <Widget>[videoContent];
          stackChildren.addAll(activeTextClips.map((clip) => _buildTextOverlay(clip, playhead)));
          if (hasParticles) {
            stackChildren.addAll(_buildParticleOverlays(constraints, _currentClip!));
          }
          if (hasShapes) {
            stackChildren.add(_buildShapeOverlay(constraints, _currentClip!, playhead));
          }
          videoContent = Stack(fit: StackFit.expand, children: stackChildren);
        }

        // Webcam PiP overlay
        final isWebcamActive = ref.watch(isWebcamActiveProvider);
        if (isWebcamActive) {
          videoContent = Stack(
            fit: StackFit.expand,
            children: [
              videoContent,
              Positioned(
                right: 16,
                bottom: 60,
                child: _WebcamPipWidget(),
              ),
            ],
          );
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.black,
          ),
          child: Column(
            children: [
              Expanded(child: videoContent),
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 24,
                        color: AppColors.primary,
                      ),
                      onPressed: widget.videoPath != null ? _togglePlay : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(
                        _isMuted || _volume == 0
                            ? Icons.volume_mute_rounded
                            : _volume < 0.5
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: widget.videoPath != null ? _toggleMute : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    SizedBox(
                      width: 60,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2.0,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.0),
                        ),
                        child: Slider(
                          value: _volume,
                          onChanged: widget.videoPath != null ? _changeVolume : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(_player.state.position),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textSecondary),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                          ),
                          child: Slider(
                            value: playhead.clamp(0.0, maxDuration),
                            min: 0.0,
                            max: maxDuration,
                            onChanged: (val) {
                              _safeSeek((val * 1000).toInt());
                              ref.read(timelineProvider.notifier).setPlayhead(val);
                            },
                          ),
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(Duration(milliseconds: (maxDuration * 1000).toInt())),
                      style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ────────────────────────────────────────────────────────────
//  Webcam Picture-in-Picture Overlay
// ────────────────────────────────────────────────────────────

class _WebcamPipWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frameAsync = ref.watch(webcamFrameProvider);

    return Container(
      width: 200,
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: frameAsync.when(
        data: (frame) {
          if (frame == null) {
            return _pipPlaceholder();
          }
          return Image.memory(frame, fit: BoxFit.cover);
        },
        error: (_, __) => _pipPlaceholder(),
        loading: () => _pipPlaceholder(),
      ),
    );
  }

  Widget _pipPlaceholder() {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_rounded, size: 28, color: Colors.white38),
            SizedBox(height: 4),
            Text('كاميرا ويب', style: TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}
