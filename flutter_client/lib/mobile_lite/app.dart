import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/results/rendered_clip.dart';
import 'done_screen.dart';
import 'flow_screen.dart';
import 'models.dart';
import 'run_screen.dart';

/// نسخة الموبايل المستقلة: مساعد يسأل 4 أسئلة وينفذ المونتاج كله لوحده.
///
/// التشغيل: `flutter run -t lib/mobile_lite_main.dart`
/// (أو build apk/ipa بنفس الـ target).
class MobileLiteApp extends StatelessWidget {
  const MobileLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مساعد Clippify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0A84FF),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const _LiteRoot(),
    );
  }
}

class _LiteRoot extends StatefulWidget {
  const _LiteRoot();

  @override
  State<_LiteRoot> createState() => _LiteRootState();
}

class _LiteRootState extends State<_LiteRoot> {
  int _runId = 0;
  LiteAnswers? _answers;
  String? _videoPath;
  List<RenderedClipData>? _clips;

  void _restart() => setState(() {
        _runId++;
        _answers = null;
        _videoPath = null;
        _clips = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_clips != null) {
      return LiteDoneScreen(
        key: ValueKey('done_$_runId'),
        clips: _clips!,
        onRestart: _restart,
      );
    }
    if (_answers != null && _videoPath != null) {
      return LiteRunScreen(
        key: ValueKey('run_$_runId'),
        answers: _answers!,
        localVideoPath: _videoPath!,
        onDone: (clips) => setState(() => _clips = clips),
      );
    }
    return LiteFlowScreen(
      key: ValueKey('flow_$_runId'),
      onReady: (answers, videoPath) => setState(() {
        _answers = answers;
        _videoPath = videoPath;
      }),
    );
  }
}

/// يلفّ التطبيق بـ ProviderScope (شاشة التقدم المعاد استخدامها تحتاجه).
class MobileLiteScope extends StatelessWidget {
  const MobileLiteScope({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: MobileLiteApp());
  }
}
