import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../native/ffmpeg_service.dart';
import 'reference_dna.dart';

// ─────────────────────────────────────────────────────────────
// محلل الفيديو المرجعي → StyleDNA
//
// كله معالجة إشارة محلية (بدون AI API): حدود مشاهد، تصنيف انتقالات،
// بدايات صوتية (onsets)، tempo، طبقة موسيقية، مزاج لوني، مقدمة/نهاية.
// الدوال النقية في الأعلى (قابلة للاختبار بفيكسچرز)، والـ runners الرفيعة
// في الأسفل (ffmpeg فقط). انظر docs/STYLE_DNA_REFERENCE.md.
// ─────────────────────────────────────────────────────────────

// ═══════════ 1. حدود المشاهد ═══════════

/// `select='gt(scene,T)',showinfo` → أزمنة بدايات اللقطات (تشمل 0.0).
List<double> parseSceneCuts(String stderr) {
  final times = <double>{0.0};
  final re = RegExp(r'n:\s*\d+\s+pts:\s*\d+\s+pts_time:([\d.]+)');
  for (final line in const LineSplitter().convert(stderr)) {
    if (!line.contains('showinfo')) continue;
    final m = re.firstMatch(line);
    if (m != null) {
      final t = double.tryParse(m.group(1)!);
      if (t != null && t.isFinite && t >= 0) times.add(t);
    }
  }
  final sorted = times.toList()..sort();
  return sorted;
}

// ═══════════ 2. منحنى السطوع ═══════════

/// `signalstats,metadata=print` → [{time, y}] لمتوسط لمعان كل فريم.
List<Map<String, double>> parseBrightnessCurve(String stderr) {
  final out = <Map<String, double>>[];
  var current = 0.0;
  final frameRe = RegExp(r'^frame:\d+\s+pts:\d+\s+pts_time:([\d.]+)');
  final yRe = RegExp(r'lavfi\.signalstats\.YAVG=([\d.]+)');
  for (final line in const LineSplitter().convert(stderr)) {
    final f = frameRe.firstMatch(line.trim());
    if (f != null) {
      final t = double.tryParse(f.group(1)!);
      if (t != null && t.isFinite) current = t;
      continue;
    }
    final y = yRe.firstMatch(line);
    if (y != null) {
      final v = double.tryParse(y.group(1)!);
      if (v != null && v.isFinite) out.add({'time': current, 'y': v});
    }
  }
  return out;
}

/// تصنيف كل حدّ: fade (انحدار للأسود)، dissolve (تدرج)، وإلا cut.
Map<String, double> classifyTransitions(
  List<double> shots,
  List<Map<String, double>> brightness,
  double totalDuration,
) {
  if (shots.length < 2) {
    return {'cut': 1.0, 'dissolve': 0.0, 'fade': 0.0, 'wipe': 0.0};
  }
  double brightnessAt(double t) {
    var best = brightness.isEmpty ? 128.0 : brightness.first['y']!;
    var bestDt = double.infinity;
    for (final p in brightness) {
      final dt = (p['time']! - t).abs();
      if (dt < bestDt) {
        bestDt = dt;
        best = p['y']!;
      }
    }
    return best;
  }

  var cut = 0, dissolve = 0, fade = 0;
  for (var i = 1; i < shots.length; i++) {
    final t = shots[i];
    // نافذة ±0.5s حول الحد
    final samples = <double>[];
    for (var dt = -0.5; dt <= 0.5; dt += 0.1) {
      final tt = (t + dt).clamp(0.0, totalDuration);
      samples.add(brightnessAt(tt));
    }
    final lo = samples.reduce((a, b) => a < b ? a : b);
    final hi = samples.reduce((a, b) => a > b ? a : b);
    final range = hi - lo;
    if (lo < 16) {
      fade++;
    } else if (range > 40) {
      dissolve++;
    } else {
      cut++;
    }
  }
  final n = shots.length - 1;
  return {
    'cut': cut / n,
    'dissolve': dissolve / n,
    'fade': fade / n,
    'wipe': 0.0,
  };
}

// ═══════════ 3. البدايات الصوتية (onsets) ═══════════

