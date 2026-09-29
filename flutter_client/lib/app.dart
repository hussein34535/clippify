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
                  : const HomeScreen();
            },
          ),
        ),
      ),
    );
  }
}
