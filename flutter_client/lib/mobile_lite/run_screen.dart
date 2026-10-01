import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/backend/auto_edit_api.dart';
import '../../core/backend/backend_service.dart';
import '../../features/mobile/wizard_mobile_page.dart' show answersFromMap;
import '../../features/results/rendered_clip.dart';
import '../../features/wizard/auto_edit_progress_screen.dart';
import 'models.dart';

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

  const LiteRunScreen({
    super.key,
    required this.answers,
    required this.localVideoPath,
    required this.onDone,
    this.checkHealth,
    this.uploadFile,
    this.apiFactory,
  });

  @override
  State<LiteRunScreen> createState() => _LiteRunScreenState();
}

class _LiteRunScreenState extends State<LiteRunScreen> {
  String _status = 'بنجهز...';
  double _progress = 0.0;
  String? _error;

  String get _base => BackendService.currentBaseUrl();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<bool> _defaultCheckHealth() async {
    try {
      final r = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
      )).get('$_base/api/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _defaultUpload(String localPath) async {
    final name = localPath.split(RegExp(r'[\\/]')).last;
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(localPath, filename: name),
    });
    final r = await Dio().post<Map<String, dynamic>>(
      '$_base/api/upload',
      data: form,
      options: Options(
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(minutes: 2),
      ),
      onSendProgress: (sent, total) {
        if (mounted && total > 0) {
          setState(() {
            _progress = 0.1 + 0.5 * sent / total;
            _status = 'بنرفع الفيديو... ${(_progress * 100).round()}%';
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
      _status = 'بنتصل بالخدمة...';
      _error = null;
    });
    final healthy = await (widget.checkHealth ?? _defaultCheckHealth)();
    if (!healthy) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر الوصول لخدمة المونتاج.\n'
            'تأكد من الإنترنت أو من إعدادات الاتصال في النسخة الكاملة.';
      });
      return;
    }
    String? serverPath;
    try {
      serverPath = await (widget.uploadFile ?? _defaultUpload)(
          widget.localVideoPath);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'فشل الرفع: $e');
      return;
    }
    if (serverPath == null || !mounted) {
      if (mounted) setState(() => _error = 'فشل رفع الفيديو.');
      return;
    }
    setState(() {
      _status = 'بنبدأ المونتاج...';
      _progress = 0.65;
    });
    final api = (widget.apiFactory ?? defaultAutoEditApi)();
    final answers =
        answersFromMap(liteAnswersToMap(widget.answers));
    String? sid;
    try {
      sid = await api.start(serverPath, answers);
    } catch (_) {
      sid = null;
    }
    if (sid == null || !mounted) {
      if (mounted) setState(() => _error = 'تعذر بدء الجلسة — حاول مجددًا.');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => AutoEditProgressScreen(
        sessionId: sid!,
        videoPath: serverPath!,
        answers: answers,
        api: api,
        onDone: widget.onDone,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('شغالين عليه')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 56),
                    const SizedBox(height: 16),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _prepare,
                      child: const Text('حاول مجددًا'),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    LinearProgressIndicator(value: _progress),
                    const SizedBox(height: 12),
                    Text(_status),
                  ],
                ),
        ),
      ),
    );
  }
}
