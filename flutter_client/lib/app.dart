import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'launch/backend_controller.dart';
import 'features/home/screens/home_screen.dart';
// MOBILE-SHELL-SWITCH imports
import 'features/shell/mobile_home_shell.dart';
import 'mobile_lite/app.dart';
import 'mobile_lite/short_sidecar.dart';
import 'shared/widgets/toast_overlay.dart';
import 'shared/providers/theme_provider.dart';
// L10N-PLUMBING (additive): locale provider + supported locales below.
import 'shared/l10n/locale_provider.dart';
import 'features/ui/edge_ui.dart';

class ClippifyApp extends ConsumerStatefulWidget {
  const ClippifyApp({super.key});

  @override
  ConsumerState<ClippifyApp> createState() => _ClippifyAppState();
}

class _ClippifyAppState extends ConsumerState<ClippifyApp> with WindowListener {
  final _shortSidecar = ShortSidecar();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await _shortSidecar.stop().catchError((Object _) {});
    await BackendController().stopBackend();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ref.watch(resolvedThemeProvider);
    final prefs    = ref.watch(appPrefsProvider);
    // L10N-PLUMBING (additive): watching here makes the whole tree rebuild
    // when the language changes; strings themselves come from context.l10n.
    final lang     = ref.watch(localeProvider);

    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(prefs.fontScale)),
      child: MaterialApp(
        title: 'Clippify Pro',
        debugShowCheckedModeBanner: false,
        locale: lang.resolved,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: appTheme.copyWith(
          scaffoldBackgroundColor: EdgeTheme.canvas,
          // TOKENS-FONT begin — premium Arabic typography with safe fallbacks
          // (fallback chain stops metric jumps when a glyph is missing)
          textTheme: appTheme.textTheme.apply(
            fontFamily: 'Cairo',
            fontFamilyFallback: const ['Rubik', 'Segoe UI', 'Arial'],
          ),
          // TOKENS-FONT end
          colorScheme: appTheme.colorScheme.copyWith(
            surface: EdgeTheme.panelBg,
          ),
          appBarTheme: appTheme.appBarTheme.copyWith(
            backgroundColor: EdgeTheme.menuBar,
          ),
          dividerColor: EdgeTheme.divider,
        ),
        home: ToastOverlay(
          // MOBILE-SHELL-SWITCH v2 — platform-decided, NOT width-decided:
          // a narrow DESKTOP window must never flip the whole UI to the mobile
          // shell (that felt like "things disappearing"). Touch platforms get
          // the 4-tab shell; Windows/macOS/Linux always get the full NLE.
          child: Builder(
            builder: (_) {
              final isTouchPlatform =
                  !kIsWeb && (Platform.isAndroid || Platform.isIOS);
              return isTouchPlatform
                  ? const MobileHomeShell()
                  : !kIsWeb && Platform.isWindows
                      ? _WorkflowPicker(shortSidecar: _shortSidecar)
                      : const HomeScreen();
            },
          ),
        ),
      ),
    );
  }
}

class _WorkflowPicker extends StatefulWidget {
  const _WorkflowPicker({required this.shortSidecar});

  final ShortSidecar shortSidecar;

  @override
  State<_WorkflowPicker> createState() => _WorkflowPickerState();
}

class _WorkflowPickerState extends State<_WorkflowPicker> {
  bool _openingEditor = false;

  Future<void> _openLongEditor() async {
    setState(() => _openingEditor = true);
    try {
      await BackendController().startBackend();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } finally {
      if (mounted) setState(() => _openingEditor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Clippify', style: theme.textTheme.headlineLarge),
                const SizedBox(height: 12),
                Text('اختار طريقة المونتاج', style: theme.textTheme.titleMedium),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _openingEditor
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LiteWorkspace(sidecar: widget.shortSidecar),
                            ),
                          ),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: const Text('فيديو قصير تلقائي'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openingEditor ? null : _openLongEditor,
                  icon: const Icon(Icons.video_library_outlined),
                  label: Text(_openingEditor ? 'بنفتح المحرر…' : 'محرر الفيديوهات الطويلة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
