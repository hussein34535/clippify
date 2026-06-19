import 'dart:io';
import 'dart:async';

enum CodecType { h264, h265, prores, av1, vp9 }

class CodecConfig {
  final CodecType type;
  final String label;
  final String extension;
  final String ffmpegCodec;
  final int bitrate;
  final String quality;

  const CodecConfig({
    required this.type,
    required this.label,
    required this.extension,
    required this.ffmpegCodec,
    this.bitrate = 8000,
    this.quality = 'high',
  });

  static const List<CodecConfig> available = [
    CodecConfig(type: CodecType.h264, label: 'H.264', extension: 'mp4', ffmpegCodec: 'libx264', bitrate: 8000),
    CodecConfig(type: CodecType.h265, label: 'H.265 HEVC', extension: 'mp4', ffmpegCodec: 'libx265', bitrate: 4000),
    CodecConfig(type: CodecType.prores, label: 'Apple ProRes', extension: 'mov', ffmpegCodec: 'prores_ks', bitrate: 45000),
    CodecConfig(type: CodecType.av1, label: 'AV1', extension: 'mp4', ffmpegCodec: 'libaom-av1', bitrate: 3000),
    CodecConfig(type: CodecType.vp9, label: 'VP9', extension: 'webm', ffmpegCodec: 'libvpx-vp9', bitrate: 4000),
  ];
}

class BatchExportJob {
  final String id;
  final String name;
  final String inputPath;
  String? outputPath;
  final CodecConfig codec;
  final int width;
  final int height;
  final int fps;
  double progress;
  String status;

  BatchExportJob({
    required this.id,
    required this.name,
    required this.inputPath,
    required this.codec,
    this.width = 1920,
    this.height = 1080,
    this.fps = 30,
    this.progress = 0,
    this.status = 'pending',
    this.outputPath,
  });
}

class BatchExporter {
  final List<BatchExportJob> _queue = [];
  bool _isRunning = false;
  final StreamController<BatchExportJob> _onProgress = StreamController.broadcast();

  Stream<BatchExportJob> get onProgress => _onProgress.stream;
  List<BatchExportJob> get queue => List.unmodifiable(_queue);
  bool get isRunning => _isRunning;

  void addJob(BatchExportJob job) {
    _queue.add(job);
    if (!_isRunning) _processNext();
  }

  void addJobs(List<BatchExportJob> jobs) {
    _queue.addAll(jobs);
    if (!_isRunning) _processNext();
  }

  void removeJob(String id) => _queue.removeWhere((j) => j.id == id);

  void clear() => _queue.clear();

  Future<void> _processNext() async {
    if (_queue.isEmpty) {
      _isRunning = false;
      return;
    }
    _isRunning = true;
    final job = _queue.first;
    job.status = 'exporting';

    try {
      final result = await Process.run('ffmpeg', [
        '-i', job.inputPath,
        '-c:v', job.codec.ffmpegCodec,
        '-b:v', '${job.codec.bitrate}k',
        '-vf', 'scale=${job.width}:${job.height}',
        '-r', job.fps.toString(),
        '-y', job.outputPath ?? 'output.${job.codec.extension}',
      ]);

      if (result.exitCode == 0) {
        job.progress = 1.0;
        job.status = 'completed';
      } else {
        job.status = 'failed';
      }
    } catch (e) {
      job.status = 'failed';
    }

    _onProgress.add(job);
    _queue.removeAt(0);
    _processNext();
  }

  void dispose() {
    _onProgress.close();
    _queue.clear();
  }
}

class HDRConfig {
  final bool enabled;
  final double peakLuminance;
  final double paperWhite;
  final String colorPrimaries;
  final String transferCharacteristics;
  final String masteringDisplay;

  const HDRConfig({
    this.enabled = false,
    this.peakLuminance = 1000,
    this.paperWhite = 203,
    this.colorPrimaries = 'bt2020',
    this.transferCharacteristics = 'smpte2084',
    this.masteringDisplay = 'G(0.265,0.690)B(0.150,0.060)R(0.680,0.320)WP(0.3127,0.3290)L(1000,0.0050)',
  });

  List<String> toFfmpegArgs() => enabled ? [
    '-color_primaries', colorPrimaries,
    '-color_trc', transferCharacteristics,
    '-colorspace', 'bt2020nc',
    '-pix_fmt', 'yuv420p10le',
    '-x265-params', 'hdr-opt=1:master-display=$masteringDisplay:max-cll=${peakLuminance.round()},400',
  ] : [];
}
