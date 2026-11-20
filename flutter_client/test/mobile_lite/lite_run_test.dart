import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_client/core/backend/auto_edit_api.dart';
import 'package:flutter_client/features/results/rendered_clip.dart';
import 'package:flutter_client/mobile_lite/models.dart';
import 'package:flutter_client/mobile_lite/run_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLiteApi implements AutoEditApi {
  final controller = StreamController<AutoEditEvent>.broadcast();
  int startCalls = 0;
  String? seenVideoPath;
  AutoEditAnswers? seenAnswers;
  Map<String, dynamic>? statusResult;
  bool _closed = false;

  @override
  Future<String?> start(String videoPath, AutoEditAnswers answers) async {
    startCalls++;
    seenVideoPath = videoPath;
    seenAnswers = answers;
    return 'sid-lite';
  }

  @override
  Stream<AutoEditEvent> subscribeProgress(String sessionId) =>
      controller.stream;

  @override
  Future<Map<String, dynamic>?> status(String sessionId) async =>
      statusResult;

  @override
  Future<bool> cancel(String sessionId) async => true;

  List<AutoEditQuestionAnswer>? submittedAnswers;

  @override
  Future<bool> answerQuestions(
    String sessionId,
    List<AutoEditQuestionAnswer> answers,
  ) async {
    submittedAnswers = answers;
    return true;
  }

  /// إغلاق آمن متكرر — الإغلاق الثاني لـ broadcast controller كان يعلّق
  /// الـ tearDown للأبد (سبب تعليق هذا الملف 10 دقائق).
  void dispose() {
    if (_closed) return;
    _closed = true;
    unawaited(controller.close());
  }

  Future<void> closeForTest() async {
    if (_closed) return;
    _closed = true;
    await controller.close();
  }
}

const _clipJson = {
  'index': 0,
  'file_url': 'output/sid-lite/clip_000.mp4',
  'viral_score': 0.88,
  'hook': {'text': 'هوك', 'start_sec': 0.5, 'end_sec': 2.0},
  'duration_sec': 30.0,
  'caption_theme': 'TikTok Yellow',
};

