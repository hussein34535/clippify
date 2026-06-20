import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../data/export_presets.dart';

// ─────────────────────────────────────────────
// HardwareEncoderDetector
// ─────────────────────────────────────────────
class HardwareEncoderDetector {
  static bool? _cachedNvenc;
  static bool? _cachedAmf;
  static bool? _cachedQsv;
  static bool? _cachedVideotoolbox;

  static Future<bool> get hasNvenc async {
    if (_cachedNvenc != null) return _cachedNvenc!;
    _cachedNvenc = await _detect('nvenc');
    return _cachedNvenc!;
  }

  static Future<bool> get hasAmf async {
    if (_cachedAmf != null) return _cachedAmf!;
    _cachedAmf = await _detect('amf');
    return _cachedAmf!;
  }

  static Future<bool> get hasQsv async {
    if (_cachedQsv != null) return _cachedQsv!;
    _cachedQsv = await _detect('qsv');
    return _cachedQsv!;
  }

  static Future<bool> get hasVideotoolbox async {
    if (_cachedVideotoolbox != null) return _cachedVideotoolbox!;
    _cachedVideotoolbox = await _detect('videotoolbox');
    return _cachedVideotoolbox!;
  }

  static Future<bool> _detect(String name) async {
    try {
      final result = await Process.run('ffmpeg', ['-encoders'],
          runInShell: true, stderrEncoding: utf8, stdoutEncoding: utf8);
      final output = (result.stdout as String).toLowerCase();
      return output.contains(name);
    } catch (e) {
      debugPrint('[HardwareEncoderDetector] ffmpeg error: $e');
      return false;
    }
  }

  static Future<List<EncoderConfig>> detectAll() async {
    final results = await Future.wait([
      hasNvenc,
      hasAmf,
      hasQsv,
      hasVideotoolbox,
    ]);
    final list = <EncoderConfig>[];
    if (results[0]) list.addAll(EncoderConfig.nvencVariants);
    if (results[1]) list.addAll(EncoderConfig.amfVariants);
    if (results[2]) list.addAll(EncoderConfig.qsvVariants);
    if (results[3]) list.addAll(EncoderConfig.videotoolboxVariants);
    return list;
  }

  static void invalidateCache() {
    _cachedNvenc = null;
    _cachedAmf = null;
    _cachedQsv = null;
    _cachedVideotoolbox = null;
  }
}

// ─────────────────────────────────────────────
// EncoderConfig
// ─────────────────────────────────────────────
class EncoderConfig {
  final String name;
  final String ffmpegCodec;
  final String pixelFormat;
  final int bitrateMbps;
  final String preset;
  final List<String> availablePixelFormats;
  final bool isHardware;
  final String type; // 'nvenc', 'amf', 'qsv', 'videotoolbox', 'software'

  const EncoderConfig({
    required this.name,
    required this.ffmpegCodec,
    this.pixelFormat = 'yuv420p',
    this.bitrateMbps = 8,
    this.preset = 'medium',
    this.availablePixelFormats = const ['yuv420p'],
    this.isHardware = false,
    this.type = 'software',
  });

  static const List<EncoderConfig> softwareVariants = [
    EncoderConfig(
      name: 'H.264 (Software)',
      ffmpegCodec: 'libx264',
      pixelFormat: 'yuv420p',
      bitrateMbps: 8,
      preset: 'medium',
      availablePixelFormats: ['yuv420p', 'yuv422p', 'yuv444p'],
      isHardware: false,
      type: 'software',
    ),
    EncoderConfig(
      name: 'H.265 HEVC (Software)',
      ffmpegCodec: 'libx265',
      pixelFormat: 'yuv420p',
      bitrateMbps: 4,
      preset: 'medium',
      availablePixelFormats: ['yuv420p', 'yuv420p10le', 'yuv422p', 'yuv444p'],
      isHardware: false,
      type: 'software',
    ),
    EncoderConfig(
      name: 'AV1 (Software)',
      ffmpegCodec: 'libaom-av1',
      pixelFormat: 'yuv420p',
      bitrateMbps: 3,
      preset: '2',
      availablePixelFormats: ['yuv420p'],
      isHardware: false,
      type: 'software',
    ),
    EncoderConfig(
      name: 'VP9 (Software)',
      ffmpegCodec: 'libvpx-vp9',
      pixelFormat: 'yuv420p',
      bitrateMbps: 4,
      preset: '0',
      availablePixelFormats: ['yuv420p'],
      isHardware: false,
      type: 'software',
    ),
    EncoderConfig(
      name: 'Apple ProRes',
      ffmpegCodec: 'prores_ks',
      pixelFormat: 'yuv422p10le',
      bitrateMbps: 45,
      preset: 'standard',
      availablePixelFormats: ['yuv422p10le', 'yuv444p10le'],
      isHardware: false,
      type: 'software',
    ),
  ];

