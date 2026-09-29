import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/backend/auth_store.dart';
import '../auth/auth_screen.dart';
import '../auth/profile_screen.dart';
import '../mobile/library_mobile_page.dart';
import '../mobile/results_store_mobile.dart';
import '../mobile/save_helpers.dart';
import '../mobile/wizard_mobile_page.dart';

/// Phone layout: 4-tab simplified app
/// المكتبة | ✨مونتاج | النتائج | حسابك
class MobileHomeShell extends StatefulWidget {
  final VoidCallback? onLogout;

  const MobileHomeShell({super.key, this.onLogout});

  @override
  State<MobileHomeShell> createState() => _MobileHomeShellState();
}

class _MobileHomeShellState extends State<MobileHomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF0A84FF), Color(0xFFBF5AF2)]),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Clippify'),
          ],
        ),
        centerTitle: false,
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const LibraryPageMobile(onShareFile: shareClip),
          const WizardPageMobile(),
          const ResultsPageMobile(),
          ProfilePageMobile(onLogout: widget.onLogout),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        indicatorColor: scheme.primary.withOpacity(0.15),        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: 'المكتبة',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '✨مونتاج',
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined),
            selectedIcon: Icon(Icons.movie),
            label: 'النتائج',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'حسابك',
          ),
        ],
      ),
    );
  }
}

/// Results tab (v1): honest empty-state. The full AutoEditResultsScreen is
/// pushed by the progress screen itself; this tab only offers quick access to
/// the directory of the last export once that is recorded.
/// TODO(mobile-v2): render InMemoryResultsStore.instance.lastClips here when
/// the wizard flow starts populating the store.
class ResultsPageMobile extends StatefulWidget {
  const ResultsPageMobile({super.key});

  @override
  State<ResultsPageMobile> createState() => _ResultsPageMobileState();
}

class _ResultsPageMobileState extends State<ResultsPageMobile> {
  String? _lastOutputDir;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadLastOutputDir();
  }

  Future<void> _loadLastOutputDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _lastOutputDir = prefs.getString(kLastOutputDirPrefKey);
        _loaded = true;
      });
    } catch (e) {
      debugPrint('[ResultsMobile] load prefs failed: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _openLastExportDir() async {
    final dir = _lastOutputDir;
    if (dir == null || dir.isEmpty) return;
    try {
      await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'مجلد آخر تصدير',
        initialDirectory: dir,
      );
    } catch (e) {
      debugPrint('[ResultsMobile] open dir failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(height: 12),
            Text('ابدأ من المكتبة', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'اختر فيديو وشغّل المونتاج التلقائي لتظهر النتائج هنا',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_rounded,
                            size: 18,
                            color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'سجل النتائج يظهر هنا بعد اكتمال أول عملية',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed:
                          (_loaded && _lastOutputDir != null && _lastOutputDir!.isNotEmpty)
                              ? _openLastExportDir
                              : null,
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: const Text('فتح آخر مجلد تصدير'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Profile tab: embeds the real AuthScreen / ProfileScreen depending on
/// [authStateProvider] state.
class ProfilePageMobile extends ConsumerWidget {
  final VoidCallback? onLogout;

  const ProfilePageMobile({super.key, this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    switch (auth.status) {
      case AuthStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case AuthStatus.unauthenticated:
        // AuthScreen is a full Scaffold (own scroll + background) — embed as-is.
        return AuthScreen(onAuthenticated: onLogout);
      case AuthStatus.authenticated:
        return const ProfileScreen();
    }
  }
}
