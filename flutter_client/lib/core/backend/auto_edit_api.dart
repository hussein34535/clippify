import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'backend_service.dart' show service;

/// عقود docs/CONTRACTS.md — قسم Auto-Edit.

class AutoEditAnswers {
  final String contentType;
  final String platform;
  final int nClips;
  final double clipDurationSec;
  final String? captionTheme;
  final bool music;
  final bool broll;
  final bool translateArabic;
  final String customInstructions;

  const AutoEditAnswers({
    this.contentType = 'auto',
    this.platform = 'tiktok',
    this.nClips = 5,
    this.clipDurationSec = 60,
    this.captionTheme,
    this.music = false,
    this.broll = true,
    this.translateArabic = false,
    this.customInstructions = '',
  });

  Map<String, dynamic> toJson() => {
        'content_type': contentType,
        'platform': platform,
        'n_clips': nClips,
        'clip_duration_sec': clipDurationSec,
        if (captionTheme != null) 'caption_theme': captionTheme,
        'music': music,
        'broll': broll,
        'translate_arabic': translateArabic,
        'custom_instructions': customInstructions,
      };
}

class AutoEditEvent {
  final String type; // progress | done | error
  final String stage;
  final double progress;
  final String messageAr;
  final String messageEn;
  final List<dynamic>? clipsJson;

  const AutoEditEvent({
    this.type = 'progress',
    this.stage = '',
    this.progress = 0,
    this.messageAr = '',
    this.messageEn = '',
    this.clipsJson,
  });
}

String buildWsUri(String httpBase) {
  String? override;
  try {
    override = dotenv.maybeGet('WS_BASE_URL');
  } catch (_) {
    override = null; // dotenv not initialized (tests) — fall through
  }
  if (override != null && override.isNotEmpty) return override;
  return httpBase
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
}

class AutoEditApi {
  final Dio _dio;
  final String _baseUrl;

  AutoEditApi({Dio? dio, String? baseUrl})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? service.baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(minutes: 5),
            )),
        _baseUrl = baseUrl ?? service.baseUrl;

  Future<String?> start(String videoPath, AutoEditAnswers answers) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/api/auto-edit', data: {
        'video_path': videoPath,
        'answers': answers.toJson(),
      });
      final sid = res.data?['session_id'];
      return sid is String && sid.isNotEmpty ? sid : null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        debugPrint('[AutoEditApi] quota_exceeded — انتهت الحصة، قم بالترقية');
      } else {
        debugPrint('[AutoEditApi] start failed: ${e.message}');
      }
      return null;
    } catch (e) {
      debugPrint('[AutoEditApi] start failed: $e');
      return null;
    }
  }

  /// WebSocket بثّ مباشر + إعادة اتصال x3 (1s/2s/4s) ثم حدث خطأ.
  Stream<AutoEditEvent> subscribeProgress(String sessionId) {
    late final StreamController<AutoEditEvent> controller;
    StreamSubscription<dynamic>? wsSub;
    WebSocket? ws;
    Timer? retryTimer;
    var attempts = 0;
    var disposed = false;

    void emitErrorAndClose(String ar, String en) {
      if (disposed || controller.isClosed) return;
      controller.add(AutoEditEvent(
        type: 'error',
        messageAr: ar,
        messageEn: en,
      ));
      controller.close();
    }

    late final void Function() scheduleRetry;

    Future<void> connect() async {
      if (disposed) return;
      try {
        ws = await WebSocket.connect(
            '${buildWsUri(_baseUrl)}/api/ws/progress/$sessionId');
        attempts = 0;
        wsSub = ws!.listen(
          (data) {
            if (disposed || controller.isClosed) return;
            try {
              controller.add(decodeEvent(data.toString()));
            } catch (e) {
              debugPrint('[AutoEditApi] bad frame: $e');
            }
          },
          onError: (Object e) => scheduleRetry(),
          onDone: () => scheduleRetry(),
          cancelOnError: true,
        );
      } catch (e) {
        debugPrint('[AutoEditApi] ws connect failed: $e');
        scheduleRetry();
      }
    }

    scheduleRetry = () {
      if (disposed) return;
      if (attempts >= 3) {
        emitErrorAndClose(
            'انقطع الاتصال بخادم المعالجة — أعد المحاولة لاحقاً',
            'Lost connection to the processing server — try again later');
        return;
      }
      final delay = Duration(seconds: 1 << attempts); // 1s, 2s, 4s
      attempts++;
      debugPrint('[AutoEditApi] ws retry #$attempts in ${delay.inSeconds}s');
      retryTimer = Timer(delay, connect);
    };

    controller = StreamController<AutoEditEvent>.broadcast(
      onListen: connect,
      onCancel: () {
        disposed = true;
        retryTimer?.cancel();
        wsSub?.cancel();
        ws?.close();
      },
    );
    return controller.stream;
  }

  /// يُستخدم داخلياً من subscribeProgress وقابل للاختبار منفصلاً.
  static AutoEditEvent decodeEvent(String raw) {
    final map = raw.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(raw) as Map).cast<String, dynamic>();
    switch (map['type']) {
      case 'done':
        final result =
            ((map['result'] as Map?) ?? const {}).cast<String, dynamic>();
        return AutoEditEvent(
          type: 'done',
          stage: 'done',
          progress: 100,
          messageAr: 'اكتمل التحرير',
          messageEn: 'Auto-edit finished',
          clipsJson: (result['clips'] as List?) ?? const [],
        );
      case 'error':
        final detail = (map['detail'] ?? 'خطأ غير معروف').toString();
        return AutoEditEvent(type: 'error', messageAr: detail, messageEn: detail);
      default:
        return AutoEditEvent(
          type: (map['type'] ?? 'progress').toString(),
          stage: (map['stage'] ?? '').toString(),
          progress: ((map['progress'] ?? 0) as num).toDouble(),
          messageAr: (map['message_ar'] ?? '').toString(),
          messageEn: (map['message_en'] ?? '').toString(),
        );
    }
  }

  /// Fallback polling — يعيد آخر رسالة بنفس شكل WS أو null عند الفشل.
  Future<Map<String, dynamic>?> status(String sessionId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
          '/api/auto-edit/status/$sessionId');
      return res.data;
    } catch (e) {
      debugPrint('[AutoEditApi] status failed: $e');
      return null;
    }
  }

  Future<bool> cancel(String sessionId) async {
    try {
      await _dio.post('/api/auto-edit/cancel/$sessionId');
      return true;
    } catch (e) {
      debugPrint('[AutoEditApi] cancel failed: $e');
      return false;
    }
  }
}