  static const List<EncoderConfig> nvencVariants = [
    EncoderConfig(
      name: 'H.264 NVENC',
      ffmpegCodec: 'h264_nvenc',
      pixelFormat: 'yuv420p',
      bitrateMbps: 8,
      preset: 'p4',
      availablePixelFormats: ['yuv420p', 'p010le'],
      isHardware: true,
      type: 'nvenc',
    ),
    EncoderConfig(
      name: 'H.265 NVENC',
      ffmpegCodec: 'hevc_nvenc',
      pixelFormat: 'yuv420p',
      bitrateMbps: 4,
      preset: 'p4',
      availablePixelFormats: ['yuv420p', 'p010le'],
      isHardware: true,
      type: 'nvenc',
    ),
    EncoderConfig(
      name: 'AV1 NVENC',
      ffmpegCodec: 'av1_nvenc',
      pixelFormat: 'yuv420p',
      bitrateMbps: 3,
      preset: 'p4',
      availablePixelFormats: ['yuv420p', 'p010le'],
      isHardware: true,
      type: 'nvenc',
    ),
  ];

  static const List<EncoderConfig> amfVariants = [
    EncoderConfig(
      name: 'H.264 AMF',
      ffmpegCodec: 'h264_amf',
      pixelFormat: 'yuv420p',
      bitrateMbps: 8,
      preset: 'balanced',
      availablePixelFormats: ['yuv420p'],
      isHardware: true,
      type: 'amf',
    ),
    EncoderConfig(
      name: 'H.265 AMF',
      ffmpegCodec: 'hevc_amf',
      pixelFormat: 'yuv420p',
      bitrateMbps: 4,
      preset: 'balanced',
      availablePixelFormats: ['yuv420p'],
      isHardware: true,
      type: 'amf',
    ),
  ];

  static const List<EncoderConfig> qsvVariants = [
    EncoderConfig(
      name: 'H.264 QSV',
      ffmpegCodec: 'h264_qsv',
      pixelFormat: 'nv12',
      bitrateMbps: 8,
      preset: 'medium',
      availablePixelFormats: ['nv12', 'p010'],
      isHardware: true,
      type: 'qsv',
    ),
    EncoderConfig(
      name: 'H.265 QSV',
      ffmpegCodec: 'hevc_qsv',
      pixelFormat: 'nv12',
      bitrateMbps: 4,
      preset: 'medium',
      availablePixelFormats: ['nv12', 'p010'],
      isHardware: true,
      type: 'qsv',
    ),
  ];

  static const List<EncoderConfig> videotoolboxVariants = [
    EncoderConfig(
      name: 'H.264 VideoToolbox',
      ffmpegCodec: 'h264_videotoolbox',
      pixelFormat: 'nv12',
      bitrateMbps: 8,
      preset: 'medium',
      availablePixelFormats: ['nv12'],
      isHardware: true,
      type: 'videotoolbox',
    ),
    EncoderConfig(
      name: 'H.265 VideoToolbox',
      ffmpegCodec: 'hevc_videotoolbox',
      pixelFormat: 'nv12',
      bitrateMbps: 4,
      preset: 'medium',
      availablePixelFormats: ['nv12'],
      isHardware: true,
      type: 'videotoolbox',
    ),
  ];

  Map<String, dynamic> toJson() => {
    'name': name,
    'ffmpeg_codec': ffmpegCodec,
    'pixel_format': pixelFormat,
    'bitrate_mbps': bitrateMbps,
    'preset': preset,
    'is_hardware': isHardware,
    'type': type,
  };
}