/// قمم energy-flux من PCM أحادي — أحداث whoosh/pop/click.
///
class OnsetResult {
  final List<double> times;
  final List<double> sharpness;
  const OnsetResult(this.times, this.sharpness);
}

OnsetResult detectOnsets(Int16List pcm, int sampleRate) {
  const frame = 1024;
  const hop = 512;
  if (pcm.length < frame * 2) return const OnsetResult([], []);
  final energies = <double>[];
  for (var start = 0; start + frame <= pcm.length; start += hop) {
    var e = 0.0;
    for (var i = start; i < start + frame; i++) {
      final s = pcm[i] / 32768.0;
      e += s * s;
    }
    energies.add(e / frame);
  }
  final flux = <double>[0.0];
  for (var i = 1; i < energies.length; i++) {
    final d = energies[i] - energies[i - 1];
    flux.add(d > 0 ? d : 0.0);
  }
  final sorted = [...flux]..sort();
  final median = sorted[sorted.length ~/ 2];
  final threshold = median * 1.8 + 1e-7;

  final times = <double>[];
  final sharp = <double>[];
  var lastIdx = -100000;
  final minGap = (0.12 * sampleRate / hop).round().clamp(1, 1 << 30);
  for (var i = 1; i < flux.length - 1; i++) {
    if (flux[i] > threshold &&
        flux[i] >= flux[i - 1] &&
        flux[i] >= flux[i + 1] &&
        i - lastIdx >= minGap) {
      lastIdx = i;
      times.add(i * hop / sampleRate);
      final local = median <= 0 ? 1e-9 : median;
      sharp.add(flux[i] / local);
    }
  }
  return OnsetResult(times, sharp);
}

/// تقدير tempo من وسيط الفواصل (يُطوى لـ 60–180). صفر عند الندرة.
double estimateTempo(List<double> onsets) {
  if (onsets.length < 5) return 0;
  final gaps = <double>[];
  for (var i = 1; i < onsets.length; i++) {
    final g = onsets[i] - onsets[i - 1];
    if (g >= 0.2 && g <= 2.0) gaps.add(g);
  }
  if (gaps.length < 4) return 0;
  gaps.sort();
  var bpm = 60.0 / gaps[gaps.length ~/ 2];
  while (bpm < 60) {
    bpm *= 2;
  }
  while (bpm > 180) {
    bpm /= 2;
  }
  return double.parse(bpm.toStringAsFixed(1));
}

/// طبقة موسيقية؟ نبض مستمر داخل فترات الصمت نفسها.
bool detectMusicBed({
  required List<double> onsets,
  required List<Map<String, dynamic>> silences,
  required double totalDuration,
}) {
  if (onsets.isEmpty || silences.isEmpty || totalDuration <= 0) return false;
  var silDur = 0.0;
  var inSil = 0;
  bool inside(double t) {
    for (final s in silences) {
      final a = (s['start'] as num).toDouble();
      final b = (s['end'] as num).toDouble();
      if (t >= a && t < b) return true;
    }
    return false;
  }

  for (final s in silences) {
    silDur += ((s['end'] as num).toDouble() - (s['start'] as num).toDouble())
        .clamp(0.0, double.infinity);
  }
  for (final t in onsets) {
    if (inside(t)) inSil++;
  }
  if (silDur < 2.0) return false;
  final rateInSil = inSil / silDur;
  final rateAll = onsets.length / totalDuration;
  return rateAll > 0 && rateInSil > 0.3 * rateAll;
}

// ═══════════ 4. اللون ═══════════

