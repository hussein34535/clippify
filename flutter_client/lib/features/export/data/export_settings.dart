import '../pipeline/export_pipeline.dart';

/// إعدادات جلسة تصدير واحدة — بيانات خالصة يبني منها المُصدِّر المحلّي
/// (TimelineExporter) أو كاتب XML.
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