// ─────────────────────────────────────────────
// FormatConfig
// ─────────────────────────────────────────────
class FormatConfig {
  final String name;
  final String extension;
  final String ffmpegFormat;
  final List<String> compatibleCodecs;
  final bool supportsAlpha;
  final bool supportsHdr;

  const FormatConfig({
    required this.name,
    required this.extension,
    required this.ffmpegFormat,
    this.compatibleCodecs = const ['h264', 'h265', 'av1'],
    this.supportsAlpha = false,
    this.supportsHdr = false,
  });

  static const List<FormatConfig> available = [
    FormatConfig(
      name: 'MP4',
      extension: '.mp4',
      ffmpegFormat: 'mp4',
      compatibleCodecs: ['h264', 'h265', 'av1'],
      supportsAlpha: false,
      supportsHdr: true,
    ),
    FormatConfig(
      name: 'MOV',
      extension: '.mov',
      ffmpegFormat: 'mov',
      compatibleCodecs: ['h264', 'h265', 'prores'],
      supportsAlpha: true,
      supportsHdr: true,
    ),
    FormatConfig(
      name: 'MKV',
      extension: '.mkv',
      ffmpegFormat: 'matroska',
      compatibleCodecs: ['h264', 'h265', 'av1', 'vp9'],
      supportsAlpha: false,
      supportsHdr: true,
    ),
    FormatConfig(
      name: 'AVI',
      extension: '.avi',
      ffmpegFormat: 'avi',
      compatibleCodecs: ['h264'],
      supportsAlpha: false,
      supportsHdr: false,
    ),
    FormatConfig(
      name: 'WebM',
      extension: '.webm',
      ffmpegFormat: 'webm',
      compatibleCodecs: ['vp9', 'av1'],
      supportsAlpha: false,
      supportsHdr: false,
    ),
    FormatConfig(
      name: 'GIF',
      extension: '.gif',
      ffmpegFormat: 'gif',
      compatibleCodecs: [],
      supportsAlpha: false,
      supportsHdr: false,
    ),
  ];

  Map<String, dynamic> toJson() => {
    'name': name,
    'extension': extension,
    'ffmpeg_format': ffmpegFormat,
    'supports_alpha': supportsAlpha,
    'supports_hdr': supportsHdr,
  };
}

// ─────────────────────────────────────────────
// ExportPresetPro (extends ExportPreset)
// ─────────────────────────────────────────────
class ExportPresetPro extends ExportPreset {
  final EncoderConfig encoder;
  final FormatConfig container;
  final int maxBitrateMbps;
  final bool twoPass;
  final bool includeMetadata;
  final String? watermarkPath;
  final String? watermarkPosition;
  final List<String> outputChannels;

  const ExportPresetPro({
    required super.name,
    required super.description,
    required super.iconName,
    required super.width,
    required super.height,
    required super.fps,
    required super.aspectRatio,
    super.quality,
    super.format,
    required this.encoder,
    required this.container,
    this.maxBitrateMbps = 50,
    this.twoPass = false,
    this.includeMetadata = true,
    this.watermarkPath,
    this.watermarkPosition,
    this.outputChannels = const ['video', 'audio'],
  });

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'encoder': encoder.toJson(),
    'container': container.toJson(),
    'max_bitrate_mbps': maxBitrateMbps,
    'two_pass': twoPass,
    'include_metadata': includeMetadata,
    'watermark_path': watermarkPath,
    'watermark_position': watermarkPosition,
    'output_channels': outputChannels,
  };
}

// ─────────────────────────────────────────────
// ExportJob
// ─────────────────────────────────────────────
class ExportJob {
  final String id;
  String status; // queued, processing, done, failed, cancelled
  double progress;
  final ExportPresetPro preset;
  String? outputPath;
  String? error;
  DateTime? startedAt;
  DateTime? completedAt;
  final int totalDurationSec;

  ExportJob({
    required this.id,
    this.status = 'queued',
    this.progress = 0.0,
    required this.preset,
    this.outputPath,
    this.error,
    this.startedAt,
    this.completedAt,
    this.totalDurationSec = 60,
  });

  Duration? get duration {
    if (startedAt == null) return null;
    final end = completedAt ?? DateTime.now();
    return end.difference(startedAt!);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status,
    'progress': progress,
    'preset': preset.toJson(),
    'output_path': outputPath,
    'error': error,
  };
}

