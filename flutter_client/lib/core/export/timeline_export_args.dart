import 'dart:math' as math;

import '../models/timeline_models.dart';

// ─────────────────────────────────────────────────────────────
// وحدة تصدير واحدة: مقطع من مصدر، أو فجوة (سوداء + صمت)
// ─────────────────────────────────────────────────────────────

class ExportSegment {
  /// null = فجوة على التايملاين (أسود + صمت).
  final String? sourcePath;
  final double trimStart;
  final double trimDuration;
  final double speed;
  final double volume;
  final bool hasAudio;

  const ExportSegment({
    required this.sourcePath,
    required this.trimStart,
    required this.trimDuration,
    required this.speed,
    required this.volume,
    required this.hasAudio,
  });

  bool get isGap => sourcePath == null;

  /// طول المقطع في المخرج (مدة المادة ÷ التسريع).
  double get outputDuration => trimDuration / (speed <= 0 ? 1.0 : speed);
}

/// تحويل كليبات المسار إلى تسلسل مقاطع متصلة يشمل الفجوات.
///
/// - يدعم تداخل الكليبات: يُقصّ رأس المقطع المتأخر عند نهاية السابق.
/// - [clips] تُفترض من مسار واحد (v1: المسار الرئيسي) — تراكب المسارات
///   يحتاج compositing ولا يُدعم في هذا الإصدار.
List<ExportSegment> buildExportSegments(List<VideoClip> clips) {
  final sorted = [...clips]
    ..sort((a, b) => a.startTimeInTimeline.compareTo(b.startTimeInTimeline));
  final segments = <ExportSegment>[];
  const epsilon = 0.01;
  double cursor = 0;

  for (final clip in sorted) {
    final start = clip.startTimeInTimeline;
    final end = clip.endTimeInTimeline;
    if (end - start <= epsilon) continue;
    final speed = clip.speed <= 0 ? 1.0 : clip.speed;

    if (start > cursor + epsilon) {
      segments.add(ExportSegment(
        sourcePath: null,
        trimStart: 0,
        trimDuration: start - cursor,
        speed: 1,
        volume: 1,
        hasAudio: true,
      ));
    }

    final effectiveStart = math.max(start, cursor);
    double trimStart = clip.sourceTrimStart;
    double trimDur =
        math.max(epsilon, clip.sourceTrimEnd - clip.sourceTrimStart);
    if (effectiveStart > start + epsilon) {
      final overlap = effectiveStart - start;
      trimStart += overlap * speed;
      trimDur = math.max(epsilon, trimDur - overlap * speed);
    }
    if (end - effectiveStart <= epsilon) continue;

    segments.add(ExportSegment(
      sourcePath: clip.sourcePath,
      trimStart: trimStart,
      trimDuration: trimDur,
      speed: speed,
      volume: clip.volume,
      hasAudio: true, // يُستكشَف لاحقًا لكل مصدر (probeHasAudio)
    ));
    cursor = math.max(cursor, end);
  }
  return segments;
}

// ─────────────────────────────────────────────────────────────
// فلاتر مساعدة (نقيّة قابلة للاختبار)
// ─────────────────────────────────────────────────────────────

/// سلسلة atempo صالحة لأي سرعة — ffmpeg يقبل [0.5, 2.0] فقط لكل عقدة.
String atempoChain(double speed) {
  if (speed <= 0) return '';
  double s = speed;
  final parts = <String>[];
  while (s > 2.0) {
    parts.add('atempo=2');
    s /= 2.0;
  }
  while (s < 0.5) {
    parts.add('atempo=0.5');
    s /= 0.5;
  }
  if ((s - 1.0).abs() > 1e-6) parts.add('atempo=${numStr(s)}');
  return parts.join(',');
}

