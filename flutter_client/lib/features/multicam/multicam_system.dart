import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import 'dart:convert';
import '../../core/models/timeline_models.dart';
import '../../core/theme/app_theme.dart';
import '../timeline/providers/timeline_provider.dart';
import 'package:file_picker/file_picker.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  MulticamSynchronizer
// ═══════════════════════════════════════════════════════════════════════════

class MulticamSynchronizer {
  /// مزامنة عبر تحليل waveforms الصوتية (تتطلب FFprobe)
  Future<MulticamClip> syncByAudio(List<String> videoPaths) async {
    final angles = <MulticamAngle>[];
    final angleColors = _angleColors;

    for (int i = 0; i < videoPaths.length; i++) {
      angles.add(MulticamAngle(
        angleId: 'angle_$i',
        name: 'Camera ${i + 1}',
        sourcePath: videoPaths[i],
        startOffset: 0.0,
        colorValue: angleColors[i % angleColors.length],
      ));
    }

    double syncOffset = 0.0;
    if (videoPaths.length >= 2) {
      try {
        syncOffset = await _analyzeAudioSync(videoPaths);
      } catch (_) {
        syncOffset = 0.0;
      }
    }

    return MulticamClip(
      id: 'multicam_${DateTime.now().millisecondsSinceEpoch}',
      angles: angles,
      syncOffset: syncOffset,
      switches: [AngleSwitch(time: 0.0, angleId: angles.first.angleId)],
    );
  }

  /// مزامنة عبر Timecode المضمن في الفيديو (FFprobe)
  Future<MulticamClip> syncByTimecode(List<String> videoPaths) async {
    final angles = <MulticamAngle>[];
    final angleColors = _angleColors;
    final List<double> timecodes = [];

    for (int i = 0; i < videoPaths.length; i++) {
      double tc = 0.0;
      try {
        tc = await _extractTimecode(videoPaths[i]);
      } catch (_) {}
      timecodes.add(tc);

      angles.add(MulticamAngle(
        angleId: 'angle_$i',
        name: 'Camera ${i + 1}',
        sourcePath: videoPaths[i],
        startOffset: tc,
        colorValue: angleColors[i % angleColors.length],
      ));
    }

    final minTc = timecodes.reduce(min);
    final adjustedAngles = angles.map((a) {
      return a.copyWith(startOffset: a.startOffset - minTc);
    }).toList();

    return MulticamClip(
      id: 'multicam_${DateTime.now().millisecondsSinceEpoch}',
      angles: adjustedAngles,
      switches: [AngleSwitch(time: 0.0, angleId: adjustedAngles.first.angleId)],
    );
  }

  /// مزامنة يدوية بإزاحات يحددها المستخدم
  Future<MulticamClip> syncManually(
      List<String> videoPaths, List<double> offsets) async {
    final angles = <MulticamAngle>[];
    final angleColors = _angleColors;

    for (int i = 0; i < videoPaths.length; i++) {
      angles.add(MulticamAngle(
        angleId: 'angle_$i',
        name: 'Camera ${i + 1}',
        sourcePath: videoPaths[i],
        startOffset: i < offsets.length ? offsets[i] : 0.0,
        colorValue: angleColors[i % angleColors.length],
      ));
    }

    return MulticamClip(
      id: 'multicam_${DateTime.now().millisecondsSinceEpoch}',
      angles: angles,
      switches: [AngleSwitch(time: 0.0, angleId: angles.first.angleId)],
    );
  }

  static const List<int> _angleColors = [
    0xFF0A84FF,
    0xFF30D158,
    0xFFFF9F0A,
    0xFFFF453A,
    0xFF5E5CE6,
    0xFF64D2FF,
    0xFFFF375F,
    0xFFBF5AF2,
  ];

  /// تحليل التزامن الصوتي باستخدام FFprobe (استخراج waveforms ومطابقتها)
  Future<double> _analyzeAudioSync(List<String> videoPaths) async {
    final waveforms = <List<double>>[];
    for (final path in videoPaths) {
      final wf = await _extractWaveform(path);
      waveforms.add(wf);
    }

    if (waveforms.length < 2) return 0.0;
    return _findBestOffset(waveforms[0], waveforms[1]);
  }