// ─────────────────────────────────────────────
// BatchProcessor
// ─────────────────────────────────────────────
class BatchProcessor {
  final List<ExportJob> _jobs = [];
  bool _isProcessing = false;
  bool _cancelled = false;

  final StreamController<ExportJob> _onJobProgress = StreamController<ExportJob>.broadcast();
  final StreamController<double> _onOverallProgress = StreamController<double>.broadcast();
  final StreamController<String> _onJobComplete = StreamController<String>.broadcast();
  final StreamController<String> _onError = StreamController<String>.broadcast();

  Stream<ExportJob> get onJobProgress => _onJobProgress.stream;
  Stream<double> get onOverallProgress => _onOverallProgress.stream;
  Stream<String> get onJobComplete => _onJobComplete.stream;
  Stream<String> get onError => _onError.stream;

  List<ExportJob> get jobs => List.unmodifiable(_jobs);
  bool get isProcessing => _isProcessing;

  double get overallProgress {
    if (_jobs.isEmpty) return 0.0;
    double total = 0;
    for (final job in _jobs) {
      total += job.progress;
    }
    return total / _jobs.length;
  }

  void addToQueue(ExportPresetPro preset, {int totalDurationSec = 60}) {
    final job = ExportJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}_${_jobs.length}',
      preset: preset,
      totalDurationSec: totalDurationSec,
    );
    _jobs.add(job);
  }

  void removeJob(String id) {
    _jobs.removeWhere((j) => j.id == id);
  }

  void moveJob(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _jobs.length) return;
    if (newIndex < 0 || newIndex >= _jobs.length) return;
    final job = _jobs.removeAt(oldIndex);
    _jobs.insert(newIndex, job);
  }

  void clearQueue() {
    _jobs.removeWhere((j) => j.status == 'queued');
  }

  Future<void> processQueue() async {
    if (_isProcessing) return;
    if (_jobs.isEmpty) return;
    _isProcessing = true;
    _cancelled = false;

    for (final job in _jobs) {
      if (_cancelled) {
        job.status = 'cancelled';
        _onJobProgress.add(job);
        break;
      }
      if (job.status != 'queued') continue;

      job.status = 'processing';
      job.startedAt = DateTime.now();
      job.progress = 0.0;
      _onJobProgress.add(job);

      try {
        await _processJob(job);
        if (!_cancelled) {
          job.status = 'done';
          job.progress = 1.0;
          job.completedAt = DateTime.now();
          _onJobProgress.add(job);
          _onJobComplete.add(job.id);
        } else {
          job.status = 'cancelled';
          _onJobProgress.add(job);
        }
      } catch (e) {
        job.status = 'failed';
        job.error = e.toString();
        job.completedAt = DateTime.now();
        _onJobProgress.add(job);
        _onError.add('${job.preset.name}: ${e.toString()}');
      }

      _onOverallProgress.add(overallProgress);
    }

    _isProcessing = false;
    _onOverallProgress.add(overallProgress);
  }

  Future<void> _processJob(ExportJob job) async {
    final p = job.preset;
    final encoder = p.encoder;
    final container = p.container;

    final outputExt = container.extension;
    final outputName = p.name.toLowerCase().replaceAll(' ', '_');
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    job.outputPath = '${outputName}_$timestamp$outputExt';

    final baseArgs = <String>['-y'];

    if (p.watermarkPath != null && p.watermarkPosition != null) {
      final posMap = <String, String>{
        'top-left': '10:10',
        'top-right': 'W-w-10:10',
        'bottom-left': '10:H-h-10',
        'bottom-right': 'W-w-10:H-h-10',
        'center': '(W-w)/2:(H-h)/2',
      };
      final overlayPos = posMap[p.watermarkPosition] ?? 'W-w-10:10';
      baseArgs.addAll([
        '-i', p.watermarkPath!,
        '-filter_complex', '[0:v][1:v]overlay=$overlayPos',
      ]);
    }

    final codecArgs = <String>[
      '-c:v', encoder.ffmpegCodec,
      '-pix_fmt', encoder.pixelFormat,
      '-b:v', '${encoder.bitrateMbps}M',
      '-maxrate', '${p.maxBitrateMbps}M',
      '-bufsize', '${p.maxBitrateMbps * 2}M',
      '-r', p.fps.toString(),
      '-preset', encoder.preset,
    ];

    final nullOutput = Platform.isWindows ? 'NUL' : '/dev/null';

    if (p.twoPass) {
      final pass1 = [...baseArgs, ...codecArgs,
        '-pass', '1',
        '-f', container.ffmpegFormat,
        '-y', nullOutput,
      ];
      final r1 = await Process.run('ffmpeg', pass1,
          runInShell: true, stderrEncoding: utf8, stdoutEncoding: utf8);
      if (r1.exitCode != 0) {
        throw Exception('Two-pass (first pass) failed with exit ${r1.exitCode}');
      }
    }

    final passArgs = p.twoPass
        ? ['-pass', '2']
        : <String>[];

    final args = [...baseArgs, ...codecArgs, ...passArgs,
      '-f', container.ffmpegFormat,
      job.outputPath!,
    ];

    final process = await Process.start('ffmpeg', args,
        runInShell: true);

    final lines = <String>[];
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      lines.add(line);
      final progress = _parseFfmpegProgress(line, totalSec: job.totalDurationSec.toDouble());
      if (progress != null) {
        job.progress = progress;
        _onJobProgress.add(job);
        _onOverallProgress.add(overallProgress);
      }
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      final errorText = lines.isNotEmpty ? lines.last : 'Unknown error';
      throw Exception('FFmpeg exit code $exitCode: $errorText');
    }
  }

  double? _parseFfmpegProgress(String line, {double totalSec = 60.0}) {
    final regex = RegExp(r'time=(\d+):(\d+):(\d+)\.(\d+)');
    final match = regex.firstMatch(line);
    if (match == null) return null;
    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    final current = hours * 3600 + minutes * 60 + seconds.toDouble();
    return (current / totalSec).clamp(0.0, 1.0);
  }

  void cancel() {
    _cancelled = true;
    for (final job in _jobs) {
      if (job.status == 'queued') {
        job.status = 'cancelled';
      }
    }
  }

  void dispose() {
    cancel();
    _onJobProgress.close();
    _onOverallProgress.close();
    _onJobComplete.close();
    _onError.close();
  }
}

