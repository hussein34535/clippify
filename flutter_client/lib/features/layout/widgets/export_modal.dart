import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../export/data/export_presets.dart';
import '../../export/pipeline/export_pipeline.dart';

class ExportSettings {
  final String type;
  final String outputFilename;
  final String exportQuality;
  final String xmlFormat;
  final bool includeSubtitles;
  final String xmlOutputPath;
  final String? presetName;
  final String? codec;
  final String? pixelFormat;
  final ExportPresetPro? presetPro;
  final bool twoPass;
  final bool includeMetadata;
  final String? watermarkPath;
  final String? watermarkPosition;

  ExportSettings({
    required this.type,
    required this.outputFilename,
    required this.exportQuality,
    required this.xmlFormat,
    required this.includeSubtitles,
    required this.xmlOutputPath,
    this.presetName,
    this.codec,
    this.pixelFormat,
    this.presetPro,
    this.twoPass = false,
    this.includeMetadata = true,
    this.watermarkPath,
    this.watermarkPosition,
  });
}

class ExportModal extends StatefulWidget {
  final String defaultOutputDir;
  final String defaultQuality;

  const ExportModal({
    super.key,
    this.defaultOutputDir = './exports',
    this.defaultQuality = 'High',
  });

  @override
  State<ExportModal> createState() => _ExportModalState();
}

class _ExportModalState extends State<ExportModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _filenameController;
  late TextEditingController _xmlPathController;

  String _exportQuality = 'High';
  String _xmlFormat = 'davinci';
  bool _includeSubtitles = true;
  String? _selectedPresetName;
  bool _twoPass = false;
  bool _includeMetadata = true;
  String? _watermarkPath;
  String _watermarkPosition = 'bottom-right';
  ExportPresetPro? _lastPipelinePreset;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _filenameController = TextEditingController(text: 'project_render_${DateTime.now().millisecondsSinceEpoch}.mp4');
    _xmlPathController = TextEditingController(
      text: '${widget.defaultOutputDir}/nle_project_${DateTime.now().millisecondsSinceEpoch}.xml',
    );
    _exportQuality = widget.defaultQuality;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _filenameController.dispose();
    _xmlPathController.dispose();
    super.dispose();
  }

  void _onPipelineEnqueue(ExportPresetPro preset) {
    _lastPipelinePreset = preset;
    _filenameController.text = preset.name.toLowerCase().replaceAll(' ', '_') + preset.container.extension;
    setState(() {
      _selectedPresetName = preset.name;
      _exportQuality = preset.quality;
      _twoPass = preset.twoPass;
      _includeMetadata = preset.includeMetadata;
      _watermarkPath = preset.watermarkPath;
      _watermarkPosition = preset.watermarkPosition ?? 'bottom-right';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 520,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 40,
              offset: Offset(0, 20),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.download_rounded, color: AppColors.primary, size: 18),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'تصدير مشروع Clippify',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'تصدير كفيديو نهائي أو كملف مشروع NLE لبرامج المونتاج',
                      style: TextStyle(fontSize: 9, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),

            // ── Tab Switcher ──
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(2),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Inter'),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.code_rounded, size: 14),
                        SizedBox(width: 6),
                        Text('تصدير XML احترافي'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.movie_creation_rounded, size: 14),
                        SizedBox(width: 6),
                        Text('ريندر فيديو نهائي'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Tab Contents ──
            Flexible(
              child: SizedBox(
                height: _tabController.index == 1 ? 480 : 240,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildXmlTab(),
                    _buildVideoPipelineTab(),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 16),

            // ── Action Buttons ──
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final isVideo = _tabController.index == 1;
                      final settings = ExportSettings(
                        type: isVideo ? 'video' : 'xml',
                        outputFilename: _filenameController.text.trim(),
                        exportQuality: _exportQuality,
                        xmlFormat: _xmlFormat,
                        includeSubtitles: _includeSubtitles,
                        xmlOutputPath: _xmlPathController.text.trim(),
                        presetName: _selectedPresetName,
                        codec: _lastPipelinePreset?.encoder.ffmpegCodec,
                        pixelFormat: _lastPipelinePreset?.encoder.pixelFormat,
                        presetPro: _lastPipelinePreset,
                        twoPass: _twoPass,
                        includeMetadata: _includeMetadata,
                        watermarkPath: _watermarkPath,
                        watermarkPosition: _watermarkPosition,
                      );
                      Navigator.pop(context, settings);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.download_rounded, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          _tabController.index == 1 ? 'بدء ريندر الفيديو' : 'تصدير ملف XML',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('إلغاء', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPipelineTab() {
    return ExportPipelinePanel(
      initialPreset: _selectedPresetName != null
          ? ExportPreset.available.where((p) => p.name == _selectedPresetName).firstOrNull
          : ExportPreset.available[0],
      onEnqueue: _onPipelineEnqueue,
    );
  }

  Widget _buildXmlTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text('تنسيق وتوافق برنامج المونتاج:', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _xmlFormat,
              isExpanded: true,
              dropdownColor: AppColors.card,
              items: const [
                DropdownMenuItem(value: 'davinci', child: Text('DaVinci Resolve (FCP 7 XML)', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 'premiere', child: Text('Adobe Premiere Pro (FCP XML)', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _xmlFormat = val;
                  });
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('مسار حفظ ملف الـ XML المخرج:', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: TextFormField(
            controller: _xmlPathController,
            style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            textAlign: TextAlign.left,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'تضمين الكلمات والترجمات كـ Markers صفراء',
              style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: _includeSubtitles,
              activeTrackColor: AppColors.primary,
              activeThumbColor: Colors.white,
              onChanged: (val) {
                setState(() {
                  _includeSubtitles = val;
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}