/// متوسط RGB + تشبع + تباين من صورة مفكوكة (package:image).
Map<String, double> colorMoments(img.Image image) {
  final w = image.width, h = image.height;
  if (w == 0 || h == 0) {
    return {'r': 128, 'g': 128, 'b': 128, 'sat': 0.5, 'contrast': 1.0};
  }
  var sr = 0.0, sg = 0.0, sb = 0.0, ssat = 0.0;
  var n = 0;
  final lum = <double>[];
  final step = ((w * h) / 4096).ceil().clamp(1, 1 << 30);
  for (var y = 0; y < h; y += step) {
    for (var x = 0; x < w; x += step) {
      final px = image.getPixel(x, y);
      final r = px.r.toDouble(), g = px.g.toDouble(), b = px.b.toDouble();
      sr += r;
      sg += g;
      sb += b;
      final mx = [r, g, b].reduce((a, v) => a > v ? a : v);
      final mn = [r, g, b].reduce((a, v) => a < v ? a : v);
      ssat += mx <= 0 ? 0 : (mx - mn) / mx;
      lum.add(0.299 * r + 0.587 * g + 0.114 * b);
      n++;
    }
  }
  if (n == 0) {
    return {'r': 128, 'g': 128, 'b': 128, 'sat': 0.5, 'contrast': 1.0};
  }
  final mean = lum.reduce((a, v) => a + v) / lum.length;
  var variance = 0.0;
  for (final l in lum) {
    variance += (l - mean) * (l - mean);
  }
  variance /= lum.length;
  final std = sqrtDouble(variance);
  return {
    'r': sr / n,
    'g': sg / n,
    'b': sb / n,
    'sat': (ssat / n).clamp(0.0, 1.0),
    // تقريبي: انحراف اللمعان مقياسًا — 1.0 متوسط، أعلى = تباين أعلى.
    'contrast': (std / 52.0).clamp(0.6, 1.6),
  };
}

double sqrtDouble(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 20; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}

/// مزاج لوني + حرارة تقريبية من متوسط RGB.
Map<String, dynamic> colorMood(double r, double g, double b, double sat) {
  String mood;
  if (sat < 0.18) {
    mood = 'muted';
  } else if (r - b > 14) {
    mood = 'warm';
  } else if (b - r > 14) {
    mood = 'cool';
  } else if (sat > 0.55) {
    mood = 'vivid';
  } else {
    mood = 'neutral';
  }
  // خريطة خشنة: دافئ ≈ 3500K، محايد ≈ 5600K، بارد ≈ 7200K.
  final temperature = (5600 - (r - b) * 45).clamp(3200.0, 7500.0);
  return {'mood': mood, 'temperature': temperature};
}

// ═══════════ 5. مقدمة/نهاية/هوك ═══════════

Map<String, dynamic> detectBookends(List<double> shots, double totalDuration) {
  var hasIntro = false;
  var introSec = 0.0;
  var hasOutro = false;
  var outroSec = 0.0;
  if (shots.length >= 3 && totalDuration > 0) {
    final firstDur = shots[1] - shots[0];
    if (firstDur <= 3.0) {
      hasIntro = true;
      introSec = firstDur;
    }
    final lastDur = totalDuration - shots.last;
    if (lastDur >= 6.0) {
      hasOutro = true;
      outroSec = lastDur.clamp(0.0, 20.0);
    }
  }
  return {
    'has_intro': hasIntro,
    'intro_sec': introSec,
    'has_outro': hasOutro,
    'outro_sec': outroSec,
  };
}

Map<String, dynamic> hookStyle(List<double> shots, double totalDuration) {
  final first = shots.length > 1 ? shots[1] - shots[0] : totalDuration;
  var cutsFirst10 = 0;
  for (var i = 1; i < shots.length; i++) {
    if (shots[i] <= 10.0) cutsFirst10++;
  }
  String style;
  if (cutsFirst10 >= 5) {
    style = 'fast_montage';
  } else if (first <= 1.5) {
    style = 'cold_open';
  } else if (first <= 3.0) {
    style = 'quick_hook';
  } else {
    style = 'statement';
  }
  return {'style': style, 'first_shot_sec': first};
}

// ═══════════ runners (رفيعة — ffmpeg فقط) ═══════════

class ReferenceAnalyzer {
  const ReferenceAnalyzer();