// ─────────────────────────────────────────────
// ExportPipelinePanel
// ─────────────────────────────────────────────
class ExportPipelinePanel extends StatefulWidget {
  final ExportPreset? initialPreset;
  final ValueChanged<ExportPresetPro>? onEnqueue;
  final VoidCallback? onStartBatch;

  const ExportPipelinePanel({
    super.key,
    this.initialPreset,
    this.onEnqueue,
    this.onStartBatch,
  });

  @override
  State<ExportPipelinePanel> createState() => _ExportPipelinePanelState();
}

class _ExportPipelinePanelState extends State<ExportPipelinePanel> {
  final BatchProcessor _batchProcessor = BatchProcessor();
  List<EncoderConfig> _availableEncoders = [];
  List<FormatConfig> _availableFormats = FormatConfig.available;
  EncoderConfig? _selectedEncoder;
  FormatConfig? _selectedFormat;
  ExportPreset? _selectedPreset;
  int _bitrateMbps = 8;
  int _maxBitrateMbps = 50;
  int _estimatedDurationSec = 60;
  bool _twoPass = false;
  bool _includeMetadata = true;
  String? _watermarkPath;
  String _watermarkPosition = 'bottom-right';
  // ignore: unused_field
  String _pixelFormat = '';
  bool _isDetecting = true;
  bool _isExporting = false;
  final Set<String> _completedJobs = {};
  late final TextEditingController _durationController;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(text: '$_estimatedDurationSec');
    _initDetectors();
    _selectedPreset = widget.initialPreset ?? ExportPreset.available[0];
    _selectedFormat = _availableFormats[0];

