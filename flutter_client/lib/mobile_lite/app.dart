import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/results/rendered_clip.dart';
import 'done_screen.dart';
import 'flow_screen.dart';
import 'models.dart';
import 'run_screen.dart';
import 'short_provider_settings.dart';
import 'short_sidecar.dart';
import 'studio_theme.dart';

const _usbBridgeUrl = String.fromEnvironment('CLIPPIFY_ANDROID_BRIDGE_URL');

/// نسخة الموبايل المستقلة: مساعد يسأل 4 أسئلة وينفذ المونتاج كله لوحده.
///
/// التشغيل: `flutter run -t lib/mobile_lite_main.dart`
/// (أو build apk/ipa بنفس الـ target).
class MobileLiteApp extends StatelessWidget {
  const MobileLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clippify',
      debugShowCheckedModeBanner: false,
      theme: studioTheme(ThemeData.dark(useMaterial3: true)),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const LiteWorkspace(),
    );
  }
}

class LiteWorkspace extends StatefulWidget {
  const LiteWorkspace({super.key, this.sidecar});

  final ShortSidecar? sidecar;

  @override
  State<LiteWorkspace> createState() => _LiteWorkspaceState();
}

class _LiteWorkspaceState extends State<LiteWorkspace> {
  late final _sidecar = widget.sidecar ?? ShortSidecar();
  int _runId = 0;
  LiteAnswers? _answers;
  String? _videoPath;
  List<RenderedClipData>? _clips;
  String? _localBase;

  String? get _mobileBridge {
    if (!kDebugMode || !Platform.isAndroid || _usbBridgeUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(_usbBridgeUrl);
    if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1' ||
        !uri.hasPort || uri.userInfo.isNotEmpty || uri.hasQuery ||
        uri.hasFragment || uri.path.isNotEmpty) {
      return null;
    }
    return uri.origin;
  }

  Future<String> _startEngine() async {
    final url = await _sidecar.start();
    _localBase = url;
    return url;
  }

  Future<void> _restart() async {
    await _sidecar.stop().catchError((Object _) {});
    if (!mounted) return;
    setState(() {
      _runId++;
      _answers = null;
      _videoPath = null;
      _clips = null;
      _localBase = null;
    });
  }

  @override
  void dispose() {
    unawaited(_sidecar.stop().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_clips != null) {
      return LiteDoneScreen(
        key: ValueKey('done_$_runId'),
        clips: _clips!,
        onRestart: _restart,
        localBaseUrl: _localBase,
        bridgeBaseUrl: _mobileBridge,
      );
    }
    if (_answers != null && _videoPath != null) {
      return LiteRunScreen(
        key: ValueKey('run_$_runId'),
        answers: _answers!,
        localVideoPath: _videoPath!,
        onDone: (clips) => setState(() => _clips = clips),
        startLocalEngine: Platform.isWindows ? _startEngine : null,
        bridgeBaseUrl: _mobileBridge,
        onBack: _restart,
      );
    }
    return LiteFlowScreen(
      key: ValueKey('flow_$_runId'),
      uploadsVideo: !Platform.isWindows,
      supportsAiDirector: Platform.isWindows || _mobileBridge != null,
      onProviderSettings: Platform.isWindows
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ShortProviderSettingsScreen(),
              ),
            )
          : null,
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
