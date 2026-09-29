import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/backend/auto_edit_api.dart';
import '../../core/theme/app_theme.dart';
import '../wizard/auto_edit_progress_screen.dart'
    show defaultAutoEditApi;
import '../wizard/auto_edit_wizard_dialog.dart';

class _MobileMedia {
  final String path;
  final String name;
  const _MobileMedia(this.path, this.name);
}

/// Injectable picker so tests (and future upload flows) can replace it.
Future<List<String>> defaultPickVideos() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.video,
    allowMultiple: true,
  );
  return res?.paths.whereType<String>().toList() ?? <String>[];
}

/// Simplified 2-column media grid for phones.
/// NOTE(mobile-v1): YouTube import is intentionally skipped on mobile —
/// it requires backend-side yt-dlp; revisit after cloud mode ships.
class LibraryPageMobile extends StatefulWidget {
  /// AutoEditApi used by the pushed wizard page — injectable for tests.
  /// Defaults to the shared [defaultAutoEditApi] instance.
  final AutoEditApi? wizardApi;

  /// Share a raw source file from the library.
  final Future<void> Function(String filePath)? onShareFile;

  final Future<List<String>> Function() pickVideos;

  const LibraryPageMobile({
    super.key,
    this.wizardApi,
    this.onShareFile,
    this.pickVideos = defaultPickVideos,
  });

  @override
  State<LibraryPageMobile> createState() => _LibraryPageMobileState();
}

class _LibraryPageMobileState extends State<LibraryPageMobile> {
  final List<_MobileMedia> _files = [];
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final paths = await widget.pickVideos();
      if (!mounted) return;
      setState(() {
        for (final path in paths) {
          if (_files.any((f) => f.path == path)) continue;
          _files.add(_MobileMedia(path, p.basename(path)));
        }
      });
      if (paths.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تمت إضافة ${paths.length} فيديو')),
        );
      }
    } catch (e) {
      debugPrint('[LibraryMobile] pick failed: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _removeAt(int index) {
    setState(() => _files.removeAt(index));
  }

  /// Self-contained auto-edit entry: hosts the existing desktop
  /// [AutoEditWizardDialog] inside a pushed full-screen route. On submit the
  /// dialog itself pops this route and pushes AutoEditProgressScreen.
  void _openAutoEditWizard(String videoPath) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: AutoEditWizardDialog(
                videoPath: videoPath,
                api: widget.wizardApi ?? defaultAutoEditApi(),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_files.isEmpty)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.video_library_outlined,
                    size: 72,
                    color:
                        Theme.of(context).colorScheme.onSurface.withOpacity(0.3)),
                const SizedBox(height: 12),
                Text(
                  'مكتبتك فاضية',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'اضغط + لاستيراد فيديو وابدأ المونتاج التلقائي',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                      ),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final file = _files[index];
              return _Tile(
                name: file.name,
                gradientColors: _gradientFor(index),
                onAutoEdit: () => _openAutoEditWizard(file.path),
                onShare: () async {
                  final share = widget.onShareFile;
                  if (share != null) {
                    await share(file.path);
                  }
                },
                onDelete: () => _removeAt(index),
              );
            },
          ),
        Positioned(
          bottom: 16,
          left: 16,
          child: FloatingActionButton(
            heroTag: 'library-pick-fab',
            onPressed: _picking ? null : _pick,
            child: _picking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  List<Color> _gradientFor(int index) {
    const palettes = [
      [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
      [Color(0xFF30D158), Color(0xFF0A84FF)],
      [Color(0xFFFF9F0A), Color(0xFFFF453A)],
      [Color(0xFF5E5CE6), Color(0xFFBF5AF2)],
    ];
    return palettes[index % palettes.length];
  }
}

class _Tile extends StatelessWidget {
  final String name;
  final List<Color> gradientColors;
  final VoidCallback onAutoEdit;
  final Future<void> Function() onShare;
  final VoidCallback onDelete;

  const _Tile({
    required this.name,
    required this.gradientColors,
    required this.onAutoEdit,
    required this.onShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: PopupMenuButton<String>(
              iconColor: Colors.white,
              onSelected: (value) {
                switch (value) {
                  case 'wizard':
                    onAutoEdit();
                  case 'share':
                    onShare();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'wizard',
                  child: Row(children: [
                    Icon(Icons.auto_awesome, size: 18),
                    SizedBox(width: 8),
                    Text('✨ مونتاج تلقائي'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(children: [
                    Icon(Icons.share, size: 18),
                    SizedBox(width: 8),
                    Text('مشاركة'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline,
                        size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('حذف', style: TextStyle(color: Colors.redAccent)),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