    _batchProcessor.onJobProgress.listen(_onJobProgress);
    _batchProcessor.onOverallProgress.listen((_) {
      if (mounted) setState(() {});
    });
    _batchProcessor.onJobComplete.listen((id) {
      if (mounted) {
        setState(() {
          _completedJobs.add(id);
        });
      }
    });
    _batchProcessor.onError.listen((error) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _initDetectors() async {
    try {
      final hwEncoders = await HardwareEncoderDetector.detectAll();
      if (mounted) {
        setState(() {
          _availableEncoders = [...hwEncoders, ...EncoderConfig.softwareVariants];
          _selectedEncoder = _availableEncoders.isNotEmpty ? _availableEncoders[0] : EncoderConfig.softwareVariants[0];
          _isDetecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availableEncoders = [...EncoderConfig.softwareVariants];
          _selectedEncoder = EncoderConfig.softwareVariants[0];
          _isDetecting = false;
        });
      }
    }
  }

  void _onJobProgress(ExportJob job) {
    if (mounted) {
      setState(() {
        _isExporting = _batchProcessor.isProcessing;
      });
    }
  }

  @override
  void dispose() {
    _durationController.dispose();
    _batchProcessor.dispose();
    super.dispose();
  }

  double get _estimatedFileSizeMB {
    final videoSize = _bitrateMbps * _estimatedDurationSec / 8;
    final audioSize = 0.192 * _estimatedDurationSec / 8;
    return videoSize + audioSize;
  }

  String get _estimatedEta {
    const encodeSpeedMbps = 50;
    final seconds = (_bitrateMbps * _estimatedDurationSec) / encodeSpeedMbps;
    final mins = (seconds / 60).ceil();
    if (mins < 1) return '<1 min';
    return '~$mins min';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEncoderSection(),
                const SizedBox(height: 12),
                _buildFormatSection(),
                const SizedBox(height: 12),
                _buildPresetSection(),
                const SizedBox(height: 12),
                _buildBitrateSection(),
                const SizedBox(height: 12),
                _buildAdvancedOptions(),
                const SizedBox(height: 12),
                _buildEstimates(),
                const SizedBox(height: 12),
                if (_batchProcessor.jobs.isNotEmpty) _buildQueue(),
              ],
            ),
          ),
        ),
        _buildBottomActions(),
        if (_batchProcessor.isProcessing || _batchProcessor.jobs.any((j) => j.status == 'done' || j.status == 'failed'))
          _buildProgressBar(),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _buildChipSelector<T>({
    required List<T> items,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
    IconData? Function(T)? icon,
    double height = 32,
  }) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item == selected;
          return GestureDetector(
            onTap: () => onSelected(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon(item), size: 12, color: isSelected ? AppColors.primary : AppColors.textMuted),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    label(item),
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Encoder Selection ──
  Widget _buildEncoderSection() {
    if (_isDetecting) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
            SizedBox(width: 8),
            Text('فحص المعالج (Detecting encoders...)', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('المشفّر (Encoder)'),
        const SizedBox(height: 6),
        _buildChipSelector(
          items: _availableEncoders,
          selected: _selectedEncoder,
          label: (e) => e.name,
          icon: (e) => e.isHardware ? Icons.memory : Icons.code,
          onSelected: (enc) {
            setState(() {
              _selectedEncoder = enc;
              _pixelFormat = enc.pixelFormat;
              _bitrateMbps = enc.bitrateMbps;
            });
          },
        ),
      ],
    );
  }

  // ── Format Selection ──
  Widget _buildFormatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('الحاوية (Container)'),
        const SizedBox(height: 6),
        _buildChipSelector(
          items: _availableFormats,
          selected: _selectedFormat,
          label: (f) => f.name,
          icon: (f) {
            if (f.name == 'GIF') return Icons.gif;
            if (f.extension == '.mov') return Icons.movie;
            return Icons.videocam;
          },
          onSelected: (fmt) {
            setState(() => _selectedFormat = fmt);
          },
        ),
        if (_selectedFormat != null && (_selectedFormat!.supportsAlpha || _selectedFormat!.supportsHdr))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (_selectedFormat!.supportsAlpha)
                  _buildFeatureChip('Alpha', AppColors.secondary),
                if (_selectedFormat!.supportsAlpha && _selectedFormat!.supportsHdr)
                  const SizedBox(width: 6),
                if (_selectedFormat!.supportsHdr)
                  _buildFeatureChip('HDR', AppColors.warning),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFeatureChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w600)),
    );
  }

  // ── Preset Section ──
  Widget _buildPresetSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('إعدادات جاهزة (Presets)'),
        const SizedBox(height: 6),
        _buildChipSelector(
          items: ExportPreset.available,
          selected: _selectedPreset,
          label: (p) => p.name,
          icon: (_) => Icons.movie_outlined,
          onSelected: (preset) {
            setState(() => _selectedPreset = preset);
          },
        ),
      ],
    );
  }

  // ── Bitrate Section ──
  Widget _buildBitrateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'معدل البت (Bitrate)',
          trailing: Text('${_bitrateMbps} Mbps', style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text('1', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            Expanded(
              child: Slider(
                value: _bitrateMbps.toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.surfaceVariant,
                onChanged: (v) => setState(() => _bitrateMbps = v.round()),
              ),
            ),
            const Text('100', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ],
        ),
        Row(
          children: [
            const Text('مدة الفيديو (ثوانٍ):', style: TextStyle(fontSize: 9, color: AppColors.textMuted)),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              height: 28,
              child: TextField(
                controller: _durationController,
                style: const TextStyle(fontSize: 10, color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed != null && parsed > 0) {
                    setState(() => _estimatedDurationSec = parsed);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Advanced Options ──
  Widget _buildAdvancedOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('خيارات متقدمة (Advanced)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            children: [
              _buildSwitchOption('Two-pass encoding', 'جودة أفضل مع تحليل ثنائي', _twoPass, (v) => setState(() => _twoPass = v)),
              const SizedBox(height: 6),
              _buildSwitchOption('Include metadata', 'الحفاظ على بيانات الميتا', _includeMetadata, (v) => setState(() => _includeMetadata = v)),
              const SizedBox(height: 6),
              _buildWatermarkOption(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchOption(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 10, color: Colors.white)),
              Text(subtitle, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          activeTrackColor: AppColors.primary,
          activeThumbColor: Colors.white,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildWatermarkOption() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Watermark overlay', style: TextStyle(fontSize: 10, color: Colors.white)),
              Text(
                _watermarkPath != null ? _watermarkPath!.split('\\').last.split('/').last : 'إضافة علامة مائية',
                style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (_watermarkPath != null) ...[
          SizedBox(
            height: 28,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _watermarkPosition,
                  dropdownColor: AppColors.card,
                  isDense: true,
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 'top-left', child: Text('TL', style: TextStyle(fontSize: 9))),
                    DropdownMenuItem(value: 'top-right', child: Text('TR', style: TextStyle(fontSize: 9))),
                    DropdownMenuItem(value: 'bottom-left', child: Text('BL', style: TextStyle(fontSize: 9))),
                    DropdownMenuItem(value: 'bottom-right', child: Text('BR', style: TextStyle(fontSize: 9))),
                    DropdownMenuItem(value: 'center', child: Text('C', style: TextStyle(fontSize: 9))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _watermarkPosition = v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _watermarkPath = null),
            child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
          ),
          const SizedBox(width: 6),
        ],
        GestureDetector(
          onTap: _pickWatermarkFile,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _watermarkPath != null ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _watermarkPath != null ? AppColors.primary : AppColors.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, size: 12, color: _watermarkPath != null ? AppColors.primary : AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(_watermarkPath != null ? 'تغيير' : 'رفع', style: TextStyle(fontSize: 9, color: _watermarkPath != null ? AppColors.primary : AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickWatermarkFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.single.path;
      if (path != null && mounted) {
        setState(() => _watermarkPath = path);
      }
    }
  }

  // ── Estimates ──
  Widget _buildEstimates() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          _buildEstimateItem(Icons.storage, '${_estimatedFileSizeMB.toStringAsFixed(1)} MB', 'Estimated Size'),
          const SizedBox(width: 24),
          _buildEstimateItem(Icons.timer_outlined, _estimatedEta, 'Estimated Time'),
          const SizedBox(width: 24),
          _buildEstimateItem(
            Icons.videocam,
            _selectedPreset != null ? '${_selectedPreset!.width}x${_selectedPreset!.height}' : '1920x1080',
            'Resolution',
          ),
        ],
      ),
    );
  }

  Widget _buildEstimateItem(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
            Text(label, style: const TextStyle(fontSize: 8, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }

  // ── Queue ──
  Widget _buildQueue() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'قائمة الانتظار (Queue)',
          trailing: Text('${_batchProcessor.jobs.length} jobs', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 120),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: _batchProcessor.jobs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: Text('قائمة الانتظار فارغة', style: TextStyle(fontSize: 10, color: AppColors.textMuted))),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const ClampingScrollPhysics(),
                  itemCount: _batchProcessor.jobs.length,
                  onReorder: (oldI, newI) {
                    setState(() => _batchProcessor.moveJob(oldI, newI));
                  },
                  itemBuilder: (context, index) {
                    final job = _batchProcessor.jobs[index];
                    return _buildQueueItem(job, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildQueueItem(ExportJob job, int index) {
    Color statusColor;
    String statusText;
    IconData statusIcon;
    switch (job.status) {
      case 'processing':
        statusColor = AppColors.primary;
        statusText = 'Processing';
        statusIcon = Icons.sync;
        break;
      case 'done':
        statusColor = AppColors.secondary;
        statusText = 'Done';
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = AppColors.destructive;
        statusText = 'Failed';
        statusIcon = Icons.error;
        break;
      case 'cancelled':
        statusColor = AppColors.textMuted;
        statusText = 'Cancelled';
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = AppColors.textMuted;
        statusText = 'Queued';
        statusIcon = Icons.hourglass_empty;
    }

    return Container(
      key: ValueKey(job.id),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: index > 0 ? const Border(top: BorderSide(color: AppColors.divider)) : null,
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.preset.name} (${job.preset.width}x${job.preset.height})',
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (job.status == 'processing')
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: LinearProgressIndicator(
                      value: job.progress,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                      minHeight: 3,
                    ),
                  ),
                if (job.status == 'failed' && job.error != null)
                  Text(job.error!, style: const TextStyle(fontSize: 8, color: AppColors.destructive), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(statusText, style: TextStyle(fontSize: 8, color: statusColor)),
          if (job.status == 'queued') ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () {
                setState(() => _batchProcessor.removeJob(job.id));
              },
              child: const Icon(Icons.close, size: 14, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  // ── Bottom Actions ──
  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _isExporting ? null : _addToQueue,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('إضافة إلى القائمة', style: TextStyle(fontSize: 10)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: (_isExporting || _batchProcessor.jobs.isEmpty) ? null : () {
                setState(() => _isExporting = true);
                _batchProcessor.processQueue();
                widget.onStartBatch?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: Text(_isExporting ? 'قيد التشغيل...' : 'بدء الريندر', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
          if (_isExporting) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _batchProcessor.cancel();
                  setState(() => _isExporting = false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.destructive,
                  side: const BorderSide(color: AppColors.destructive),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('إيقاف', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Progress Bar ──
  Widget _buildProgressBar() {
    final progress = _batchProcessor.overallProgress;
    final doneCount = _completedJobs.length;
    final failedCount = _batchProcessor.jobs.where((j) => j.status == 'failed').length;
    final total = _batchProcessor.jobs.length;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Overall: $doneCount/$total done',
                style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
              ),
              if (failedCount > 0)
                Text(
                  '$failedCount failed',
                  style: const TextStyle(fontSize: 9, color: AppColors.destructive),
                ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(
                failedCount > 0 && progress < 1.0
                    ? AppColors.warning
                    : progress >= 1.0
                        ? AppColors.secondary
                        : AppColors.primary,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  void _addToQueue() {
    if (_selectedEncoder == null || _selectedFormat == null || _selectedPreset == null) return;

    final preset = ExportPresetPro(
      name: '${_selectedPreset!.name} - ${_selectedEncoder!.name}',
      description: '${_selectedPreset!.width}x${_selectedPreset!.height}, ${_selectedEncoder!.name}',
      iconName: _selectedPreset!.iconName,
      width: _selectedPreset!.width,
      height: _selectedPreset!.height,
      fps: _selectedPreset!.fps,
      aspectRatio: _selectedPreset!.aspectRatio,
      quality: _selectedPreset!.quality,
      format: _selectedFormat!.ffmpegFormat,
      encoder: _selectedEncoder!,
      container: _selectedFormat!,
      maxBitrateMbps: _maxBitrateMbps,
      twoPass: _twoPass,
      includeMetadata: _includeMetadata,
      watermarkPath: _watermarkPath,
      watermarkPosition: _watermarkPosition,
    );

    setState(() {
      _batchProcessor.addToQueue(preset, totalDurationSec: _estimatedDurationSec);
    });
    widget.onEnqueue?.call(preset);
  }
}
