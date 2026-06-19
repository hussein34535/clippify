import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/timeline_models.dart';
import '../../core/theme/app_theme.dart';
import '../timeline/providers/timeline_provider.dart';

class TrackedPoint {
  final double time;
  final double x;
  final double y;
  TrackedPoint({required this.time, required this.x, required this.y});

  factory TrackedPoint.fromJson(Map<String, dynamic> json) => TrackedPoint(
        time: (json['time'] as num).toDouble(),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
      );
}

class FaceTrackedRect {
  final double time;
  final double x;
  final double y;
  final double w;
  final double h;
  final double confidence;
  FaceTrackedRect({
    required this.time,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.confidence,
  });

  factory FaceTrackedRect.fromJson(Map<String, dynamic> json) =>
      FaceTrackedRect(
        time: (json['time'] as num).toDouble(),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

class PlanarTrackResult {
  final double time;
  final List<List<double>>? homography;
  final List<List<double>>? corners;
  PlanarTrackResult({
    required this.time,
    this.homography,
    this.corners,
  });

  factory PlanarTrackResult.fromJson(Map<String, dynamic> json) =>
      PlanarTrackResult(
        time: (json['time'] as num).toDouble(),
        homography: (json['homography'] as List<dynamic>?)
            ?.map((row) => (row as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList(),
        corners: (json['corners'] as List<dynamic>?)
            ?.map((pt) => (pt as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList(),
      );
}

class MotionTracker {
  double _progress = 0.0;
  double get progress => _progress;

  final String _pythonCmd;
  final String _scriptPath;

  MotionTracker({String? pythonCmd, String? scriptPath})
      : _pythonCmd = pythonCmd ?? 'python',
        _scriptPath = scriptPath ?? _findTrackerScript();

  static String _findTrackerScript() {
    final candidates = [
      'tracker.py',
      '../tracker.py',
      '../../tracker.py',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f.absolute.path;
    }
    return 'tracker.py';
  }

  Future<List<Keyframe>?> trackPoint(
    String videoPath,
    double x,
    double y, {
    int maxFrames = 0,
    void Function(double progress)? onProgress,
  }) async {
    _progress = 0.0;
    final args = [
      _scriptPath,
      'point',
      videoPath,
      x.toStringAsFixed(1),
      y.toStringAsFixed(1),
      if (maxFrames > 0) maxFrames.toString(),
    ];

    try {
      final result = await Process.run(_pythonCmd, args);
      if (result.exitCode != 0) {
        debugPrint('[MotionTracker] Error: ${result.stderr}');
        return null;
      }

      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        debugPrint('[MotionTracker] ${data['error']}');
        return null;
      }

      final kfs = (data['keyframes'] as List<dynamic>?) ?? [];
      final total = kfs.length;
      final keyframes = <Keyframe>[];
      for (int i = 0; i < total; i++) {
        final pt = kfs[i] as Map<String, dynamic>;
        final t = (pt['time'] as num).toDouble();
        keyframes.add(Keyframe(
          time: t,
          property: 'tracked_x',
          value: (pt['x'] as num).toDouble(),
          easing: 'linear',
        ));
        keyframes.add(Keyframe(
          time: t,
          property: 'tracked_y',
          value: (pt['y'] as num).toDouble(),
          easing: 'linear',
        ));
        _progress = (i + 1) / total;
        onProgress?.call(_progress);
      }
      return keyframes;
    } catch (e) {
      debugPrint('[MotionTracker] Exception: $e');
      return null;
    }
  }

  Future<List<Keyframe>?> trackFaces(
    String videoPath, {
    int maxFrames = 0,
    void Function(double progress)? onProgress,
  }) async {
    _progress = 0.0;
    final args = [
      _scriptPath,
      'faces',
      videoPath,
      if (maxFrames > 0) maxFrames.toString(),
    ];

    try {
      final result = await Process.run(_pythonCmd, args);
      if (result.exitCode != 0) {
        debugPrint('[FaceTracker] Error: ${result.stderr}');
        return null;
      }

      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        debugPrint('[FaceTracker] ${data['error']}');
        return null;
      }

      final kfs = (data['keyframes'] as List<dynamic>?) ?? [];
      final total = kfs.length;
      final keyframes = <Keyframe>[];
      for (int i = 0; i < total; i++) {
        final f = kfs[i] as Map<String, dynamic>;
        final cx = (f['x'] as num?)?.toDouble() ?? 0;
        final cy = (f['y'] as num?)?.toDouble() ?? 0;
        final fw = (f['w'] as num?)?.toDouble() ?? 0;
        final fh = (f['h'] as num?)?.toDouble() ?? 0;
        final faceCenterX = cx + fw / 2.0;
        final faceCenterY = cy + fh / 2.0;
        final t = (f['time'] as num).toDouble();

        keyframes.add(Keyframe(
          time: t,
          property: 'tracked_x',
          value: faceCenterX,
          easing: 'linear',
        ));
        keyframes.add(Keyframe(
          time: t,
          property: 'tracked_y',
          value: faceCenterY,
          easing: 'linear',
        ));
        _progress = (i + 1) / total;
        onProgress?.call(_progress);
      }
      return keyframes;
    } catch (e) {
      debugPrint('[FaceTracker] Exception: $e');
      return null;
    }
  }

  Future<List<Keyframe>?> trackPlanar(
    String videoPath,
    Rect region, {
    int maxFrames = 0,
    void Function(double progress)? onProgress,
  }) async {
    _progress = 0.0;
    final args = [
      _scriptPath,
      'planar',
      videoPath,
      region.left.toStringAsFixed(1),
      region.top.toStringAsFixed(1),
      region.width.toStringAsFixed(1),
      region.height.toStringAsFixed(1),
      if (maxFrames > 0) maxFrames.toString(),
    ];

    try {
      final result = await Process.run(_pythonCmd, args);
      if (result.exitCode != 0) {
        debugPrint('[PlanarTracker] Error: ${result.stderr}');
        return null;
      }

      final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      if (data.containsKey('error')) {
        debugPrint('[PlanarTracker] ${data['error']}');
        return null;
      }

      final kfs = (data['keyframes'] as List<dynamic>?) ?? [];
      final total = kfs.length;
      final keyframes = <Keyframe>[];
      for (int i = 0; i < total; i++) {
        final p = kfs[i] as Map<String, dynamic>;
        final corners = (p['corners'] as List<dynamic>?)
            ?.map((pt) => (pt as List<dynamic>)
                .map((v) => (v as num).toDouble())
                .toList())
            .toList();

        if (corners != null && corners.length == 4) {
          final cx = corners.map((c) => c[0]).reduce((a, b) => a + b) / 4;
          final cy = corners.map((c) => c[1]).reduce((a, b) => a + b) / 4;
          final t = (p['time'] as num).toDouble();
          keyframes.add(Keyframe(
            time: t,
            property: 'tracked_x',
            value: cx,
            easing: 'linear',
          ));
          keyframes.add(Keyframe(
            time: t,
            property: 'tracked_y',
            value: cy,
            easing: 'linear',
          ));
        }

        _progress = (i + 1) / total;
        onProgress?.call(_progress);
      }
      return keyframes;
    } catch (e) {
      debugPrint('[PlanarTracker] Exception: $e');
      return null;
    }
  }
}

class TrackingPanel extends ConsumerStatefulWidget {
  final VideoClip clip;

  const TrackingPanel({super.key, required this.clip});

  @override
  ConsumerState<TrackingPanel> createState() => _TrackingPanelState();
}

class _TrackingPanelState extends ConsumerState<TrackingPanel> {
  final MotionTracker _tracker = MotionTracker();
  bool _isTracking = false;
  double _trackProgress = 0.0;
  String _status = '';
  bool _pointMode = false;

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'تتبع الحركة',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),

        if (_isTracking)
          Column(
            children: [
              LinearProgressIndicator(
                value: _trackProgress > 0 ? _trackProgress : null,
                backgroundColor: AppColors.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          )
        else ...[
          _buildActionButton(
            icon: Icons.ads_click_rounded,
            label: 'تتبع نقطة',
            subtitle: 'اختر نقطة على الفيديو',
            color: AppColors.primary,
            onTap: _pointMode ? null : () => setState(() => _pointMode = true),
          ),
          const SizedBox(height: 8),
          _buildActionButton(
            icon: Icons.face_rounded,
            label: 'تتبع وجه',
            subtitle: 'كشف وتعقب الوجوه تلقائياً',
            color: const Color(0xFF30D158),
            onTap: () => _startFaceTracking(clip),
          ),
          const SizedBox(height: 8),
          _buildActionButton(
            icon: Icons.crop_square_rounded,
            label: 'تتبع سطح',
            subtitle: 'تتبع سطح مستوي (شاشة، لافتة)',
            color: const Color(0xFFFF9F0A),
            onTap: () => _startPlanarTracking(clip),
          ),
        ],

        if (_pointMode) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withAlpha(80)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.touch_app_rounded, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'انقر على الفيديو في المشغل لتحديد نقطة التتبع',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _pointMode = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
                    ),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Divider(color: AppColors.divider),

        SwitchListTile(
          title: const Text('تطبيق التتبع', style: TextStyle(fontSize: 12, color: Colors.white)),
          subtitle: const Text('تحريك الكليب حسب مسار التتبع', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          value: clip.useTracking,
          onChanged: (v) {
            ref.read(timelineProvider.notifier).updateVideoClip(clip.id, (c) => c.copyWith(
              useTracking: v,
            ));
          },
          activeTrackColor: AppColors.primary,
        ),

        if (clip.trackedPosition.isNotEmpty)
          SwitchListTile(
            title: const Text('تتبع مع الاقتصاص', style: TextStyle(fontSize: 12, color: Colors.white)),
            subtitle: const Text('إعادة تأطير تلقائي للفيديو', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            value: clip.trackingType == 'crop',
            onChanged: (v) {
              ref.read(timelineProvider.notifier).updateVideoClip(clip.id, (c) => c.copyWith(
                trackingType: v ? 'crop' : 'point',
              ));
            },
            activeTrackColor: AppColors.primary,
          ),

        if (clip.trackedPosition.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withAlpha(100),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.secondary),
                const SizedBox(width: 8),
                Text(
                  '${clip.trackedPosition.length} keyframes',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    ref.read(timelineProvider.notifier).updateVideoClip(clip.id, (c) => c.copyWith(
                      trackedPosition: const [],
                      useTracking: false,
                      trackingType: 'none',
                    ));
                  },
                  child: const Text('مسح', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),
        const Text(
          'ملاحظة: يتطلب التثبيت Python ومكتبة OpenCV',
          style: TextStyle(fontSize: 9, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 12, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  void _startFaceTracking(VideoClip clip) async {
    setState(() {
      _isTracking = true;
      _trackProgress = 0.0;
      _status = 'جاري تتبع الوجوه...';
    });

    final kfs = await _tracker.trackFaces(
      clip.sourcePath,
      onProgress: (p) {
        if (mounted) {
          setState(() => _trackProgress = p);
        }
      },
    );

    if (kfs != null && kfs.isNotEmpty && mounted) {
      ref.read(timelineProvider.notifier).updateVideoClip(clip.id, (c) => c.copyWith(
        trackedPosition: kfs,
        useTracking: true,
        trackingType: 'face',
      ));
      setState(() {
        _status = 'تم التتبع: ${kfs.length} keyframe';
        _isTracking = false;
      });
    } else if (mounted) {
      setState(() {
        _status = 'فشل تتبع الوجوه';
        _isTracking = false;
      });
    }
  }

  void _startPlanarTracking(VideoClip clip) async {
    setState(() {
      _isTracking = true;
      _trackProgress = 0.0;
      _status = 'جاري تتبع السطح...';
    });

    final region = const Rect.fromLTWH(100, 100, 200, 150);
    final kfs = await _tracker.trackPlanar(
      clip.sourcePath,
      region,
      onProgress: (p) {
        if (mounted) setState(() => _trackProgress = p);
      },
    );

    if (kfs != null && kfs.isNotEmpty && mounted) {
      ref.read(timelineProvider.notifier).updateVideoClip(clip.id, (c) => c.copyWith(
        trackedPosition: kfs,
        useTracking: true,
        trackingType: 'planar',
      ));
      setState(() {
        _status = 'تم التتبع: ${kfs.length} keyframe';
        _isTracking = false;
      });
    } else if (mounted) {
      setState(() {
        _status = 'فشل تتبع السطح';
        _isTracking = false;
      });
    }
  }
}
