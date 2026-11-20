import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'backend_service.dart' show service;

/// عقود docs/CONTRACTS.md — قسم Auto-Edit.

class AutoEditAnswers {
  final String? mode;
  final String? shortDirector;
  final String? editBrief;
  final String? zoomPolicy;
  final String? creativeStyle;
  final String? creativeTitle;
  final bool? creativeMusic;
  final bool? creativeEffects;
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
    this.mode,
    this.shortDirector,
    this.editBrief,
    this.zoomPolicy,
    this.creativeStyle,
    this.creativeTitle,
    this.creativeMusic,
    this.creativeEffects,
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
        if (mode != null) 'mode': mode,
        if (shortDirector != null) 'short_director': shortDirector,
        if (editBrief != null && editBrief!.isNotEmpty) 'edit_brief': editBrief,
        if (zoomPolicy != null) 'zoom_policy': zoomPolicy,
        if (creativeStyle != null) 'creative_style': creativeStyle,
        if (creativeTitle != null) 'creative_title': creativeTitle,
        if (creativeMusic != null) 'creative_music': creativeMusic,
        if (creativeEffects != null) 'creative_effects': creativeEffects,
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

class AutoEditQuestionOption {
  final String id;
  final String label;

  const AutoEditQuestionOption({required this.id, required this.label});

  factory AutoEditQuestionOption.fromJson(Map<String, dynamic> json) =>
      AutoEditQuestionOption(
        id: (json['id'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
      );
}

class AutoEditQuestionAnswer {
  final String questionId;
  final String optionId;

  const AutoEditQuestionAnswer({
    required this.questionId,
    required this.optionId,
  });

  Map<String, dynamic> toJson() => {
    'question_id': questionId,
    'option_id': optionId,
  };
}

class AutoEditQuestion {
  final String id;
  final String question;
  final List<AutoEditQuestionOption> options;
  final String? recommended;

  const AutoEditQuestion({
    required this.id,
    required this.question,
    required this.options,
    this.recommended,
  });

  factory AutoEditQuestion.fromJson(Map<String, dynamic> json) =>
      AutoEditQuestion(
        id: (json['id'] ?? '').toString(),
        question: (json['question'] ?? '').toString(),
        options: (json['options'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (option) =>
                  AutoEditQuestionOption.fromJson(option.cast<String, dynamic>()),
            )
            .toList(),
        recommended: json['recommended']?.toString(),
      );
}

class AutoEditEvent {
  final String type; // progress | questions | done | error
  final String stage;
  final double progress;
  final String messageAr;
  final String messageEn;
  final List<dynamic>? clipsJson;
  final List<AutoEditQuestion>? questions;

  const AutoEditEvent({
    this.type = 'progress',
    this.stage = '',
    this.progress = 0,
    this.messageAr = '',
    this.messageEn = '',
    this.clipsJson,
    this.questions,
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
  final bool _allowWsOverride;

  AutoEditApi({Dio? dio, String? baseUrl, bool allowWsOverride = true})
      : _allowWsOverride = allowWsOverride,
        _dio = dio ??
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
        final baseUri = Uri.parse(_baseUrl);
        final endpoint = _allowWsOverride
            ? buildWsUri(_baseUrl)
            : baseUri.replace(scheme: baseUri.scheme == 'https' ? 'wss' : 'ws');
        final connected = await WebSocket.connect('$endpoint/api/ws/progress/$sessionId');
        if (disposed) {
          await connected.close();
          return;
        }
        ws = connected;
        wsSub = connected.listen(
          (data) {
            if (disposed || controller.isClosed) return;
            try {
              final event = decodeEvent(data.toString());
              controller.add(event);
              if (event.type == 'done' || event.type == 'error') {
                controller.close();
                ws?.close();
              }
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
      if (disposed || controller.isClosed || retryTimer?.isActive == true) return;
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
        return AutoEditEvent(
          type: 'error',
          messageAr: (map['message_ar'] ?? detail).toString(),
          messageEn: (map['message_en'] ?? detail).toString(),
        );
      case 'questions':
        return AutoEditEvent(
          type: 'questions',
          stage: (map['stage'] ?? 'selecting').toString(),
          progress: ((map['progress'] ?? 64) as num).toDouble(),
          messageAr: (map['message_ar'] ?? '').toString(),
          messageEn: (map['message_en'] ?? '').toString(),
          questions: (map['questions'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (question) =>
                    AutoEditQuestion.fromJson(question.cast<String, dynamic>()),
              )
              .toList(),
        );
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

  Future<bool> answerQuestions(
    String sessionId,
    List<AutoEditQuestionAnswer> answers,
  ) async {
    try {
      await _dio.post(
        '/api/auto-edit/questions/$sessionId',
        data: {'answers': answers.map((answer) => answer.toJson()).toList()},
      );
      return true;
    } catch (e) {
      debugPrint('[AutoEditApi] submit questions failed: $e');
      return false;
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