  /// استخراج waveform بقيمة 0–1 باستخدام FFprobe
  Future<List<double>> _extractWaveform(String videoPath) async {
    final result = await Process.run(
      'ffprobe',
      [
        '-v',
        'quiet',
        '-f',
        'lavfi',
        '-i',
        'amovie=$videoPath,asetnsamples=256,astats=metadata=1:reset=1',
        '-show_entries',
        'frame=pkt_pts_time:metadata=lavfi.astats.Mean',
        '-of',
        'json',
      ],
    );
    if (result.exitCode != 0) return [];

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final frames = json['frames'] as List<dynamic>? ?? [];
    final samples = <double>[];
    for (final f in frames) {
      final meta = (f as Map<String, dynamic>)['tags'] as Map<String, dynamic>?;
      final mean = meta?['lavfi.astats.Mean'];
      if (mean != null) {
        samples.add((mean as num).toDouble().abs().clamp(0.0, 1.0));
      }
    }
    if (samples.isEmpty) return [];
    return samples;
  }

  /// إيجاد أفضل إزاحة بين موجتين (cross-correlation بسيط)
  double _findBestOffset(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxOffset = (a.length / 10).round().clamp(1, 100);
    double bestCorr = -1;
    int bestOffset = 0;

    for (int offset = -maxOffset; offset <= maxOffset; offset++) {
      double corr = 0;
      int count = 0;
      for (int i = 0; i < a.length; i++) {
        final j = i + offset;
        if (j >= 0 && j < b.length) {
          corr += (a[i] - 0.5) * (b[j] - 0.5);
          count++;
        }
      }
      if (count > 0) {
        corr /= count;
        if (corr > bestCorr) {
          bestCorr = corr;
          bestOffset = offset;
        }
      }
    }
    // تحويل offset من sample إلى ثوانٍ (بفرض 256 sample لكل frame و frame rate متغير)
    return bestOffset * 0.01;
  }

  /// استخراج timecode من الفيديو باستخدام FFprobe
  Future<double> _extractTimecode(String videoPath) async {
    final result = await Process.run(
      'ffprobe',
      [
        '-v',
        'quiet',
        '-show_entries',
        'format_tags=timecode',
        '-of',
        'json',
        videoPath,
      ],
    );
    if (result.exitCode != 0) return 0.0;

    final json = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final format = json['format'] as Map<String, dynamic>?;
    final tags = format?['tags'] as Map<String, dynamic>?;
    final tc = tags?['timecode'] as String?;
    if (tc == null) return 0.0;
    return _parseTimecode(tc);
  }

  double _parseTimecode(String tc) {
    final parts = tc.split(':');
    if (parts.length >= 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final sParts = parts[2].split(';');
      final s = int.tryParse(sParts[0]) ?? 0;
      final f = sParts.length > 1 ? int.tryParse(sParts[1]) ?? 0 : 0;
      return h * 3600.0 + m * 60.0 + s + f / 30.0;
    }
    return 0.0;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MulticamViewer — يعرض جميع زوايا الكاميرا في شبكة
// ═══════════════════════════════════════════════════════════════════════════

class MulticamViewer extends ConsumerWidget {
  final double currentTime;
  final void Function(String angleId)? onSwitchAngle;

  const MulticamViewer({
    super.key,
    required this.currentTime,
    this.onSwitchAngle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mc = ref.watch(timelineProvider).timeline.activeMulticam;
    if (mc == null) {
      return const Center(child: Text('No multicam clip active'));
    }

    final activeAngleId = mc.getActiveAngleIdAtTime(currentTime);
    final count = mc.angles.length;
    final crossAxisCount = count <= 1 ? 1 : (count <= 4 ? 2 : 3);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          padding: const EdgeInsets.all(4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 16 / 9,
          ),
          itemCount: mc.angles.length,
          itemBuilder: (context, index) {
            final angle = mc.angles[index];
            final isActive = angle.angleId == activeAngleId;
            return _AngleTile(
              angle: angle,
              isActive: isActive,
              onTap: () => onSwitchAngle?.call(angle.angleId),
            );
          },
        );
      },
    );
  }
}

class _AngleTile extends StatelessWidget {
  final MulticamAngle angle;
  final bool isActive;
  final VoidCallback onTap;

