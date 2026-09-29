import 'dart:convert';
import 'dart:io';

/// YouTube download via yt-dlp — fully standalone (no backend needed).
class YoutubeService {
  YoutubeService._();

  static String? _exe;
  static bool _resolved = false;

  /// Resolve yt-dlp: PATH → python -m yt_dlp → backend fallback
  static Future<String> resolveExe() async {
    if (_resolved) return _exe ?? 'yt-dlp';
    _resolved = true;

    // 1) standalone yt-dlp.exe in PATH
    try {
      final r = await Process.run('where', ['yt-dlp']);
      if (r.exitCode == 0) {
        final p = (r.stdout as String).trim().split('\n').first.trim();
        if (p.isNotEmpty) {
          _exe = p;
          return _exe!;
        }
      }
    } catch (_) {}

    // 2) python -m yt_dlp
    try {
      final r = await Process.run('python', ['-m', 'yt_dlp', '--version']);
      if (r.exitCode == 0) {
        _exe = 'python -m yt_dlp';
        return _exe!;
      }
    } catch (_) {}

    _exe = 'yt-dlp';
    return _exe!;
  }

  /// Download a YouTube video to [outputDir] as MP4 (1080p max).
  /// Returns the downloaded file path, or null on failure.
  static Future<String?> download(
    String url,
    String outputDir, {
    void Function(double progress, String status)? onProgress,
  }) async {
    try {
      final exe = await resolveExe();
      final isModule = exe.startsWith('python');
      final tmpOut = '$outputDir/yt_%(id)s.%(ext)s';

      onProgress?.call(0.05, 'بدء التحميل...');

      final args = isModule
          ? ['-m', 'yt_dlp', ..._buildArgs(url, tmpOut)]
          : [..._buildArgs(url, tmpOut)];

      onProgress?.call(0.1, 'جاري التحميل من يوتيوب...');

      final ProcessResult result;
      if (isModule) {
        result = await Process.run('python', args, stdoutEncoding: utf8, stderrEncoding: utf8);
      } else {
        result = await Process.run(exe, args, stdoutEncoding: utf8, stderrEncoding: utf8);
      }

      if (result.exitCode != 0) {
        onProgress?.call(0.0, 'فشل التحميل: ${result.stderr.toString().substring(0, (result.stderr.toString().length).clamp(0, 100))}');
        return null;
      }

      // Find the downloaded file
      final dir = Directory(outputDir);
      if (!await dir.exists()) return null;
      final files = await dir
          .list()
          .where((f) => f.path.contains('yt_') && (f.path.endsWith('.mp4') || f.path.endsWith('.webm')))
          .toList();
      if (files.isEmpty) return null;

      // Sort by modified time (newest first)
      final stats = <File, DateTime>{};
      for (final f in files) {
        stats[f as File] = (await f.stat()).modified;
      }
      final sorted = stats.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final downloaded = sorted.first.key.path;

      onProgress?.call(1.0, 'تم التحميل!');
      return downloaded;
    } catch (e) {
      onProgress?.call(0.0, 'خطأ: $e');
      return null;
    }
  }

  static List<String> _buildArgs(String url, String outputTemplate) {
    return [
      '-f', 'bestvideo[height<=1080]+bestaudio/best[height<=1080]',
      '--merge-output-format', 'mp4',
      '-o', outputTemplate,
      '--no-playlist',
      '--no-warnings',
      url,
    ];
  }
}
