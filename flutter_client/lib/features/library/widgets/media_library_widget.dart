import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

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

  const MediaLibraryWidget({
    super.key,
    required this.onSelectVideo,
    required this.importedFiles,
    required this.onFileAdded,
    this.onFileRemoved,
  });

  @override
  ConsumerState<MediaLibraryWidget> createState() => _MediaLibraryWidgetState();
}

class _MediaLibraryWidgetState extends ConsumerState<MediaLibraryWidget> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

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

  String _formatDuration(double seconds) {
    if (seconds <= 0) return '00:00';
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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
      _downloadProgress = 0.0;
      _downloadStatus = 'بدء معالجة رابط يوتيوب...';
    });

    final apiClient = ApiClient();
    final downloadResult = await apiClient.downloadYoutube(url);

    switch (downloadResult) {
      case Success(data: final sessionId):
        _pollDownloadStatus(sessionId);
      case Failure():
        setState(() {
          _isDownloading = false;
          _downloadStatus = 'فشل بدء التحميل. تأكد من اتصالك بالإنترنت والباك إند.';
        });
    }
  }

  void _pollDownloadStatus(String sessionId) async {
    final apiClient = ApiClient();
    int failedAttempts = 0;

    while (_isDownloading) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      final statusData = await apiClient.getSessionStatus(sessionId);
      switch (statusData) {
        case Success(data: final data):
          failedAttempts = 0;
          final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
          final status = data['status'] as String? ?? '';
          final results = data['results'] as List<dynamic>? ?? [];
          final errors = data['errors'] as List<dynamic>? ?? [];

          setState(() {
            _downloadProgress = progress;
            _downloadStatus = status;
          });

          if (status.toLowerCase() == 'done' && results.isNotEmpty) {
            final videoPath = results.first as String;
            final name = videoPath.split('/').last.split('\\').last;

            setState(() {
              _isDownloading = false;
            });

            final apiClient = ApiClient();
            final mediaInfo = await apiClient.getMediaInfo(videoPath);

            double duration = 0.0;
            String? thumbPath;

            switch (mediaInfo) {
              case Success(data: final mi):
                if (mi['status'] == 'success') {
                  duration = (mi['duration'] as num?)?.toDouble() ?? 0.0;
                  thumbPath = mi['thumbnail_path'] as String?;
                } else {
                  thumbPath = await _generateThumbnail(videoPath);
                  duration = await _getVideoDuration(videoPath);
                }
              case Failure():
                thumbPath = await _generateThumbnail(videoPath);
                duration = await _getVideoDuration(videoPath);
            }

            final media = MediaFile(path: videoPath, name: name, isYoutube: true, thumbnailPath: thumbPath, duration: duration);
            widget.onFileAdded(media);
            widget.onSelectVideo(videoPath);
            return;
          }

          if (status.toLowerCase() == 'failed' || errors.isNotEmpty) {
            setState(() {
              _isDownloading = false;
              _downloadStatus = 'فشل التحميل: ${errors.isNotEmpty ? errors.join(', ') : 'خطأ غير معروف'}';
            });
            return;
          }
        case Failure():
          failedAttempts++;
          if (failedAttempts > 10) {
            setState(() {
              _isDownloading = false;
              _downloadStatus = 'انقطع الاتصال بالخادم أثناء التحميل.';
            });
            return;
          }
      }
    }
  }

  Future<void> _showYoutubeDialog() async {
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('تحميل من يوتيوب', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: 'أدخل رابط فيديو يوتيوب...',
              filled: true,
              fillColor: AppColors.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.destructive),
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
    final isAudio = file.path.toLowerCase().endsWith('.mp3') || file.path.toLowerCase().endsWith('.wav');
    
    return GestureDetector(
      onTap: () => widget.onSelectVideo(file.path),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
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
                              ? [const Color(0xFF1c1c1e), const Color(0xFF2c2c2e)]
                              : file.isYoutube
                                  ? [const Color(0xFFcc0000), const Color(0xFF990000)]
                                  : [const Color(0xFF4c3db5), const Color(0xFF6b5ce7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          isAudio ? Icons.music_note_rounded : (file.isYoutube ? Icons.play_circle_fill_rounded : Icons.videocam_rounded),
                          size: 32,
                          color: isAudio ? Colors.greenAccent : Colors.white.withValues(alpha: 0.85),
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
                    colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Text(
                  file.name,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

            // Duration (bottom right)
            Positioned(
              bottom: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(file.duration),
                  style: const TextStyle(fontSize: 9, color: Colors.white),
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
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان اللوحة
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'مكتبة الوسائط',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // قائمة الملفات + رأس الأدوات
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'الملفات المستوردة',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                  ),
                ),
                Tooltip(
                  message: 'إضافة فيديو من الجهاز',
                  child: InkWell(
                    onTap: _isDownloading ? null : _importLocalVideo,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.add_rounded, size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'تحميل من يوتيوب',
                  child: InkWell(
                    onTap: _isDownloading ? null : _showYoutubeDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.play_circle_outline, size: 16, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ملفات التحميل من يوتيوب (تقدم)
          if (_isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: AppColors.card,
                    minHeight: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _downloadStatus,
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

          Expanded(
            child: widget.importedFiles.isEmpty
                ? const Center(
                    child: Text(
                      'اضغط + لإضافة ملفات',
                      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 140,
                            height: 100,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7c6af7).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
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
