import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class AudioWaveformPainter extends CustomPainter {
  final Color color;
  final String clipId;
  final double zoomLevel;
  final List<double>? waveformSamples;
  final bool isMuted;

  AudioWaveformPainter({
    required this.color,
    required this.clipId,
    required this.zoomLevel,
    this.waveformSamples,
    this.isMuted = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformSamples == null || waveformSamples!.isEmpty) {
      _drawPlaceholder(canvas, size);
      return;
    }

    final paint = Paint()
      ..color = isMuted ? color.withValues(alpha: 0.3) : color
      ..style = PaintingStyle.fill;

    final barWidth = math.max(1.0, size.width / waveformSamples!.length);
    final centerY = size.height / 2;

    for (int i = 0; i < waveformSamples!.length; i++) {
      final sample = waveformSamples![i];
      final barHeight = sample * size.height * 0.9;
      final x = i * barWidth;

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth - 0.5,
          height: math.max(1.0, barHeight),
        ),
        paint,
      );
    }
  }

  void _drawPlaceholder(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final centerY = size.height / 2;
    final barWidth = 2.0;
    final barSpacing = 2.0;
    final barCount = (size.width / (barWidth + barSpacing)).floor();

    final random = math.Random(42);
    for (int i = 0; i < barCount; i++) {
      final height = random.nextDouble() * size.height * 0.6 + 2;
      final x = i * (barWidth + barSpacing);

      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(x + barWidth / 2, centerY),
          width: barWidth,
          height: height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.clipId != clipId ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.isMuted != isMuted ||
        oldDelegate.waveformSamples != waveformSamples;
  }
}

class WaveformCache {
  static final WaveformCache _instance = WaveformCache._internal();
  factory WaveformCache() => _instance;
  WaveformCache._internal();

  final Map<String, List<double>> _cache = {};

  List<double>? get(String key) => _cache[key];

  void set(String key, List<double> samples) {
    _cache[key] = samples;
  }

  bool has(String key) => _cache.containsKey(key);

  void clear() => _cache.clear();
}

class WaveformGenerator {
  static Future<List<double>> generate(String audioPath, {int sampleCount = 200}) async {
    final cache = WaveformCache();
    final cacheKey = '${audioPath}_$sampleCount';

    if (cache.has(cacheKey)) {
      return cache.get(cacheKey)!;
    }

    try {
      final result = await Process.run(
        'ffprobe',
        [
          '-v', 'error',
          '-select_streams', 'a:0',
          '-show_entries', 'stream=duration',
          '-of', 'default=noprint_wrappers=1:nokey=1',
          audioPath,
        ],
      );

      if (result.exitCode != 0) {
        return _generateFallback(sampleCount);
      }

      final duration = double.tryParse((result.stdout as String).trim()) ?? 10.0;
      final samples = await _extractWaveformSamples(audioPath, duration, sampleCount);

      cache.set(cacheKey, samples);
      return samples;
    } catch (_) {
      return _generateFallback(sampleCount);
    }
  }

  static Future<List<double>> _extractWaveformSamples(
    String audioPath,
    double duration,
    int sampleCount,
  ) async {
    try {
      final result = await Process.run(
        'ffmpeg',
        [
          '-i', audioPath,
          '-ac', '1',
          '-ar', '8000',
          '-f', 'f32le',
          '-hide_banner',
          '-loglevel', 'error',
          'pipe:1',
        ],
        stdoutEncoding: null,
      );

      if (result.exitCode != 0 || result.stdout == null) {
        return _generateFallback(sampleCount);
      }

      final bytes = result.stdout as List<int>;
      if (bytes.length < 4) return _generateFallback(sampleCount);

      final samples = Float32List.view(
        Uint8List.fromList(bytes).buffer,
        0,
        bytes.length ~/ 4,
      );

      if (samples.isEmpty) return _generateFallback(sampleCount);

      final segmentSize = (samples.length / sampleCount).ceil();
      final waveform = <double>[];

      for (int i = 0; i < sampleCount; i++) {
        final segStart = i * segmentSize;
        final segEnd = (segStart + segmentSize).clamp(0, samples.length);

        double sumSq = 0;
        int count = 0;
        for (int j = segStart; j < segEnd; j++) {
          final s = samples[j];
          sumSq += s * s;
          count++;
        }
        final rms = count > 0 ? (sumSq / count) : 0.0;
        waveform.add(rms.clamp(0.0, 1.0));
      }

      return waveform;
    } catch (_) {
      return _generateFallback(sampleCount);
    }
  }

  static List<double> _generateFallback(int sampleCount) {
    final random = math.Random(42);
    return List.generate(
      sampleCount,
      (i) => random.nextDouble() * 0.8 + 0.1,
    );
  }
}

class AudioWaveformLoader extends StatefulWidget {
  final String audioPath;
  final Widget Function(List<double>? samples) builder;

  const AudioWaveformLoader({
    super.key,
    required this.audioPath,
    required this.builder,
  });

  @override
  State<AudioWaveformLoader> createState() => _AudioWaveformLoaderState();
}

class _AudioWaveformLoaderState extends State<AudioWaveformLoader> {
  List<double>? _samples;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant AudioWaveformLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioPath != oldWidget.audioPath) {
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    final cache = WaveformCache();
    final cacheKey = '${widget.audioPath}_150';
    
    if (cache.has(cacheKey)) {
      if (mounted) {
        setState(() => _samples = cache.get(cacheKey));
      }
      return;
    }

    final samples = await WaveformGenerator.generate(widget.audioPath, sampleCount: 150);
    if (mounted) {
      setState(() => _samples = samples);
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_samples);
  }
}
