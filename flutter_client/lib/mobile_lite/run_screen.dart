import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/backend/auto_edit_api.dart';
import '../core/backend/backend_service.dart';
import '../features/mobile/wizard_mobile_page.dart' show answersFromMap;
import '../features/results/rendered_clip.dart';
import '../features/wizard/auto_edit_progress_screen.dart';
import 'models.dart';
import 'studio_theme.dart';

/// تشغيل المهمة: فحص الاتصال → رفع الفيديو → بدء الجلسة → شاشة التقدم.
///
/// الهاتف لا يستطيع إعطاء مسار محلي للسيرفر — الرفع عبر POST /api/upload
/// إلزامي قبل start (انظر engine/src/api/files.rs).
///
/// الحقن الثلاثي ([checkHealth]/[uploadFile]/[apiFactory]) للاختبارات —
/// الافتراضي هو التنفيذ الحقيقي.
class LiteRunScreen extends StatefulWidget {
  final LiteAnswers answers;
  final String localVideoPath;
  final void Function(List<RenderedClipData> clips) onDone;
  final Future<bool> Function()? checkHealth;
  final Future<String?> Function(String localPath)? uploadFile;
  final AutoEditApi Function()? apiFactory;
  final Future<String> Function()? startLocalEngine;
  final String? bridgeBaseUrl;
  final VoidCallback? onBack;

  const LiteRunScreen({
    super.key,
    required this.answers,
    required this.localVideoPath,
    required this.onDone,
    this.checkHealth,
    this.uploadFile,
    this.apiFactory,
    this.startLocalEngine,
    this.bridgeBaseUrl,
    this.onBack,
  });

  @override
  State<LiteRunScreen> createState() => _LiteRunScreenState();
}

class _LiteRunScreenState extends State<LiteRunScreen> {
  String _status = 'بنتصل بخدمة المونتاج.';
  double? _uploadProgress;
  String? _error;
  bool _handedOff = false;
  bool _uploading = false;
  CancelToken? _uploadCancellation;

  String? _localBase;

  String get _base =>
      _localBase ?? widget.bridgeBaseUrl ?? BackendService.currentBaseUrl();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _uploadCancellation?.cancel();
    super.dispose();
  }

  Future<bool> _defaultCheckHealth() async {
    try {
      final r = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      ).get('$_base/api/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _defaultUpload(String localPath) async {
    final cancellation = _uploadCancellation = CancelToken();
    final name = localPath.split(RegExp(r'[\\/]')).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(localPath, filename: name),
    });
    final r = await Dio().post<Map<String, dynamic>>(
      '$_base/api/upload',
      data: form,
      cancelToken: cancellation,
      options: Options(
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 2),
      ),
      onSendProgress: (sent, total) {
        if (mounted && total > 0) {
          setState(() {
            _uploadProgress = (sent / total).clamp(0.0, 1.0);
          });
        }
      },
    );
    final data = r.data;
    final serverPath = data?['path'] as String?;
    if (data?['status'] == 'ok' &&
        serverPath != null &&
        serverPath.isNotEmpty) {
      return serverPath;
    }
    return null;
  }

  Future<void> _prepare() async {
    setState(() {
      _status = 'بنتصل بخدمة المونتاج.';
      _error = null;
      _handedOff = false;
      _uploading = false;
      _uploadProgress = null;
    });
    final startLocal = widget.startLocalEngine;
    if (startLocal != null) {
      try {
        _localBase = await startLocal();
      } catch (_) {
        if (mounted) {
          setState(
            () => _error =
                'تعذر تشغيل محرك Clippify المحلي. تأكد إن النسخة الحالية فيها المحرك.',
          );
        }
        return;
      }
    }
    if (!mounted) return;
    final healthy = await (widget.checkHealth ?? _defaultCheckHealth)();
    if (!healthy) {
      if (!mounted) return;
      setState(() {
        _error = startLocal == null
            ? widget.bridgeBaseUrl != null
                ? 'تعذر الوصول لمحرك المونتاج على الكمبيوتر. اتأكد إن اتصال ADB والمحرك شغالين.'
                : 'تعذر الوصول لخدمة المونتاج. اتأكد من الإنترنت وحاول تاني.'
            : 'المحرك المحلي غير متاح. حاول مرة أخرى.';
      });
      return;
    }
    final String? serverPath;
    try {
      if (startLocal == null) {
        setState(() {
          _uploading = true;
          _status = 'خليك في التطبيق لحد ما رفع الفيديو يخلص.';
        });
      }
      serverPath = startLocal != null
          ? File(widget.localVideoPath).absolute.path
          : await (widget.uploadFile ?? _defaultUpload)(widget.localVideoPath);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = e is DioException && e.response?.statusCode == 413
            ? 'حجم الفيديو أكبر من الحد المسموح. جرّب فيديو أصغر.'
            : 'فشل رفع الفيديو. اتأكد من الاتصال وحاول تاني.',
      );
      return;
    }
    if (serverPath == null || !mounted) {
      if (mounted) setState(() => _error = 'فشل رفع الفيديو.');
      return;
    }
    setState(() {
      _status = 'بنبعَت طلب المونتاج.';
      _uploading = false;
    });
    final api =
        widget.apiFactory?.call() ??
        (_localBase == null && widget.bridgeBaseUrl == null
            ? defaultAutoEditApi()
            : AutoEditApi(baseUrl: _base, allowWsOverride: false));
    final payload = liteAnswersToMap(widget.answers);
    if (startLocal == null && widget.bridgeBaseUrl == null) {
      payload.remove('mode');
    }
    final answers = answersFromMap(payload);
    final String? sid;
    try {
      sid = await api.start(serverPath, answers);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر بدء المونتاج. حاول مجددًا.');
      return;
    }
    if (!mounted) {
      if (sid != null) await api.cancel(sid);
      return;
    }
    if (sid == null) {
      setState(() => _error = 'تعذر بدء المونتاج. حاول مجددًا.');
      return;
    }
    setState(() => _handedOff = true);
    final navigator = Navigator.of(context);
    var completed = false;
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => AutoEditProgressScreen(
          sessionId: sid!,
          videoPath: serverPath!,
          answers: answers,
          api: api,
          studioMode: true,
          onDone: (clips) {
            if (!mounted) return;
            final playable = clips
                .where((clip) => clip.fileUrl.isNotEmpty)
                .toList();
            completed = true;
            navigator.pop();
            if (playable.length == 1) {
              widget.onDone(playable);
            } else {
              setState(
                () => _error = 'المحرك ما رجّعش مقطع واحد قابل للتشغيل.',
              );
            }
          },
        ),
      ),
    );
    if (mounted && !completed) widget.onBack?.call();
  }

  @override
  Widget build(BuildContext context) {
    final failed = _error != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('استوديو الريلز'),
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
      ),
      body: StudioLayout(
        footer: failed
            ? FilledButton(
                onPressed: _prepare,
                child: const Text('حاول مجددًا'),
              )
            : null,
        children: [
          StudioProgress(
            title: failed
                ? 'المونتاج ما بدأش'
                : _uploading
                ? 'بنرفع الفيديو'
                : 'بنجهّز المونتاج',
            detail: _error ?? _status,
            icon: failed
                ? Icons.cloud_off_outlined
                : _uploading
                ? Icons.cloud_upload_outlined
                : Icons.movie_filter_outlined,
            progress: _handedOff
                ? 0
                : _uploading
                ? _uploadProgress
                : null,
            failed: failed,
          ),
        ],
      ),
    );
  }
}