  /// حدود المشاهد عبر select(scene).
  Future<List<double>> analyzeShots(String path,
      {double threshold = 0.4}) async {
    try {
      final exe = await FfmpegService.resolveExe();
      final r = await Process.run(exe, [
        '-hide_banner', '-i', path,
        '-vf', "select='gt(scene,$threshold)',showinfo",
        '-f', 'null', '-',
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      return parseSceneCuts(r.stderr as String);
    } catch (_) {
      return const [0.0];
    }
  }

  /// منحنى السطوع عبر signalstats.
  Future<List<Map<String, double>>> analyzeBrightness(String path) async {
    try {
      final exe = await FfmpegService.resolveExe();
      final r = await Process.run(exe, [
        '-hide_banner', '-i', path,
        '-vf', 'signalstats,metadata=print',
        '-f', 'null', '-',
      ], stdoutEncoding: utf8, stderrEncoding: utf8);
      return parseBrightnessCurve(r.stderr as String);
    } catch (_) {
      return const [];
    }
  }

  /// PCM أحادي 8kHz عبر pipe (للبدايات والـ tempo والطبقة).
  Future<(Int16List, int)> decodeMono(String path) async {
    const rate = 8000;
    final exe = await FfmpegService.resolveExe();
    final r = await Process.run(exe, [
      '-hide_banner', '-loglevel', 'error',
      '-i', path, '-ac', '1', '-ar', '$rate', '-f', 's16le', 'pipe:1',
    ], stdoutEncoding: null);
    if (r.exitCode != 0 || r.stdout == null) return (Int16List(0), rate);
    final bytes = r.stdout as List<int>;
    if (bytes.length < 2) return (Int16List(0), rate);
    return (
      Int16List.view(Uint8List.fromList(bytes).buffer, 0, bytes.length ~/ 2),
      rate
    );
  }

  /// لقطات JPEG صغيرة لأزمنة معينة (للمزاج اللوني).
  Future<List<img.Image>> thumbnails(String path, List<double> times,
      {int width = 64}) async {
    final out = <img.Image>[];
    final exe = await FfmpegService.resolveExe();
    for (final t in times) {
      try {
        final r = await Process.run(exe, [
          '-hide_banner', '-loglevel', 'error',
          '-ss', t.toStringAsFixed(2), '-i', path,
          '-frames:v', '1', '-vf', 'scale=$width:-2',
          '-f', 'mjpeg', 'pipe:1',
        ], stdoutEncoding: null);
        if (r.exitCode != 0 || r.stdout == null) continue;
        final decoded = img.decodeJpg(
            Uint8List.fromList((r.stdout as List<int>).cast<int>()));
        if (decoded != null) out.add(decoded);
      } catch (_) {}
    }
    return out;
  }

  /// التحليل الكامل: مسار مرجعي → ReferenceDna.
  ///
  /// [onProgress] بقيم 0..1 للواجهة (عملية خلفية طويلة).
  Future<ReferenceDna> analyzeReference(
    String path, {
    String channel = '',
    String videoId = '',
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.05, 'قياس المدة...');
    final duration = await FfmpegService.probeDuration(path) ?? 0.0;

    onProgress?.call(0.15, 'كشف المشاهد...');
    var shots = await analyzeShots(path);
    if (shots.isEmpty) shots = [0.0];

    onProgress?.call(0.35, 'منحنى السطوع والانتقالات...');
    final brightness = await analyzeBrightness(path);
    final transitions = classifyTransitions(shots, brightness, duration);

    onProgress?.call(0.5, 'تحليل الصوت...');
    final (pcm, rate) = await decodeMono(path);
    final onsets = detectOnsets(pcm, rate);
    final tempo = estimateTempo(onsets.times);
    final silences = await FfmpegService.detectSilences(path,
        minSilenceDur: FfmpegService.silenceThresholdFor(duration));

    onProgress?.call(0.7, 'الموسيقى والكلام...');
    final bed = detectMusicBed(
        onsets: onsets.times, silences: silences, totalDuration: duration);
    var silDur = 0.0;
    for (final s in silences) {
      silDur += ((s['end'] as num).toDouble() - (s['start'] as num).toDouble())
          .clamp(0.0, double.infinity);
    }
    final speechFraction =
        duration > 0 ? ((duration - silDur) / duration).clamp(0.0, 1.0) : 0.0;

    onProgress?.call(0.82, 'الألوان...');
    final mids = <double>[];
    for (var i = 0; i < shots.length && mids.length < 10; i++) {
      final end = i + 1 < shots.length ? shots[i + 1] : duration;
      final mid = (shots[i] + end) / 2;
      if (mid < duration) mids.add(mid);
    }
    final thumbs = await thumbnails(path, mids);
    var r = 128.0, g = 128.0, b = 128.0, sat = 0.5, contrast = 1.0;
    if (thumbs.isNotEmpty) {
      var sr = 0.0, sg = 0.0, sb = 0.0, ss = 0.0, sc = 0.0;
      for (final th in thumbs) {
        final m = colorMoments(th);
        sr += m['r']!;
        sg += m['g']!;
        sb += m['b']!;
        ss += m['sat']!;
        sc += m['contrast']!;
      }
      final n = thumbs.length.toDouble();
      r = sr / n;
      g = sg / n;
      b = sb / n;
      sat = ss / n;
      contrast = sc / n;
    }
    final mood = colorMood(r, g, b, sat);

    // إيقاع
    final shotDurs = <double>[];
    for (var i = 0; i < shots.length; i++) {
      final end = i + 1 < shots.length ? shots[i + 1] : duration;
      if (end > shots[i]) shotDurs.add(end - shots[i]);
    }
    final avgShot = shotDurs.isEmpty
        ? 0.0
        : shotDurs.reduce((a, v) => a + v) / shotDurs.length;
    final cutsPerMin =
        duration > 0 ? (shots.length - 1) / duration * 60.0 : 0.0;
    var firstHalf = 0, secondHalf = 0;
    for (var i = 1; i < shots.length; i++) {
      if (shots[i] < duration / 2) {
        firstHalf++;
      } else {
        secondHalf++;
      }
    }
    final accelerating =
        firstHalf > 0 && secondHalf / firstHalf > 1.3;

    // أصوات: كثافة + نسبة على القص + أنواع من الحدة
    final eventsPerMin =
        duration > 0 ? onsets.times.length / duration * 60.0 : 0.0;
    var onCut = 0;
    final typeCount = <String, int>{};
    for (var i = 0; i < onsets.times.length; i++) {
      final t = onsets.times[i];
      for (var j = 1; j < shots.length; j++) {
        if ((shots[j] - t).abs() <= 0.3) {
          onCut++;
          break;
        }
      }
      final type = onsets.sharpness[i] > 2.5 ? 'pop' : 'whoosh';
      typeCount[type] = (typeCount[type] ?? 0) + 1;
    }
    final types = typeCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    onProgress?.call(0.95, 'تجميع البصمة...');
    final bookends = detectBookends(shots, duration);
    final hook = hookStyle(shots, duration);

    return ReferenceDna(
      channel: channel,
      videoId: videoId,
      sourceDuration: duration,
      rhythm: RhythmDna(
        avgShot: _round3(avgShot),
        cutsPerMin: _round3(cutsPerMin),
        accelerating: accelerating,
      ),
      transitions: TransitionDna(
        cut: _round3(transitions['cut']!),
        dissolve: _round3(transitions['dissolve']!),
        fade: _round3(transitions['fade']!),
        wipe: 0,
      ),
      sfx: SfxDna(
        eventsPerMin: _round3(eventsPerMin),
        onCutRatio: onsets.times.isEmpty
            ? 0
            : _round3(onCut / onsets.times.length),
        types: types.map((e) => e.key).toList(),
      ),
      music: MusicDna(
        hasBed: bed,
        bedDb: -20,
        tempoBpm: tempo,
        mood: tempo >= 120
            ? 'upbeat'
            : tempo >= 90
                ? 'groovy'
                : tempo > 0
                    ? 'calm'
                    : 'neutral',
        hasIntroSting: bookends['has_intro'] as bool && bed,
        hasOutro: bookends['has_outro'] as bool,
      ),
      color: ColorDna(
        mood: mood['mood'] as String,
        saturation: _round3(sat),
        temperature: _round3((mood['temperature'] as num).toDouble()),
        contrast: _round3(contrast),
      ),
      captions: CaptionDna(
        density: _round3(speechFraction),
        casing: 'mixed',
        position: 'bottom',
        wordsPerCaption: 3,
      ),
      bookends: BookendsDna(
        hasIntro: bookends['has_intro'] as bool,
        introSec: _round3((bookends['intro_sec'] as num).toDouble()),
        hasOutro: bookends['has_outro'] as bool,
        outroSec: _round3((bookends['outro_sec'] as num).toDouble()),
      ),
      hook: HookDna(
        style: hook['style'] as String,
        firstShotSec:
            _round3((hook['first_shot_sec'] as num).toDouble()),
      ),
    );
  }
}

double _round3(double v) => (v * 1000).round() / 1000;
