import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/backend/backend_service.dart';
import '../../features/mobile/save_helpers.dart';
import '../../features/results/rendered_clip.dart';

/// شاشة النهاية: المقاطع الجاهزة + حفظ في الاستوديو + مشاركة + فيديو جديد.
class LiteDoneScreen extends StatefulWidget {
  final List<RenderedClipData> clips;
  final VoidCallback onRestart;

  const LiteDoneScreen({
    super.key,
    required this.clips,
    required this.onRestart,
  });

  @override
  State<LiteDoneScreen> createState() => _LiteDoneScreenState();
}

class _LiteDoneScreenState extends State<LiteDoneScreen> {
  bool _busy = false;
  String? _notice;

  /// fileUrl قادم من السيرفر: http مباشر أو مسار نسبي (output/...) يُبنى
  /// عليه رابط /api/files (انظر engine/src/api/files.rs).
  Future<String> _resolveLocal(RenderedClipData clip) async {
    final raw = clip.fileUrl;
    final url = raw.startsWith('http')
        ? raw
        : '${BackendService.currentBaseUrl()}/api/files/$raw';
    final name = url.split('/').last;
    final tmp = File(p.join(Directory.systemTemp.path, 'lite_$name'));
    if (await tmp.exists()) return tmp.path;
    await Dio().download(url, tmp.path);
    return tmp.path;
  }

  Future<void> _saveAll() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    var ok = 0;
    try {
      for (final c in widget.clips) {
        final local = await _resolveLocal(c);
        if (await saveToGallery(local)) ok++;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = ok == widget.clips.length
          ? 'اتحفظوا كلهم في الاستوديو ($ok)'
          : 'اتحفظ $ok من ${widget.clips.length} — الباقي شاركه مباشرة';
    });
  }

  Future<void> _share(RenderedClipData clip) async {
    try {
      await shareClip(await _resolveLocal(clip));
    } catch (_) {
      if (!mounted) return;
      setState(() => _notice = 'تعذر تجهيز الملف للمشاركة.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final clips = widget.clips;
    return Scaffold(
      appBar: AppBar(
        title: const Text('خلصنا!'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      const Icon(Icons.celebration_rounded, size: 44),
                      const SizedBox(height: 8),
                      Text(
                        clips.isEmpty
                            ? 'مفيش مقاطع المرة دي'
                            : 'طلعنا لك ${clips.length} ${clips.length == 1 ? 'مقطع' : 'مقاطع'} جاهزين',
                        style: const TextStyle(fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: clips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = clips[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(
                          c.hookText.isNotEmpty ? c.hookText : 'مقطع ${i + 1}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                            '${c.durationSec.toStringAsFixed(0)} ث • ${c.viralScore.toStringAsFixed(2)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.ios_share_rounded),
                          onPressed:
                              _busy ? null : () => _share(c),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_notice != null) ...[
                Text(_notice!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _busy || clips.isEmpty ? null : _saveAll,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('حفظ الكل في الاستوديو'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : widget.onRestart,
                child: const Text('فيديو جديد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