  const _AngleTile({
    required this.angle,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(angle.colorValue);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isActive ? color : AppColors.border,
            width: isActive ? 3 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videocam,
              color: isActive ? color : AppColors.textMuted,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              angle.name,
              style: TextStyle(
                color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              angle.sourcePath.split('\\').last.split('/').last,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  MulticamEditor — يعرض multicam كمسارات ملونة في التايملاين
// ═══════════════════════════════════════════════════════════════════════════

class MulticamEditor extends ConsumerWidget {
  const MulticamEditor({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(timelineProvider);
    final mc = data.timeline.activeMulticam;
    final playheadSec = data.timeline.playheadSec;
    final zoomLevel = data.timeline.zoomLevel;
    if (mc == null) return const SizedBox.shrink();

    final activeAngleId = mc.getActiveAngleIdAtTime(playheadSec);
    final pxPerSec = zoomLevel;
    final totalWidth = (mc.duration + 5.0) * pxPerSec;

    return Container(
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.timelineTrack,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              children: [
                Icon(Icons.switch_camera, size: 12, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  'Multicam (${mc.angles.length} angles)',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  'Active: ${mc.getAngleById(activeAngleId)?.name ?? ''}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    size: Size(totalWidth, 34),
                    painter: _MulticamTrackPainter(
                      mc: mc,
                      playheadSec: playheadSec,
                      pxPerSec: pxPerSec,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MulticamTrackPainter extends CustomPainter {
  final MulticamClip mc;
  final double playheadSec;
  final double pxPerSec;

  _MulticamTrackPainter({
    required this.mc,
    required this.playheadSec,
    required this.pxPerSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sortedSwitches = List<AngleSwitch>.from(mc.switches)
      ..sort((a, b) => a.time.compareTo(b.time));

    double segmentStart = 0.0;
    for (int i = 0; i < sortedSwitches.length; i++) {
      final sw = sortedSwitches[i];
      final segmentEnd = (i < sortedSwitches.length - 1)
          ? sortedSwitches[i + 1].time
          : mc.duration;
      final angle = mc.getAngleById(sw.angleId);
      final color = Color(angle?.colorValue ?? 0xFF0A84FF);

      final x1 = segmentStart * pxPerSec;
      final x2 = segmentEnd * pxPerSec;

      canvas.drawRect(
        Rect.fromLTRB(x1, 0, x2, size.height),
        Paint()..color = color.withValues(alpha: 0.3),
      );

      if (angle != null) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: angle.name,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: x2 - x1 - 8);
        textPainter.paint(canvas, Offset(x1 + 4, size.height / 2 - textPainter.height / 2));
      }

      canvas.drawLine(
        Offset(x2, 0),
        Offset(x2, size.height),
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..strokeWidth = 2,
      );

      segmentStart = segmentEnd;
    }

    if (sortedSwitches.isEmpty && mc.angles.isNotEmpty) {
      final angle = mc.angles.first;
      final color = Color(angle.colorValue);
      canvas.drawRect(
        Rect.fromLTRB(0, 0, mc.duration * pxPerSec, size.height),
        Paint()..color = color.withValues(alpha: 0.3),
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: angle.name,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, const Offset(4, size.height / 2 - textPainter.height / 2));
    }

    final playheadX = playheadSec * pxPerSec;
    if (playheadX >= 0 && playheadX <= size.width) {
      canvas.drawLine(
        Offset(playheadX, 0),
        Offset(playheadX, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }

    final totalW = mc.duration * pxPerSec;
    if (totalW < size.width) {
      canvas.drawLine(
        Offset(totalW, 0),
        Offset(totalW, size.height),
        Paint()
          ..color = AppColors.border
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MulticamTrackPainter old) =>
      old.mc != mc || old.playheadSec != playheadSec || old.pxPerSec != pxPerSec;
}

// ═══════════════════════════════════════════════════════════════════════════
//  CreateMulticamDialog — حوار إنشاء مقطع متعدد الكاميرات
// ═══════════════════════════════════════════════════════════════════════════

class CreateMulticamDialog extends ConsumerStatefulWidget {
  const CreateMulticamDialog({super.key});

  @override
  ConsumerState<CreateMulticamDialog> createState() => _CreateMulticamDialogState();
}

class _CreateMulticamDialogState extends ConsumerState<CreateMulticamDialog> {
  final List<_AngleEntry> _angles = [];
  String _syncMethod = 'audio';
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _angles.add(_AngleEntry(name: 'Camera 1'));
    _angles.add(_AngleEntry(name: 'Camera 2'));
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'mts', 'm2ts', 'webm'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _angles.clear();
        for (int i = 0; i < result.files.length; i++) {
          _angles.add(_AngleEntry(
            name: 'Camera ${i + 1}',
            path: result.files[i].path,
          ));
        }
      });
    }
  }

  Future<void> _createMulticam() async {
    final validAngles = _angles.where((a) => a.path != null && a.path!.isNotEmpty).toList();
    if (validAngles.isEmpty || validAngles.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least 2 video files')),
        );
      }
      return;
    }

    setState(() => _isCreating = true);

    try {
      final paths = validAngles.map((a) => a.path!).toList();
      final synchronizer = MulticamSynchronizer();
      late MulticamClip clip;

      switch (_syncMethod) {
        case 'timecode':
          clip = await synchronizer.syncByTimecode(paths);
          break;
        case 'manual':
          final offsets = validAngles.map((a) => a.offset).toList();
          clip = await synchronizer.syncManually(paths, offsets);
          break;
        default:
          clip = await synchronizer.syncByAudio(paths);
      }

      // تطبيق الأسماء المخصصة
      final updatedAngles = <MulticamAngle>[];
      for (int i = 0; i < clip.angles.length && i < validAngles.length; i++) {
        updatedAngles.add(clip.angles[i].copyWith(
          name: validAngles[i].name.isNotEmpty ? validAngles[i].name : clip.angles[i].name,
        ));
      }
      clip = clip.copyWith(angles: updatedAngles);

      if (mounted) {
        ref.read(timelineProvider.notifier).setMulticamClip(clip);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating multicam: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.switch_camera, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'إنشاء مقطع متعدد الكاميرات',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // File picker button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.video_library_outlined, size: 18),
                        label: const Text('اختيار ملفات الفيديو'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sync method selector
                    const Text(
                      'طريقة المزامنة',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SyncMethodChip(
                      label: 'Audio (Waveform)',
                      icon: Icons.graphic_eq,
                      selected: _syncMethod == 'audio',
                      onSelected: () => setState(() => _syncMethod = 'audio'),
                    ),
                    const SizedBox(height: 4),
                    _SyncMethodChip(
                      label: 'Timecode',
                      icon: Icons.timer_outlined,
                      selected: _syncMethod == 'timecode',
                      onSelected: () => setState(() => _syncMethod = 'timecode'),
                    ),
                    const SizedBox(height: 4),
                    _SyncMethodChip(
                      label: 'يدوي (Manual)',
                      icon: Icons.tune,
                      selected: _syncMethod == 'manual',
                      onSelected: () => setState(() => _syncMethod = 'manual'),
                    ),
                    const SizedBox(height: 16),

                    // Angle list
                    const Text(
                      'الزوايا',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._angles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final angle = entry.value;
                      return _AngleInputTile(
                        index: index,
                        angle: angle,
                        showOffset: _syncMethod == 'manual',
                        onNameChanged: (v) => setState(() => _angles[index].name = v),
                        onOffsetChanged: (v) => setState(() => _angles[index].offset = v),
                        onPathChanged: (v) => setState(() => _angles[index].path = v),
                        onRemove: _angles.length > 2
                            ? () => setState(() => _angles.removeAt(index))
                            : null,
                      );
                    }),
                    if (_angles.length < 8)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _angles.add(_AngleEntry(name: 'Camera ${_angles.length + 1}'));
                          }),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('إضافة زاوية'),
                          style: AppButtonStyle.text(),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إلغاء'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isCreating ? null : _createMulticam,
                    style: AppButtonStyle.filled(),
                    child: _isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('إنشاء'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncMethodChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  const _SyncMethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (selected) const Spacer(),
            if (selected)
              const Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _AngleInputTile extends StatelessWidget {
  final int index;
  final _AngleEntry angle;
  final bool showOffset;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<double> onOffsetChanged;
  final ValueChanged<String?> onPathChanged;
  final VoidCallback? onRemove;

  const _AngleInputTile({
    required this.index,
    required this.angle,
    required this.showOffset,
    required this.onNameChanged,
    required this.onOffsetChanged,
    required this.onPathChanged,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(MulticamSynchronizer._angleColors[index % MulticamSynchronizer._angleColors.length]);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 28,
                  child: TextField(
                    controller: TextEditingController(text: angle.name),
                    onChanged: onNameChanged,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  angle.path != null
                      ? angle.path!.split('\\').last.split('/').last
                      : 'No file selected',
                  style: TextStyle(
                    color: angle.path != null ? AppColors.textSecondary : AppColors.textMuted,
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showOffset)
            SizedBox(
              width: 70,
              child: TextField(
                keyboardType: TextInputType.number,
                onChanged: (v) => onOffsetChanged(double.tryParse(v) ?? 0.0),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  border: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                  hintText: '0.0s',
                  hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 16, color: AppColors.destructive),
              onPressed: onRemove,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 14,
            ),
        ],
      ),
    );
  }
}

class _AngleEntry {
  String name;
  String? path;
  double offset;

  _AngleEntry({required this.name, this.path, this.offset = 0.0});
}