void main() {
  group('LiteRunScreen full loop (injected fakes)', () {
    testWidgets('Android debug bridge uploads then uses Short Auto', (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);
      String? uploaded;
      await tester.pumpWidget(
        MaterialApp(
          home: LiteRunScreen(
            answers: const LiteAnswers(),
            localVideoPath: '/sdcard/Download/source.mp4',
            onDone: (_) {},
            bridgeBaseUrl: 'http://127.0.0.1:8768',
            checkHealth: () async => true,
            uploadFile: (path) async {
              uploaded = path;
              return 'uploads/source.mp4';
            },
            apiFactory: () => api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(uploaded, '/sdcard/Download/source.mp4');
      expect(api.seenVideoPath, 'uploads/source.mp4');
      expect(api.seenAnswers?.mode, 'short_auto');
    });

    testWidgets('Windows workflow sends short mode with no upload', (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);
      var uploads = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: 'source.mp4',
              onDone: (_) {},
              checkHealth: () async => true,
              startLocalEngine: () async => 'http://127.0.0.1:8594',
              uploadFile: (_) async {
                uploads++;
                return null;
              },
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(uploads, 0);
      expect(api.seenVideoPath, endsWith('source.mp4'));
      expect(api.seenAnswers?.mode, 'short_auto');
      expect(api.seenAnswers?.nClips, 1);
    });

    testWidgets('health → upload → start → progress → onDone',
        (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);
      List<RenderedClipData>? done;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (clips) => done = clips,
              checkHealth: () async => true,
              uploadFile: (_) async => 'uploads/x.mp4',
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // الرفع تم بمسار الهاتف، والبدء تم بمسار السيرفر.
      expect(api.startCalls, 1);
      expect(api.seenVideoPath, 'uploads/x.mp4');
      expect(find.text('بنجهّز الريل'), findsOneWidget);

      api.controller.add(const AutoEditEvent(
          type: 'progress', progress: 0.5, messageAr: 'شغال'));
      await tester.pump();
      api.controller.add(
          const AutoEditEvent(type: 'done', progress: 1.0, clipsJson: [_clipJson]));
      await tester.pumpAndSettle();

      expect(done, hasLength(1));
      expect(done!.first.hookText, 'هوك');
      expect(done!.first.fileUrl, 'output/sid-lite/clip_000.mp4');
    });

    testWidgets('health failure shows honest error, no start', (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (_) {},
              checkHealth: () async => false,
              uploadFile: (_) async => 'uploads/x.mp4',
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.startCalls, 0);
      expect(find.textContaining('تعذر الوصول'), findsOneWidget);
    });

    testWidgets('null session shows retryable error', (tester) async {      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (_) {},
              checkHealth: () async => true,
              uploadFile: (_) async => null,
              apiFactory: () => _FakeLiteApi(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('فشل رفع'), findsOneWidget);
      expect(find.text('حاول مجددًا'), findsOneWidget);
    });

    testWidgets('answers the director questions before rendering',
        (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (_) {},
              checkHealth: () async => true,
              uploadFile: (_) async => 'uploads/x.mp4',
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      api.controller.add(
        const AutoEditEvent(
          type: 'questions',
          stage: 'selecting',
          progress: 64,
          questions: [
            AutoEditQuestion(
              id: 'q1',
              question: 'لمين الفيديو؟',
              options: [
                AutoEditQuestionOption(id: 'a', label: 'جمهور عام'),
                AutoEditQuestionOption(id: 'b', label: 'متابعيني'),
              ],
              recommended: 'b',
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('لمين الفيديو؟'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'متابعيني'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'متابعيني'));
      await tester.pump();
      await tester.ensureVisible(find.text('ابدأ المونتاج'));
      await tester.tap(find.text('ابدأ المونتاج'));
      await tester.pumpAndSettle();

      expect(api.submittedAnswers, hasLength(1));
      expect(api.submittedAnswers!.first.questionId, 'q1');
      expect(api.submittedAnswers!.first.optionId, 'b');
      expect(find.text('لمين الفيديو؟'), findsNothing);
    });

    testWidgets('skipping the questions resumes the render', (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (_) {},
              checkHealth: () async => true,
              uploadFile: (_) async => 'uploads/x.mp4',
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      api.controller.add(
        const AutoEditEvent(
          type: 'questions',
          questions: [
            AutoEditQuestion(
              id: 'q1',
              question: 'لمين الفيديو؟',
              options: [
                AutoEditQuestionOption(id: 'a', label: 'جمهور عام'),
                AutoEditQuestionOption(id: 'b', label: 'متابعيني'),
              ],
            ),
          ],
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('تخطَّ الأسئلة'));
      await tester.tap(find.text('تخطَّ الأسئلة'));
      await tester.pumpAndSettle();

      expect(api.submittedAnswers, isEmpty);
      expect(find.text('لمين الفيديو؟'), findsNothing);
    });

    testWidgets('closed stream without done recovers via status poll',
        (tester) async {
      final api = _FakeLiteApi();
      addTearDown(api.dispose);
      api.statusResult = {
        'status': 'done',
        'result': {
          'clips': [_clipJson],
        },
      };
      List<RenderedClipData>? done;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: LiteRunScreen(
              answers: const LiteAnswers(),
              localVideoPath: '/tmp/in.mp4',
              onDone: (clips) => done = clips,
              checkHealth: () async => true,
              uploadFile: (_) async => 'uploads/x.mp4',
              apiFactory: () => api,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.startCalls, 1);

      // البث يُغلق بلا حدث done (الحالة العالقة عند 100%) — الاستكمال
      // عبر polling يجب أن ينقل للنتيجة بدل التعليق.
      await api.closeForTest();
      await tester.pumpAndSettle();

      expect(done, hasLength(1));
      expect(done!.first.fileUrl, 'output/sid-lite/clip_000.mp4');
    });
  });
}
