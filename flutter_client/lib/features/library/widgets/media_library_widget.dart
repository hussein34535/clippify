import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/api/api_client.dart';
import '../../../core/native/ffmpeg_service.dart';
import '../../../core/native/youtube_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_kit.dart';
import '../../timeline/logic/add_media.dart';

class MediaFile {
  final String path;
  final String name;
  final bool isYoutube;
  final String? thumbnailPath;
  final double duration;

  MediaFile({required this.path, required this.name, this.isYoutube = false, this.thumbnailPath, this.duration = 0.0});

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'isYoutube': isYoutube,
        'thumbnailPath': thumbnailPath,
        'duration': duration,
      };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
        path: json['path'] as String? ?? '',
        name: json['name'] as String? ?? '',
        isYoutube: json['isYoutube'] as bool? ?? false,
        thumbnailPath: json['thumbnailPath'] as String?,
        duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      );
}

class MediaLibraryWidget extends ConsumerStatefulWidget {
  final Function(String) onSelectVideo;
  final List<MediaFile> importedFiles;
  final Function(MediaFile) onFileAdded;
  final Function(int index)? onFileRemoved;
  final void Function(String path)? onAutoEdit;

  /// Injectable media-info resolver (duration lookup). Defaults to the real
  /// backend call; tests inject a fake so no network is needed.
  final MediaInfoResolver? mediaInfoResolver;

  const MediaLibraryWidget({
    super.key,
    required this.onSelectVideo,
    required this.importedFiles,
    required this.onFileAdded,
    this.onFileRemoved,
    this.onAutoEdit,
    this.mediaInfoResolver,
  });

  @override
  ConsumerState<MediaLibraryWidget> createState() => _MediaLibraryWidgetState();
}

