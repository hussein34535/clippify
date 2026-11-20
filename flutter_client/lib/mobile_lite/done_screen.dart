import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/backend/backend_service.dart';
import '../features/mobile/save_helpers.dart';
import '../features/results/rendered_clip.dart';
import 'studio_theme.dart';

class LiteDoneScreen extends StatefulWidget {
  const LiteDoneScreen({
    super.key,
    required this.clips,
    required this.onRestart,
    this.localBaseUrl,
    this.bridgeBaseUrl,
    this.previewBuilder,
  });

  final List<RenderedClipData> clips;
  final VoidCallback onRestart;
  final String? localBaseUrl;
  final String? bridgeBaseUrl;
  final Widget Function(Uri source)? previewBuilder;

  @override
  State<LiteDoneScreen> createState() => _LiteDoneScreenState();
}

class _LiteDoneScreenState extends State<LiteDoneScreen> {
  final _downloadCancellation = CancelToken();
  Directory? _downloadDirectory;
  Future<File>? _download;
  String? _notice;
  bool _busy = false;

  bool get _desktop => widget.localBaseUrl != null;

  Uri _assetUri(RenderedClipData clip) => liteOutputUri(
    Uri.parse(
      widget.localBaseUrl ??
          widget.bridgeBaseUrl ??
          BackendService.currentBaseUrl(),
    ),
    clip.fileUrl,
    local: _desktop || widget.bridgeBaseUrl != null,
  );

  Future<File> _getFile(Uri source) async {
    try {
      return await (_download ??= _downloadFile(source));
    } catch (_) {
      _download = null;
      rethrow;
    }
  }

  Future<File> _downloadFile(Uri source) async {
    final directory = _downloadDirectory ??= await Directory.systemTemp
        .createTemp('clippify_reel_');
    final file = File(p.join(directory.path, 'Clippify-reel.mp4'));
    if (_downloadCancellation.isCancelled) {
      await _deleteDownload(directory);
      throw StateError('Download was cancelled');
    }
    final client = Dio();
    try {
      await client.downloadUri(
        source,
        file.path,
        cancelToken: _downloadCancellation,
        options: Options(
          followRedirects: !_desktop && widget.bridgeBaseUrl == null,
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      if (await file.length() == 0) throw StateError('Empty reel');
      return file;
    } finally {
      client.close();
    }
  }

  Future<void> _save(Uri source) => _perform(() async {
    if (_desktop) {
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ الريل',
        fileName: 'Clippify-reel.mp4',
        type: FileType.custom,
        allowedExtensions: const ['mp4'],
      );
      if (!mounted || destination == null) return null;
      await (await _getFile(source)).copy(destination);
      return 'اتحفظ الريل.';
    }
    final file = await _getFile(source);
    if (!mounted) return null;
    if (!await saveToGallery(file.path)) {
      return 'تعذّر الحفظ. راجع صلاحية الوصول للصور والفيديوهات.';
    }
    return 'اتحفظ الريل في الاستوديو.';
  }, failure: 'تعذّر تنزيل الريل للحفظ. جرّب تاني.');

  Future<void> _share(Uri source, Rect origin) => _perform(() async {
    final file = await _getFile(source);
    if (!mounted) return null;
    await Share.shareXFiles([XFile(file.path)], sharePositionOrigin: origin);
    return null;
  }, failure: 'تعذّرت مشاركة الريل. جرّب تاني.');

  Future<void> _perform(
    Future<String?> Function() action, {
    required String failure,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    String? notice;
    try {
      notice = await action();
    } catch (_) {
      notice = failure;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = notice;
    });
  }

  @override
  void dispose() {
    _downloadCancellation.cancel();
    final download = _download;
    final directory = _downloadDirectory;
    if (directory != null) {
      unawaited(() async {
        try {
          await download;
        } catch (_) {}
        await _deleteDownload(directory);
      }());
    }
    super.dispose();
  }

  Future<void> _deleteDownload(Directory directory) async {
    try {
      final file = File(p.join(directory.path, 'Clippify-reel.mp4'));
      if (await file.exists()) await file.delete();
      await directory.delete();
    } on FileSystemException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clip = widget.clips.firstOrNull;
    Uri? source;
    if (clip != null) {
      try {
        source = _assetUri(clip);
      } on FormatException {
        source = null;
      }
    }
    final playable = source;
    return Scaffold(
      appBar: AppBar(
        title: const Text('استوديو الريلز'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _busy ? null : widget.onRestart,
            child: const Text('فيديو جديد'),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: StudioLayout(
        footer: playable == null
            ? FilledButton(
                onPressed: widget.onRestart,
                child: const Text('اختار فيديو تاني'),
              )
            : _actions(playable),
        children: [
          if (playable == null || clip == null)
            const StudioProgress(
              title: 'الريل مش متاح',
              detail:
                  'النتيجة ما فيهاش رابط فيديو صالح. اختار فيديو وحاول تاني.',
              icon: Icons.movie_creation_outlined,
              failed: true,
            )
          else ...[
            Text(
              'الريل جاهز',
              style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${clip.durationSec.round()} ثانية  ·  فيديو عمودي'
              '${clip.hasCaptions == false ? '  ·  من غير كابشن' : ''}',
              style: text.bodySmall?.copyWith(color: studioMuted),
            ),
            const SizedBox(height: 16),
            Align(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: (MediaQuery.sizeOf(context).height * 0.54 * 9 / 16)
                      .clamp(148.0, 290.0),
                ),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child:
                        widget.previewBuilder?.call(playable) ??
                        _ReelPreview(source: playable),
                  ),
                ),
              ),
            ),
            if (clip.hookText.trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                clip.hookText,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
            ],
            if (clip.director case final director?) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('قرارات المخرج الذكي'),
                subtitle: Text(director.purpose),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('فهم المشهد', style: text.titleSmall),
                  Text(director.understanding),
                  const SizedBox(height: 8),
                  Text('خطة المونتاج', style: text.titleSmall),
                  Text(director.strategy),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _actions(Uri source) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(_notice!, textAlign: TextAlign.center),
          ),
        ),
      FilledButton.icon(
        onPressed: _busy ? null : () => _save(source),
        icon: const Icon(Icons.download_rounded),
        label: Text(_busy ? 'بنجهّز الملف…' : 'احفظ الفيديو'),
      ),
      if (!_desktop) ...[
        const SizedBox(height: 8),
        Builder(
          builder: (buttonContext) => OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () {
                    final box = buttonContext.findRenderObject()! as RenderBox;
                    _share(source, box.localToGlobal(Offset.zero) & box.size);
                  },
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('شارك الريل'),
          ),
        ),
      ],
    ],
  );
}