/// رقم قصير بلا أصفار زائدة (لأوامر ffmpeg).
String numStr(double v) {
  var s = v.toStringAsFixed(4);
  if (s.contains('.')) {
    s = s.replaceAll(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  return s;
}

/// هل يستقبل هذا الترميز خيار ‎`-preset`؟ (x264/x265/NVENC/AMF/QSV فقط)
bool usesFfmpegPreset(String encoder) {
  const presets = {
    'libx264',
    'libx265',
    'h264_nvenc',
    'hevc_nvenc',
    'av1_nvenc',
    'h264_amf',
    'hevc_amf',
    'h264_qsv',
    'hevc_qsv',
    'av1_qsv',
  };
  return presets.contains(encoder);
}

/// هل يدعم هذا الترميز التصدير ذي المرورتين (two-pass)؟ — البرمجيات فقط.
bool supportsTwoPass(String encoder) {
  const supported = {
    'libx264',
    'libx265',
    'libaom-av1',
    'libsvtav1',
    'libvpx-vp9',
  };
  return supported.contains(encoder);
}

/// تحويل موقع العلامة المائية إلى تعبير overlay.
String watermarkPositionExpr(String? position) {
  const posMap = <String, String>{
    'top-left': '10:10',
    'top-right': 'W-w-10:10',
    'bottom-left': '10:H-h-10',
    'bottom-right': 'W-w-10:H-h-10',
    'center': '(W-w)/2:(H-h)/2',
  };
  return posMap[position] ?? posMap['bottom-right']!;
}

// ─────────────────────────────────────────────────────────────
// بناء أمر ffmpeg الكامل
// ─────────────────────────────────────────────────────────────

/// [pass]: 0 = تمريرة واحدة، 1/2 = pass مدفوع (يُشغَّل مرتين من المستدعي).
///
/// البنية: مدخل لكل مقاطع (‎-ss/-t دقيق) + فجوات lavfi → filter_complex
/// (scale/pad/fps + سرعة + تطويل بالآخر إطار عند نفاد المادة) → concat →
/// watermark اختياري → encode.
List<String> buildExportArgs({
  required List<ExportSegment> segments,
  required int width,
  required int height,
  required int fps,
  required String encoder,
  required String pixelFormat,
  required int bitrateMbps,
  required int maxBitrateMbps,
  required String encoderPreset,
  required String ffmpegFormat,
  required String outputPath,
  required int pass,
  bool includeMetadata = true,
  String? watermarkPath,
  String? watermarkPosition,
  String nullSink = 'NUL',
}) {
  final args = <String>['-y', '-hide_banner', '-loglevel', 'error', '-stats'];
  final videoLabels = <String>[];
  final audioLabels = <String>[];
  final filters = <String>[];

  // GIF بلا صوت أصلًا — أي خريطة صوتية تفشل التصدير حتمًا، وحتى مخرج
  // concat الصوتي غير المستهلَك يرفضه ffmpeg. تُبنى الرسوم بلا صوت تمامًا.
  final mapsAudio = pass != 1 && ffmpegFormat != 'gif';

  int inputIndex = 0;
  final segVideoIdx = <int>[];
  final segAudioIdx = <int>[];

  for (final seg in segments) {
    final d = numStr(seg.outputDuration);
    if (seg.isGap) {
      args.addAll([
        '-f', 'lavfi', '-t', d,
        '-i', 'color=c=black:s=${width}x$height:r=$fps',
      ]);
      segVideoIdx.add(inputIndex++);
      args.addAll([
        '-f', 'lavfi', '-t', d,
        '-i', 'anullsrc=r=48000:cl=stereo',
      ]);
      segAudioIdx.add(inputIndex++);
      continue;
    }

    args.addAll([
      '-ss', numStr(seg.trimStart),
      '-t', numStr(seg.trimDuration),
      '-i', seg.sourcePath!,
    ]);
    segVideoIdx.add(inputIndex++);
    if (seg.hasAudio) {
      segAudioIdx.add(segVideoIdx.last);
    } else {
      args.addAll(['-f', 'lavfi', '-t', d, '-i', 'anullsrc=r=48000:cl=stereo']);
      segAudioIdx.add(inputIndex++);
    }
  }

  int? watermarkIdx;
  if (watermarkPath != null && watermarkPath.isNotEmpty) {
    args.addAll(['-i', watermarkPath]);
    watermarkIdx = inputIndex++;
  }

  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final d = numStr(seg.outputDuration);

    // فيديو: توحيد المقاس + fps + سرعة ثم قصّ بالطول الدقيق.
    // (طول المخرج مشتق دائمًا من المادة ÷ السرعة، فلا حاجة لحشو إضافي)
    final speed = seg.speed;
    final setpts =
        speed == 1 ? 'setpts=PTS-STARTPTS' : 'setpts=(PTS-STARTPTS)/${numStr(speed)}';
    final vFilters = [
      'scale=$width:$height:force_original_aspect_ratio=decrease',
      'pad=$width:$height:(ow-iw)/2:(oh-ih)/2:color=black',
      'fps=$fps',
      'setsar=1',
      setpts,
      'trim=duration=$d',
      'setpts=PTS-STARTPTS',
      'format=yuv420p',
    ];
    final vChain = '[${segVideoIdx[i]}:v]${vFilters.join(',')}';
    final vLabel = 'v$i';
    filters.add('$vChain[$vLabel]');
    videoLabels.add(vLabel);

    // صوت: حجم + سرعة + توحيد 48k ستيريو + تطويل/قصّ بالطول الدقيق
    if (mapsAudio) {
      final atempo = speed == 1 ? '' : '${atempoChain(speed)},';
      final aFilters = [
        'volume=${numStr(seg.volume)}',
        '${atempo}aresample=48000',
        'aformat=sample_fmts=fltp:channel_layouts=stereo',
        'apad',
        'atrim=duration=$d',
        'asetpts=PTS-STARTPTS',
      ];
      final aChain = '[${segAudioIdx[i]}:a]${aFilters.join(',')}';
      final aLabel = 'a$i';
      filters.add('$aChain[$aLabel]');
      audioLabels.add(aLabel);
    }
  }

  // concat يستهلك المدخلات أزواجًا متداخلة (v,a,v,a…) — ترتيب فيديوهات-ثم-
  // أصوات يربط دبابيس بنوع خاطئ ويفشل الرسم (mismatch/invalid argument).
  final concatIn = StringBuffer();
  for (var i = 0; i < segments.length; i++) {
    concatIn.write('[${videoLabels[i]}]');
    if (mapsAudio) concatIn.write('[${audioLabels[i]}]');
  }
  final concatTail = mapsAudio ? '[vc][ac]' : '[vc]';
  filters.add(
      '${concatIn}concat=n=${segments.length}:v=1:a=${mapsAudio ? 1 : 0}$concatTail');

  String outVideo = 'vc';
  if (watermarkIdx != null) {
    filters.add(
        '[vc][$watermarkIdx:v]overlay=${watermarkPositionExpr(watermarkPosition)}[vout]');
    outVideo = 'vout';
  }

  args.addAll(['-filter_complex', filters.join(';')]);
  args.addAll(['-map', '[$outVideo]']);
  if (mapsAudio) args.addAll(['-map', '[ac]']);

  args.addAll([
    '-c:v', encoder,
    '-b:v', '${bitrateMbps}M',
    '-maxrate', '${maxBitrateMbps}M',
    '-bufsize', '${maxBitrateMbps * 2}M',
    '-r', '$fps',
    '-pix_fmt', pixelFormat,
  ]);
  if (usesFfmpegPreset(encoder)) {
    args.addAll(['-preset', encoderPreset]);
  }
  if (pass != 0) args.addAll(['-pass', '$pass']);
  if (!includeMetadata) args.addAll(['-map_metadata', '-1']);

  if (pass == 1) {
    args.addAll(['-an', '-f', 'null', nullSink]);
    return args;
  }

  if (mapsAudio) {
    args.addAll(['-c:a', 'aac', '-b:a', '192k']);
  }
  if (ffmpegFormat == 'mp4') args.addAll(['-movflags', '+faststart']);
  args.addAll(['-f', ffmpegFormat, outputPath]);
  return args;
}

/// تقدّم من سطر `time=HH:MM:SS.xx` مقابل إجمالي المدة بالثواني.
double? parseFfmpegProgress(String line, {required double totalSec}) {
  if (totalSec <= 0) return null;
  final match =
      RegExp(r'time=(\d+):(\d+):(\d+)\.(\d+)').firstMatch(line);
  if (match == null) return null;
  final h = int.parse(match.group(1)!);
  final m = int.parse(match.group(2)!);
  final s = int.parse(match.group(3)!);
  final cs = int.parse(match.group(4)!);
  final current = h * 3600 + m * 60 + s + cs / 100.0;
  return (current / totalSec).clamp(0.0, 1.0).toDouble();
}