class _MediaLibraryWidgetState extends ConsumerState<MediaLibraryWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';
  bool _downloadCancelled = false;
  int? _hoveredIndex;

  Future<String?> _generateThumbnail(String videoPath) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final thumbPath = p.join(tempDir.path, '${videoPath.hashCode}_thumb.jpg');
      if (await File(thumbPath).exists()) return thumbPath;

      final result = await Process.run('ffmpeg', [
        '-i', videoPath,
        '-ss', '00:00:01',
        '-vframes', '1',
        '-q:v', '2',
        '-vf', 'scale=160:-1',
        '-y',
        thumbPath,
      ]);
      if (result.exitCode == 0 && await File(thumbPath).exists()) return thumbPath;
      debugPrint('[MediaLibrary] FFmpeg thumbnail error: ${result.stderr}');
      return null;
    } catch (e) {
      debugPrint('[MediaLibrary] Thumbnail error: $e');
      return null;
    }
  }

  Future<double> _getVideoDuration(String videoPath) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        videoPath,
      ]);
      if (result.exitCode == 0) {
        return double.tryParse(result.stdout.toString().trim()) ?? 0.0;
      }
    } catch (_) {}
    return 0.0;
  }

  Future<void> _importLocalVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final name = result.files.single.name;

        final apiClient = ApiClient();
        final mediaInfo = await apiClient.getMediaInfo(path);

        double duration = 0.0;
        String? thumbPath;

        switch (mediaInfo) {
          case Success(data: final data):
            if (data['status'] == 'success') {
              duration = (data['duration'] as num?)?.toDouble() ?? 0.0;
              thumbPath = data['thumbnail_path'] as String?;
            } else {
              thumbPath = await _generateThumbnail(path);
              duration = await _getVideoDuration(path);
            }
          case Failure():
            thumbPath = await _generateThumbnail(path);
            duration = await _getVideoDuration(path);
        }

        final media = MediaFile(path: path, name: name, thumbnailPath: thumbPath, duration: duration);
        widget.onFileAdded(media);
        widget.onSelectVideo(path);
      }
    } catch (e) {
      debugPrint('[MediaLibrary] Error picking file: $e');
    }
  }

  Future<void> _downloadYoutubeVideo(String url) async {
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadCancelled = false;
      _downloadProgress = 0.0;
      _downloadStatus = 'بدء معالجة رابط يوتيوب...';
    });

    // ── STANDALONE: yt-dlp directly, no backend needed ──
    final tmpDir = Directory.systemTemp.path;
    final downloaded = await YoutubeService.download(
      url,
      tmpDir,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });
        }
      },
    );

    if (downloaded != null && mounted) {
      // Get duration via FfmpegService
      final duration = await FfmpegService.probeDuration(downloaded) ?? 0.0;
      final name = downloaded.split(Platform.pathSeparator).last;
      final media = MediaFile(
        path: downloaded,
        name: name,
        isYoutube: true,
        duration: duration,
      );
      widget.onFileAdded(media);
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadStatus = '';
      });
    } else if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadStatus = _downloadCancelled
            ? 'أُلغي التحميل.'
            : 'فشل التحميل. تأكد من تثبيت yt-dlp ومن اتصالك بالإنترنت.';
      });
    }
  }

  void _cancelDownload() {
    _downloadCancelled = true;
    YoutubeService.cancelDownload();
  }

  Future<void> _showYoutubeDialog() async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: const BorderSide(color: AppColors.border, width: 0.5),
          ),
          title: const Text('تحميل من يوتيوب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamilyFallback: AppTypography.fallbacks)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'أدخل رابط فيديو يوتيوب...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.textSecondary))),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
              child: const Text('تحميل'),
            ),
          ],
        );
      },
    );
    if (url != null && url.isNotEmpty) {
      await _downloadYoutubeVideo(url);
    }
  }

  Widget _buildMediaCard(MediaFile file, int index) {
    final isAudio = isAudioFilePath(file.path);
    final isHovered = _hoveredIndex == index;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = null),
      child: GestureDetector(
      onTap: () => widget.onSelectVideo(file.path),
      // Click-to-add: double-tap drops the media at the playhead (desktop-friendly).
      onDoubleTap: () async {
        await addMediaFromPath(
          ref,
          context,
          file.path,
          mediaInfoResolver: widget.mediaInfoResolver,
        );
      },
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        curve: AppTheme.animCurve,
        transform: Matrix4.translationValues(0, isHovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border, width: 0.5),
          boxShadow: isHovered ? AppShadows.card : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Thumbnail background
            Positioned.fill(
              child: file.thumbnailPath != null && File(file.thumbnailPath!).existsSync()
                  ? Image.file(File(file.thumbnailPath!), fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isAudio
                              ? [const Color(0xFF1C1C1E), const Color(0xFF2C2C2E)]
                              : file.isYoutube
                                  ? [const Color(0xFF421D22), const Color(0xFF2B1417)]
                                  : [const Color(0xFF1B2A41), const Color(0xFF131C2B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          isAudio ? Icons.music_note_rounded : (file.isYoutube ? Icons.play_circle_fill_rounded : Icons.videocam_rounded),
                          size: 32,
                          color: isAudio ? AppColors.secondary : (file.isYoutube ? AppColors.destructive : AppColors.teal).withValues(alpha: 0.85),
                        ),
                      ),
                    ),
            ),

            // Name overlay (top)
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Text(
                  file.name,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white, fontFamilyFallback: AppTypography.fallbacks),
                  maxLines: 1,
                  textDirection: TextDirection.ltr, // keep "name.mp4" sane in RTL layout
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Duration (bottom right) — self-healing: probes the file when the
            // stored duration is unknown instead of claiming 00:00.
            Positioned(
              bottom: 6, right: 6,
              child: _DurationBadge(path: file.path, initialSeconds: file.duration),
            ),

            // Auto-edit popup action (bottom left)
            if (widget.onAutoEdit != null)
              Positioned(
                bottom: 6,
                left: 6,
                child: PopupMenuButton<String>(
                  tooltip: 'مونتاج تلقائي',
                  padding: EdgeInsets.zero,
                  color: AppColors.surfaceVariant,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  onSelected: (_) => widget.onAutoEdit!(file.path),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'auto',
                      height: 36,
                      child: Text('⚡ مونتاج تلقائي', style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, size: 12, color: AppColors.warning),
                  ),
                ),
              ),

            // Delete button (top right)
            Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                onTap: () {
                  if (widget.onFileRemoved != null) {
                    widget.onFileRemoved!(index);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان اللوحة + أزرار الاستيراد
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Text(
              'الملفات المستوردة',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: AppColors.textMuted,
                fontFamilyFallback: AppTypography.fallbacks,
              ),
            ),
          ),

          // أزرار الاستيراد (pill)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: IOSButton(
                    label: 'استيراد',
                    icon: Icons.add_rounded,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    expand: true,
                    onPressed: _isDownloading ? null : _importLocalVideo,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: IOSButton(
                    label: 'يوتيوب',
                    icon: Icons.play_circle_outline_rounded,
                    fontSize: 12,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    style: IOSButtonStyle.ghost,
                    expand: true,
                    onPressed: _isDownloading ? null : _showYoutubeDialog,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // ملفات التحميل من يوتيوب (تقدم + إلغاء + رسالة قابلة للصرف)
          if (_isDownloading || _downloadStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  if (_isDownloading) ...[
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: AppColors.surfaceVariant,
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _downloadStatus,
                          style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontFamilyFallback: AppTypography.fallbacks),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_isDownloading)
                        GestureDetector(
                          onTap: _cancelDownload,
                          child: const Padding(
                            padding: EdgeInsetsDirectional.only(start: 8),
                            child: Text('إلغاء',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700)),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () =>
                              setState(() => _downloadStatus = ''),
                          child: const Padding(
                            padding: EdgeInsetsDirectional.only(start: 8),
                            child: Icon(Icons.close_rounded,
                                size: 14, color: AppColors.textMuted),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

          Expanded(
            child: widget.importedFiles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.video_library_outlined, size: 36, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        const Text(
                          'استورد فيديو لتبدأ المونتاج',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontFamilyFallback: AppTypography.fallbacks),
                        ),
                        const SizedBox(height: 12),
                        IOSButton(
                          label: 'استيراد فيديو',
                          icon: Icons.add_rounded,
                          fontSize: 12,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          onPressed: _importLocalVideo,
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: widget.importedFiles.length,
                    itemBuilder: (context, index) {
                      final file = widget.importedFiles[index];
                      return Draggable<String>(
                        data: file.path,
                        // Anchor the feedback under the POINTER (not the
                        // child's grab offset) so the drop position delivered
                        // to timeline targets is exactly where the finger is.
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        onDragStarted: () {
                          debugPrint('[DnD] DRAG STARTED — data="${file.path}"');
                        },
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 140,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: const Center(child: Icon(Icons.add_circle_outline, size: 24, color: Colors.white)),
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.3, child: _buildMediaCard(file, index)),
                        child: _buildMediaCard(file, index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Duration pill that heals itself: when the stored duration is unknown
/// (<= 0) it probes the file once via FFmpeg instead of displaying 00:00.
class _DurationBadge extends StatefulWidget {
  final String path;
  final double initialSeconds;
  const _DurationBadge({required this.path, required this.initialSeconds});

  @override
  State<_DurationBadge> createState() => _DurationBadgeState();
}

class _DurationBadgeState extends State<_DurationBadge> {
  late double _seconds;
  bool _probing = false;

  @override
  void initState() {
    super.initState();
    _seconds = widget.initialSeconds;
    if (_seconds <= 0) _resolve();
  }

  @override
  void didUpdateWidget(covariant _DurationBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.path != oldWidget.path) {
      _seconds = widget.initialSeconds;
      _probing = false;
      if (_seconds <= 0) _resolve();
    } else if (widget.initialSeconds > 0 && _seconds <= 0) {
      setState(() => _seconds = widget.initialSeconds);
    }
  }

  Future<void> _resolve() async {
    if (_probing) return;
    _probing = true;
    try {
      final d = await FfmpegService.probeDuration(widget.path);
      if (mounted && d != null && d > 0) setState(() => _seconds = d);
    } catch (_) {}
    _probing = false;
  }

  static String _fmt(double seconds) {
    if (seconds <= 0) return '…';
    final total = seconds.floor();
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        _fmt(_seconds),
        style: const TextStyle(fontSize: 9, color: Colors.white, fontFamilyFallback: AppTypography.fallbacks),
      ),
    );
  }
}
