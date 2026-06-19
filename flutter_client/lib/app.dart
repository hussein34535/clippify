import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'launch/backend_controller.dart';
import 'features/home/screens/home_screen.dart';
import 'shared/widgets/toast_overlay.dart';
import 'shared/providers/theme_provider.dart';
import 'features/ui/edge_ui.dart';

class ClipAIApp extends ConsumerStatefulWidget {
  const ClipAIApp({super.key});

  @override
  ConsumerState<ClipAIApp> createState() => _ClipAIAppState();
}

class _ClipAIAppState extends ConsumerState<ClipAIApp> with WindowListener {
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

    return MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(prefs.fontScale)),
      child: MaterialApp(
        title: 'ClipAI Pro',
        debugShowCheckedModeBanner: false,
        theme: appTheme.copyWith(
          scaffoldBackgroundColor: EdgeTheme.canvas,
          colorScheme: appTheme.colorScheme.copyWith(
            surface: EdgeTheme.panelBg,
          ),
          appBarTheme: appTheme.appBarTheme.copyWith(
            backgroundColor: EdgeTheme.menuBar,
          ),
          dividerColor: EdgeTheme.divider,
        ),
        home: ToastOverlay(
          child: const HomeScreen(),
        ),
      ),
    );
  }
}
