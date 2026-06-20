import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';

// ════════════════════════════════════════════════
// 1. AIUpscalePanel
// ════════════════════════════════════════════════

class AIUpscalePanel extends ConsumerStatefulWidget {
  final String videoPath;
  const AIUpscalePanel({super.key, required this.videoPath});

  @override
  ConsumerState<AIUpscalePanel> createState() => _AIUpscalePanelState();
}

class _AIUpscalePanelState extends ConsumerState<AIUpscalePanel> {
  int _factor = 2;
  String _model = 'realesrgan';
  bool _processing = false;
  String _status = '';
  String? _outputPath;

  Future<void> _process() async {
    setState(() {
      _processing = true;
      _status = 'جاري تحسين الدقة...';
      _outputPath = null;
    });
    try {
      final result = await ApiClient().aiUpscale(
        widget.videoPath,
        factor: _factor,
        model: _model,
      );
      switch (result) {
        case Success(data: final data):
          if (data['output_path'] != null) {
            setState(() {
              _outputPath = data['output_path'] as String;
              _status = 'اكتمل التحسين';
            });
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'تحسين الدقة',
      icon: Icons.enhance_photo_translate_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropDropdown(
            label: 'عامل التكبير',
            value: _factor.toString(),
            items: [2, 3, 4].map((f) => DropdownMenuItem(value: f.toString(), child: Text('${f}x', style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setState(() => _factor = int.parse(v!)),
          ),
          const SizedBox(height: 8),
          _PropDropdown(
            label: 'النموذج',
            value: _model,
            items: const [
              DropdownMenuItem(value: 'realesrgan', child: Text('Real-ESRGAN', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'waifu2x', child: Text('Waifu2x', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'srgan', child: Text('SRGAN', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _model = v!),
          ),
          const SizedBox(height: 12),
          _ActionButton(
            processing: _processing,
            onPressed: _process,
          ),
          if (_processing) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_processing) ...[const SizedBox(height: 8), _StatusText(_status)],
          if (_outputPath != null) ...[const SizedBox(height: 8), _BeforeAfterPreview()],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
// 2. AIFrameInterpolationPanel
// ════════════════════════════════════════════════

class AIFrameInterpolationPanel extends ConsumerStatefulWidget {
  final String videoPath;
  const AIFrameInterpolationPanel({super.key, required this.videoPath});

  @override
  ConsumerState<AIFrameInterpolationPanel> createState() => _AIFrameInterpolationPanelState();
}

class _AIFrameInterpolationPanelState extends ConsumerState<AIFrameInterpolationPanel> {
  int _fps = 60;
  String _method = 'rife';
  bool _processing = false;
  String _status = '';

  Future<void> _process() async {
    setState(() { _processing = true; _status = 'جاري تعبئة الإطارات...'; });
    try {
      final result = await ApiClient().aiInterpolate(widget.videoPath, fps: _fps, method: _method);
      switch (result) {
        case Success(data: final data):
          if (data['output_path'] != null) {
            setState(() => _status = 'اكتملت التعبئة');
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'تعبئة الإطارات',
      icon: Icons.slow_motion_video_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropDropdown(
            label: 'FPS الهدف',
            value: _fps.toString(),
            items: [30, 60, 120].map((f) => DropdownMenuItem(value: f.toString(), child: Text('${f}FPS', style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setState(() => _fps = int.parse(v!)),
          ),
          const SizedBox(height: 8),
          _PropDropdown(
            label: 'الطريقة',
            value: _method,
            items: const [
              DropdownMenuItem(value: 'rife', child: Text('RIFE', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'dain', child: Text('DAIN', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'film', child: Text('FILM', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 12),
          _ActionButton(processing: _processing, onPressed: _process),
          if (_processing) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_processing) ...[const SizedBox(height: 8), _StatusText(_status)],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
// 3. AIObjectRemovalPanel
// ════════════════════════════════════════════════

class AIObjectRemovalPanel extends ConsumerStatefulWidget {
  final String videoPath;
  final double videoWidth;
  final double videoHeight;
  const AIObjectRemovalPanel({super.key, required this.videoPath, this.videoWidth = 1920, this.videoHeight = 1080});

  @override
  ConsumerState<AIObjectRemovalPanel> createState() => _AIObjectRemovalPanelState();
}

class _AIObjectRemovalPanelState extends ConsumerState<AIObjectRemovalPanel> {
  Rect? _region;
  String _method = 'propainter';
  bool _processing = false;
  String _status = '';

  void _simulateRegionSelect() {
    setState(() {
      if (_region == null) {
        _region = Rect.fromLTWH(0.25, 0.25, 0.3, 0.3);
      } else {
        _region = null;
      }
    });
  }

  Future<void> _process() async {
    if (_region == null) { setState(() => _status = 'الرجاء تحديد المنطقة أولاً'); return; }
    setState(() { _processing = true; _status = 'جاري إزالة العنصر...'; });
    try {
      final result = await ApiClient().aiRemoveObject(
        widget.videoPath,
        {'x': _region!.left, 'y': _region!.top, 'w': _region!.width, 'h': _region!.height},
        method: _method,
      );
      switch (result) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            setState(() => _status = 'تمت الإزالة بنجاح');
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'إزالة العناصر',
      icon: Icons.auto_fix_high_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _region != null ? AppColors.primary : AppColors.border),
            ),
            child: GestureDetector(
              onTap: _simulateRegionSelect,
              child: _region == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app_rounded, color: AppColors.primary, size: 28),
                        SizedBox(height: 4),
                        Text('اضغط لتحديد المنطقة', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ],
                    )
                  : Stack(
                      children: [
                        const Center(child: Icon(Icons.videocam_outlined, color: AppColors.textMuted, size: 32)),
                        Positioned(
                          left: _region!.left * 260,
                          top: _region!.top * 70,
                          child: Container(
                            width: _region!.width * 260,
                            height: _region!.height * 70,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.destructive, width: 2),
                              color: AppColors.destructive.withValues(alpha: 0.15),
                            ),
                            child: const Center(child: Icon(Icons.close_rounded, color: AppColors.destructive, size: 20)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (_region != null) ...[
            const SizedBox(height: 4),
            Text('x:${(_region!.left*100).toInt()}% y:${(_region!.top*100).toInt()}% w:${(_region!.width*100).toInt()}% h:${(_region!.height*100).toInt()}%',
                style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 8),
          _PropDropdown(
            label: 'الطريقة',
            value: _method,
            items: const [
              DropdownMenuItem(value: 'propainter', child: Text('ProPainter', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'e2fgvi', child: Text('E2FGVI', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'mask', child: Text('mask-based', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 12),
          _ActionButton(processing: _processing, onPressed: _process),
          if (_processing) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_processing) ...[const SizedBox(height: 8), _StatusText(_status)],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
// 4. AIBackgroundReplacementPanel
// ════════════════════════════════════════════════

class AIBackgroundReplacementPanel extends ConsumerStatefulWidget {
  final String videoPath;
  const AIBackgroundReplacementPanel({super.key, required this.videoPath});

  @override
  ConsumerState<AIBackgroundReplacementPanel> createState() => _AIBackgroundReplacementPanelState();
}

class _AIBackgroundReplacementPanelState extends ConsumerState<AIBackgroundReplacementPanel> {
  String _method = 'ai';
  String _bgType = 'blur';
  Color _solidColor = const Color(0xFF00FF00);
  bool _processing = false;
  String _status = '';

  Future<void> _process() async {
    setState(() { _processing = true; _status = 'جاري استبدال الخلفية...'; });
    try {
      final result = await ApiClient().aiBackgroundReplace(widget.videoPath, {
        'method': _method,
        'background_type': _bgType,
        'solid_color': '#${_solidColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      });
      switch (result) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            setState(() => _status = 'تم استبدال الخلفية');
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'استبدال الخلفية',
      icon: Icons.wallpaper_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PropDropdown(
            label: 'الطريقة',
            value: _method,
            items: const [
              DropdownMenuItem(value: 'chromakey', child: Text('Chromakey', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'ai', child: Text('AI (RVM)', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'greenscreen', child: Text('Green Screen', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _method = v!),
          ),
          const SizedBox(height: 8),
          _PropDropdown(
            label: 'الخلفية',
            value: _bgType,
            items: const [
              DropdownMenuItem(value: 'blur', child: Text('ضبابية', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'solid', child: Text('لون صلب', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'image', child: Text('صورة', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _bgType = v!),
          ),
          const SizedBox(height: 8),
          if (_bgType == 'solid')
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final c = await showDialog<Color>(
                      context: context,
                      builder: (ctx) => _SimpleColorPicker(initial: _solidColor),
                    );
                    if (c != null) setState(() => _solidColor = c);
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _solidColor,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text('اختيار لون', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          const SizedBox(height: 12),
          _ActionButton(processing: _processing, onPressed: _process),
          if (_processing) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_processing) ...[const SizedBox(height: 8), _StatusText(_status)],
        ],
      ),
    );
  }
}

class _SimpleColorPicker extends StatelessWidget {
  final Color initial;
  const _SimpleColorPicker({required this.initial});

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.green, Colors.blue, Colors.red, Colors.yellow,
      Colors.cyan, Colors.purple, Colors.orange, Colors.white,
      Colors.black54, Colors.grey,
    ];
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('اختيار لون الخلفية', style: TextStyle(fontSize: 14, color: Colors.white)),
      content: Wrap(
        spacing: 8, runSpacing: 8,
        children: colors.map((c) => GestureDetector(
          onTap: () => Navigator.of(context).pop(c),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c == initial ? AppColors.primary : AppColors.border, width: c == initial ? 2.5 : 1),
            ),
          ),
        )).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════
// 5. AIVideoGenerationPanel
// ════════════════════════════════════════════════

class AIVideoGenerationPanel extends ConsumerStatefulWidget {
  const AIVideoGenerationPanel({super.key});

  @override
  ConsumerState<AIVideoGenerationPanel> createState() => _AIVideoGenerationPanelState();
}

class _AIVideoGenerationPanelState extends ConsumerState<AIVideoGenerationPanel> {
  final _promptController = TextEditingController();
  String _style = 'cinematic';
  int _duration = 5;
  String _resolution = '720p';
  bool _generating = false;
  String _status = '';

  Future<void> _generate() async {
    if (_promptController.text.trim().isEmpty) {
      setState(() => _status = 'الرجاء إدخال نص');
      return;
    }
    setState(() { _generating = true; _status = 'جاري توليد الفيديو...'; });
    try {
      final result = await ApiClient().aiGenerateVideo(
        _promptController.text.trim(),
        style: _style,
        duration: _duration,
        resolution: _resolution,
      );
      switch (result) {
        case Success(data: final data):
          if (data['output_path'] != null) {
            setState(() => _status = 'تم التوليد');
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _generating = false);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'توليد فيديو',
      icon: Icons.auto_awesome_motion_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _promptController,
            maxLines: 3,
            style: const TextStyle(fontSize: 12, color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'أدخل النص لتوليد الفيديو...',
              hintStyle: TextStyle(fontSize: 11, color: AppColors.textMuted),
              contentPadding: EdgeInsets.all(10),
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          _PropDropdown(
            label: 'الأسلوب',
            value: _style,
            items: const [
              DropdownMenuItem(value: 'cinematic', child: Text('سينمائي', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'anime', child: Text('أنمي', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'realistic', child: Text('واقعي', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: '3d', child: Text('ثلاثي الأبعاد', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setState(() => _style = v!),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('المدة (ثوان)', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                    Slider(
                      value: _duration.toDouble(), min: 2, max: 30, divisions: 28,
                      label: '${_duration}s',
                      onChanged: (v) => setState(() => _duration = v.round()),
                    ),
                  ],
                ),
              ),
              Text('${_duration}s', style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              _Chip(label: '720p', selected: _resolution == '720p', onTap: () => setState(() => _resolution = '720p')),
              const SizedBox(width: 6),
              _Chip(label: '1080p', selected: _resolution == '1080p', onTap: () => setState(() => _resolution = '1080p')),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _generating ? null : _generate,
              icon: Icon(_generating ? Icons.hourglass_top : Icons.auto_awesome, size: 14),
              label: Text(_generating ? 'جاري التوليد...' : 'توليد', style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_generating) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_generating) ...[const SizedBox(height: 8), _StatusText(_status)],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
// 6. AIAudioEnhancementPanel
// ════════════════════════════════════════════════

class AIAudioEnhancementPanel extends ConsumerStatefulWidget {
  final String videoPath;
  const AIAudioEnhancementPanel({super.key, required this.videoPath});

  @override
  ConsumerState<AIAudioEnhancementPanel> createState() => _AIAudioEnhancementPanelState();
}

class _AIAudioEnhancementPanelState extends ConsumerState<AIAudioEnhancementPanel> {
  bool _removeNoise = true;
  bool _removeReverb = false;
  bool _voiceIsolation = false;
  String _lufsTarget = '-14';
  bool _processing = false;
  String _status = '';

  Future<void> _process() async {
    setState(() { _processing = true; _status = 'جاري تحسين الصوت...'; });
    try {
      final result = await ApiClient().aiEnhanceAudio(widget.videoPath, {
        'remove_noise': _removeNoise,
        'remove_reverb': _removeReverb,
        'voice_isolation': _voiceIsolation,
        'lufs_target': _lufsTarget,
      });
      switch (result) {
        case Success(data: final data):
          if (data['status'] == 'success') {
            setState(() => _status = 'تم تحسين الصوت');
          } else {
            setState(() => _status = 'فشلت العملية');
          }
        case Failure():
          setState(() => _status = 'فشلت العملية');
      }
    } catch (e) {
      setState(() => _status = 'خطأ: $e');
    }
    if (mounted) setState(() => _processing = false);
  }

  @override
  Widget build(BuildContext context) {
    return _PanelCard(
      title: 'تحسين الصوت',
      icon: Icons.hearing_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToggleRow(label: 'إزالة الضوضاء', value: _removeNoise, onChanged: (v) => setState(() => _removeNoise = v)),
          _ToggleRow(label: 'إزالة الصدى', value: _removeReverb, onChanged: (v) => setState(() => _removeReverb = v)),
          _ToggleRow(label: 'عزل الصوت', value: _voiceIsolation, onChanged: (v) => setState(() => _voiceIsolation = v)),
          const SizedBox(height: 8),
          const Text('استهداف مستوى الصوت', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Row(
            children: [
              _Chip(label: '-14 LUFS', selected: _lufsTarget == '-14', onTap: () => setState(() => _lufsTarget = '-14')),
              const SizedBox(width: 6),
              _Chip(label: '-16 LUFS', selected: _lufsTarget == '-16', onTap: () => setState(() => _lufsTarget = '-16')),
              const SizedBox(width: 6),
              _Chip(label: '-23 LUFS', selected: _lufsTarget == '-23', onTap: () => setState(() => _lufsTarget = '-23')),
            ],
          ),
          const SizedBox(height: 12),
          _ActionButton(processing: _processing, onPressed: _process),
          if (_processing) ...[const SizedBox(height: 8), _ProgressBar()],
          if (_status.isNotEmpty && !_processing) ...[const SizedBox(height: 8), _StatusText(_status)],
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
// AI Pro Tab (container with sub-tabs)
// ════════════════════════════════════════════════

class AIProTab extends ConsumerStatefulWidget {
  final String videoPath;
  final double videoWidth;
  final double videoHeight;
  const AIProTab({super.key, required this.videoPath, this.videoWidth = 1920, this.videoHeight = 1080});

  @override
  ConsumerState<AIProTab> createState() => _AIProTabState();
}

class _AIProTabState extends ConsumerState<AIProTab> with SingleTickerProviderStateMixin {
  late TabController _subTabController;

  @override
  void initState() {
    super.initState();
    _subTabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _subTabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _subTabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          tabs: const [
            Tab(text: 'Upscale'),
            Tab(text: 'Interpolate'),
            Tab(text: 'Remove'),
            Tab(text: 'Background'),
            Tab(text: 'Generate'),
            Tab(text: 'Audio'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _subTabController,
            children: [
              SingleChildScrollView(padding: const EdgeInsets.all(12), child: AIUpscalePanel(videoPath: widget.videoPath)),
              SingleChildScrollView(padding: const EdgeInsets.all(12), child: AIFrameInterpolationPanel(videoPath: widget.videoPath)),
              SingleChildScrollView(padding: const EdgeInsets.all(12), child: AIObjectRemovalPanel(videoPath: widget.videoPath, videoWidth: widget.videoWidth, videoHeight: widget.videoHeight)),
              SingleChildScrollView(padding: const EdgeInsets.all(12), child: AIBackgroundReplacementPanel(videoPath: widget.videoPath)),
              const SingleChildScrollView(padding: EdgeInsets.all(12), child: AIVideoGenerationPanel()),
              SingleChildScrollView(padding: const EdgeInsets.all(12), child: AIAudioEnhancementPanel(videoPath: widget.videoPath)),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════
// Shared Widgets
// ════════════════════════════════════════════════

class _PanelCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _PanelCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _PropDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _PropDropdown({required this.label, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              dropdownColor: AppColors.surfaceVariant,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ToggleRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
          SizedBox(
            height: 24,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final bool processing;
  final VoidCallback onPressed;
  const _ActionButton({required this.processing, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: processing ? null : onPressed,
        icon: Icon(processing ? Icons.hourglass_top : Icons.play_arrow_rounded, size: 14),
        label: Text(processing ? '...جاري المعالجة' : 'تشغيل', style: const TextStyle(fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar();

  @override
  Widget build(BuildContext context) {
    return const LinearProgressIndicator(
      backgroundColor: AppColors.divider,
      valueColor: AlwaysStoppedAnimation(AppColors.primary),
    );
  }
}

class _StatusText extends StatelessWidget {
  final String text;
  const _StatusText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary));
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _BeforeAfterPreview extends StatelessWidget {
  const _BeforeAfterPreview();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(child: Icon(Icons.broken_image_rounded, color: AppColors.textMuted, size: 20)),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.arrow_forward_rounded, color: AppColors.primary, size: 16),
        ),
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            child: const Center(child: Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 20)),
          ),
        ),
      ],
    );
  }
}
