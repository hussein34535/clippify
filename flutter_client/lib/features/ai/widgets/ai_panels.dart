import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SmartCutPanel extends StatefulWidget {
  final String? videoPath;
  final VoidCallback? onCutComplete;

  const SmartCutPanel({super.key, this.videoPath, this.onCutComplete});

  @override
  State<SmartCutPanel> createState() => _SmartCutPanelState();
}

class _SmartCutPanelState extends State<SmartCutPanel> {
  bool _isAnalyzing = false;
  double _progress = 0;
  String _status = '';
  List<Map<String, double>> _silences = [];

  Future<void> _analyzeSilence() async {
    if (widget.videoPath == null || widget.videoPath!.isEmpty) return;
    setState(() { _isAnalyzing = true; _progress = 0; _status = 'تحليل الصمت...'; _silences = []; });

    try {
      final result = await Process.run('ffmpeg', [
        '-i', widget.videoPath!,
        '-af', 'silencedetect=noise=-30dB:d=0.5',
        '-f', 'null',
        '-',
      ]);

      if (result.stderr is String) {
        final lines = (result.stderr as String).split('\n');
        double? start;
        for (final line in lines) {
          if (line.contains('silence_start')) {
            start = double.tryParse(line.split('silence_start: ').last.trim());
          } else if (line.contains('silence_end') && start != null) {
            final end = double.tryParse(line.split('silence_end: ').last.split(' |').first.trim());
            if (end != null) {
              _silences.add({'start': start, 'end': end});
            }
            start = null;
          }
        }
        setState(() => _status = 'تم العثور على ${_silences.length} مقطع صامت');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    setState(() { _isAnalyzing = false; _progress = 1.0; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.content_cut, size: 14, color: AppColors.primary),
            const SizedBox(width: 8),
            const Text('Smart Cut', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeSilence,
              icon: Icon(_isAnalyzing ? Icons.hourglass_top : Icons.search, size: 14),
              label: Text(_isAnalyzing ? '...' : 'تحليل', style: const TextStyle(fontSize: 10)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
              ),
            ),
          ],
        ),
        if (_isAnalyzing) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _progress, backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
        ],
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
        if (_silences.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: CustomPaint(
              size: const Size(double.infinity, 60),
              painter: _SilenceTimelinePainter(silences: _silences, duration: _silences.last['end'] ?? 30),
            ),
          ),
          const SizedBox(height: 8),
          Text('${_silences.length} silent segments found', style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
        ],
      ],
    );
  }
}

class _SilenceTimelinePainter extends CustomPainter {
  final List<Map<String, double>> silences;
  final double duration;

  _SilenceTimelinePainter({required this.silences, required this.duration});

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF1E1F24);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    final silencePaint = Paint()..color = const Color(0xFFEF4444).withValues(alpha: 0.6);
    for (final s in silences) {
      final x1 = (s['start']! / duration) * size.width;
      final x2 = (s['end']! / duration) * size.width;
      canvas.drawRect(Rect.fromLTRB(x1, 0, x2, size.height), silencePaint);
    }

    final linePaint = Paint()..color = Colors.white.withValues(alpha: 0.1);
    for (double t = 0; t < duration; t += 1) {
      final x = (t / duration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SilenceTimelinePainter old) => old.silences != silences;
}

class BackgroundRemovalPanel extends StatelessWidget {
  final String currentMethod; // 'none', 'chromakey', 'rmbg'
  final String chromakeyColor;
  final ValueChanged<String> onMethodChanged;
  final ValueChanged<String> onColorChanged;

  const BackgroundRemovalPanel({
    super.key,
    required this.currentMethod,
    required this.chromakeyColor,
    required this.onMethodChanged,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.backup_table_rounded, size: 14, color: AppColors.primary),
        const SizedBox(width: 8),
        const Text('إزالة الخلفية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: currentMethod,
          decoration: const InputDecoration(
            labelText: 'طريقة الإزالة',
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('لا شيء', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'chromakey', child: Text('Chromakey', style: TextStyle(fontSize: 12))),
            DropdownMenuItem(value: 'rmbg', child: Text('AI (RMBG)', style: TextStyle(fontSize: 12))),
          ],
          onChanged: (v) => onMethodChanged(v ?? 'none'),
        ),
      ],
    );
  }
}