@visibleForTesting
Uri liteOutputUri(Uri base, String raw, {required bool local}) {
  final link = Uri.parse(raw.trim().replaceAll('\\', '/'));
  if (link.hasScheme &&
      !local &&
      (link.scheme == 'https' || link.scheme == 'http') &&
      link.host.isNotEmpty &&
      link.userInfo.isEmpty) {
    return link;
  }
  final segments = link.pathSegments;
  if (link.hasScheme ||
      link.hasAuthority ||
      segments.isEmpty ||
      segments.any((part) => part == '..' || part == '.')) {
    throw const FormatException('Invalid reel URL');
  }
  final path = switch (segments) {
    ['api', 'files', ...] ||
    ['files', ...] => link.path.startsWith('/') ? link.path : '/${link.path}',
    ['output', ...] =>
      '/api/files/${link.path.replaceFirst(RegExp(r'^/'), '')}',
    _ => throw const FormatException('Unknown reel path'),
  };
  return base.replace(path: path, query: link.hasQuery ? link.query : null);
}

class _ReelPreview extends StatefulWidget {
  const _ReelPreview({required this.source});

  final Uri source;

  @override
  State<_ReelPreview> createState() => _ReelPreviewState();
}

class _ReelPreviewState extends State<_ReelPreview> {
  Player? _player;
  VideoController? _controller;
  StreamSubscription<String>? _errors;
  bool _loading = false;
  bool _failed = false;

  Future<void> _play() async {
    if (_loading) return;
    setState(() {
      _failed = false;
      _loading = true;
    });
    try {
      await _errors?.cancel();
      await _player?.dispose();
      if (!mounted) return;
      MediaKit.ensureInitialized();
      final player = _player = Player();
      _errors = player.stream.error.listen((_) {
        if (mounted) setState(() => _failed = true);
      });
      final controller = VideoController(player);
      setState(() => _controller = controller);
      await player
          .open(Media(widget.source.toString()))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    unawaited(_errors?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null && !_failed) {
      return Video(controller: controller, fit: BoxFit.contain);
    }
    return ColoredBox(
      color: const Color(0xFF211B30),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: TextButton.icon(
            onPressed: _loading ? null : _play,
            icon: Icon(
              _failed
                  ? Icons.refresh_rounded
                  : Icons.play_circle_outline_rounded,
            ),
            label: Text(
              _failed
                  ? 'أعد المعاينة'
                  : _loading
                  ? 'بنفتح الفيديو…'
                  : 'شغّل المعاينة',
            ),
          ),
        ),
      ),
    );
  }
}
