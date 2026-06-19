import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  
  late final Dio _dio;
  
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5), // لعمليات التحليل الطويلة
      headers: {
        'Content-Type': 'application/json',
      },
    ));
  }

  Dio get dio => _dio;

  /// الحصول على الإعدادات الحالية
  Future<Map<String, dynamic>> getSettings() async {
    try {
      final response = await _dio.get('/api/settings');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ApiClient] getSettings error: $e');
      return {};
    }
  }

  /// حفظ الإعدادات
  Future<bool> postSettings(Map<String, dynamic> settings) async {
    try {
      final response = await _dio.post('/api/settings', data: settings);
      return response.data['status'] == 'success';
    } catch (e) {
      debugPrint('[ApiClient] postSettings error: $e');
      return false;
    }
  }

  /// تنظيف الذاكرة المؤقتة (Cache)
  Future<Map<String, dynamic>> clearCache() async {
    try {
      final response = await _dio.post('/api/clear-cache');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[ApiClient] clearCache error: $e');
      return {'status': 'failed', 'message': e.toString()};
    }
  }

  /// بدء تحميل فيديو يوتيوب
  Future<String?> downloadYoutube(String url) async {
    try {
      final response = await _dio.post('/api/download-youtube', data: {'url': url});
      return response.data['session_id'] as String?;
    } catch (e) {
      debugPrint('[ApiClient] downloadYoutube error: $e');
      return null;
    }
  }

  /// التحقق من حالة جلسة عمل معينة (مثل تحميل أو رندر)
  Future<Map<String, dynamic>?> getSessionStatus(String sessionId) async {
    try {
      final response = await _dio.get('/api/status', queryParameters: {'session_id': sessionId});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] getSessionStatus error: $e');
      return null;
    }
  }

  /// تحويل الصوت إلى نصوص (Transcribe)
  Future<Map<String, dynamic>?> transcribe(String videoPath) async {
    try {
      final response = await _dio.post('/api/transcribe', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] transcribe error: $e');
      return null;
    }
  }

  /// اكتشاف الصمت في الفيديو
  Future<Map<String, dynamic>?> detectSilence(String videoPath, {int minSilenceDurationMs = 500, double threshold = 0.5}) async {
    try {
      final response = await _dio.post('/api/detect-silence', data: {
        'video_path': videoPath,
        'min_silence_duration_ms': minSilenceDurationMs,
        'threshold': threshold,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] detectSilence error: $e');
      return null;
    }
  }

  /// التحدث مع المساعد الذكي (Copilot Chat)
  Future<Map<String, dynamic>?> copilotChat({
    required String prompt,
    required List<Map<String, dynamic>> transcript,
    required Map<String, dynamic> timelineState,
  }) async {
    try {
      final response = await _dio.post('/api/copilot/chat', data: {
        'prompt': prompt,
        'transcript': transcript,
        'timeline_state': timelineState,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] copilotChat error: $e');
      return null;
    }
  }

  /// بدء تحليل الفيديو الذكي (يرجع session_id)
  Future<String?> analyzeVideo(String videoPath, {String contentType = 'podcast'}) async {
    try {
      final response = await _dio.post('/api/analyze-video', data: {
        'video_path': videoPath,
        'content_type': contentType,
      });
      return response.data['session_id'] as String?;
    } catch (e) {
      debugPrint('[ApiClient] analyzeVideo error: $e');
      return null;
    }
  }

  /// توليد خطة المونتاج الذكية
  Future<Map<String, dynamic>?> generatePlan({
    required String videoPath,
    required List<Map<String, dynamic>> words,
    String contentType = 'podcast',
    int nClips = 5,
    double durationSec = 60.0,
    String customInstructions = '',
  }) async {
    try {
      final response = await _dio.post('/api/generate-plan', data: {
        'video_path': videoPath,
        'words': words,
        'content_type': contentType,
        'n_clips': nClips,
        'duration_sec': durationSec,
        'custom_instructions': customInstructions,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] generatePlan error: $e');
      return null;
    }
  }

  /// بدء تصدير الفيديو (Render)
  Future<String?> renderPlan({
    required String videoPath,
    required List<Map<String, dynamic>> clips,
    String contentType = 'podcast',
    String outputDir = './output',
    String sfxMode = 'normal',
    bool compileClips = true,
    bool translateToArabic = false,
    String fontName = 'Impact',
    String exportQuality = 'High',
    bool autoBroll = false,
    bool gemmaMultimodal = false,
    String pexelsApiKey = '',
    String pixabayApiKey = '',
    String exportMode = 'ffmpeg',
    String? presetName,
    String? codec,
    String? pixelFormat,
    String? encoder,
    String? containerFormat,
    int? bitrateMbps,
    int? maxBitrateMbps,
    bool twoPass = false,
    bool includeMetadata = true,
    String? watermarkPath,
    String? watermarkPosition,
    String? preset,
  }) async {
    try {
      final data = <String, dynamic>{
        'video_path': videoPath,
        'clips': clips,
        'content_type': contentType,
        'output_dir': outputDir,
        'sfx_mode': sfxMode,
        'compile_clips': compileClips,
        'translate_to_arabic': translateToArabic,
        'font_name': fontName,
        'export_quality': exportQuality,
        'auto_broll': autoBroll,
        'gemma_multimodal': gemmaMultimodal,
        'pexels_api_key': pexelsApiKey,
        'pixabay_api_key': pixabayApiKey,
        'export_mode': exportMode,
        'two_pass': twoPass,
        'include_metadata': includeMetadata,
      };
      if (presetName != null) data['preset_name'] = presetName;
      if (codec != null) data['codec'] = codec;
      if (pixelFormat != null) data['pixel_format'] = pixelFormat;
      if (encoder != null) data['encoder'] = encoder;
      if (containerFormat != null) data['container_format'] = containerFormat;
      if (bitrateMbps != null) data['bitrate_mbps'] = bitrateMbps;
      if (maxBitrateMbps != null) data['max_bitrate_mbps'] = maxBitrateMbps;
      if (watermarkPath != null) data['watermark_path'] = watermarkPath;
      if (watermarkPosition != null) data['watermark_position'] = watermarkPosition;
      if (preset != null) data['preset'] = preset;
      final response = await _dio.post('/api/render-plan', data: data);
      return response.data['session_id'] as String?;
    } catch (e) {
      debugPrint('[ApiClient] renderPlan error: $e');
      return null;
    }
  }

  /// جلب جميع أدوات الذكاء الاصطناعي المصنفة
  Future<Map<String, dynamic>?> getAITools() async {
    try {
      final response = await _dio.get('/api/ai/tools');
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] getAITools error: $e');
      return null;
    }
  }

  /// تنفيذ إجراءات الذكاء الاصطناعي على حالة التايملاين
  Future<Map<String, dynamic>?> executeAIActions(List<Map<String, dynamic>> actions, Map<String, dynamic> timelineState) async {
    try {
      final response = await _dio.post('/api/ai/execute', data: {
        'actions': actions,
        'timeline_state': timelineState,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] executeAIActions error: $e');
      return null;
    }
  }

  /// حفظ المشروع محلياً
  Future<Map<String, dynamic>?> saveProject(Map<String, dynamic> timeline, {String? outputPath}) async {
    try {
      final response = await _dio.post('/api/project/save', data: {
        'timeline': timeline,
        'output_path': outputPath,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] saveProject error: $e');
      return null;
    }
  }

  /// تحميل مشروع مخزن محلياً
  Future<Map<String, dynamic>?> loadProject(String path) async {
    try {
      final response = await _dio.get('/api/project/load', queryParameters: {'path': path});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] loadProject error: $e');
      return null;
    }
  }

  /// الحصول على قائمة المشاريع الأخيرة
  Future<List<dynamic>> getRecentProjects() async {
    try {
      final response = await _dio.get('/api/project/recent');
      return response.data as List<dynamic>? ?? [];
    } catch (e) {
      debugPrint('[ApiClient] getRecentProjects error: $e');
      return [];
    }
  }

  /// بدء ريندر التايملاين بالكامل كفيديو نهائي
  Future<Map<String, dynamic>?> renderTimeline(Map<String, dynamic> timeline, {String? outputFilename}) async {
    try {
      final response = await _dio.post('/api/project/render/timeline', data: {
        'timeline': timeline,
        'output_filename': outputFilename,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] renderTimeline error: $e');
      return null;
    }
  }

  /// تصدير التايملاين بصيغة XML المتوافقة مع NLE (DaVinci/Premiere)
  Future<Map<String, dynamic>?> exportXml(Map<String, dynamic> timeline, {String? outputPath, String format = 'davinci'}) async {
    try {
      final response = await _dio.post('/api/project/export/xml', data: {
        'timeline': timeline,
        'output_path': outputPath,
        'format': format,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] exportXml error: $e');
      return null;
    }
  }

  /// الحصول على معلومات الفيديو والـ Thumbnail من الباك إند
  Future<Map<String, dynamic>?> getMediaInfo(String videoPath, {double? timestampSec}) async {
    try {
      final Map<String, dynamic> payload = {'path': videoPath};
      if (timestampSec != null) {
        payload['timestamp_sec'] = timestampSec;
      }
      final response = await _dio.post('/api/media-info', data: payload);
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] getMediaInfo error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> analyzeBeats(String audioPath) async {
    try {
      final response = await _dio.post('/api/analyze-beats', data: {'audio_path': audioPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] analyzeBeats error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> styleAnalyze(String videoPath) async {
    try {
      final response = await _dio.post('/api/style/analyze-reference', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] styleAnalyze error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> styleImitate(String videoPath, String styleProfile) async {
    try {
      final response = await _dio.post('/api/style/imitate', data: {'video_path': videoPath, 'style_profile': styleProfile});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] styleImitate error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> brollSearch(String query) async {
    try {
      final response = await _dio.post('/api/broll/search', data: {'query': query});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] brollSearch error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> brollDownload(String url) async {
    try {
      final response = await _dio.post('/api/broll/download', data: {'url': url});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] brollDownload error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> audioSeparate(String videoPath) async {
    try {
      final response = await _dio.post('/api/audio/separate', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] audioSeparate error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> audioDucking(String videoPath) async {
    try {
      final response = await _dio.post('/api/audio/ducking', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] audioDucking error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> viralRecommendations(String videoPath) async {
    try {
      final response = await _dio.post('/api/viral/recommendations', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] viralRecommendations error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> autoFraming(String videoPath) async {
    try {
      final response = await _dio.post('/api/project/ai/autoframing', data: {'video_path': videoPath});
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] autoFraming error: $e');
      return null;
    }
  }

  /// AI Upscale – تحسين دقة الفيديو
  Future<Map<String, dynamic>?> aiUpscale(String videoPath, {int factor = 2, String model = 'realesrgan'}) async {
    try {
      final response = await _dio.post('/api/ai/upscale', data: {
        'video_path': videoPath,
        'factor': factor,
        'model': model,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiUpscale error: $e');
      return null;
    }
  }

  /// AI Frame Interpolation – تعبئة الإطارات
  Future<Map<String, dynamic>?> aiInterpolate(String videoPath, {int fps = 60, String method = 'rife'}) async {
    try {
      final response = await _dio.post('/api/ai/interpolate', data: {
        'video_path': videoPath,
        'fps': fps,
        'method': method,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiInterpolate error: $e');
      return null;
    }
  }

  /// AI Object Removal – إزالة العناصر
  Future<Map<String, dynamic>?> aiRemoveObject(String videoPath, Map<String, dynamic> region, {String method = 'propainter'}) async {
    try {
      final response = await _dio.post('/api/ai/remove-object', data: {
        'video_path': videoPath,
        'region': region,
        'method': method,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiRemoveObject error: $e');
      return null;
    }
  }

  /// AI Background Replacement – استبدال الخلفية
  Future<Map<String, dynamic>?> aiBackgroundReplace(String videoPath, Map<String, dynamic> settings) async {
    try {
      final response = await _dio.post('/api/ai/background-replace', data: {
        'video_path': videoPath,
        'settings': settings,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiBackgroundReplace error: $e');
      return null;
    }
  }

  /// AI Video Generation – توليد فيديو
  Future<Map<String, dynamic>?> aiGenerateVideo(String prompt, {String style = 'cinematic', int duration = 5, String resolution = '720p'}) async {
    try {
      final response = await _dio.post('/api/ai/generate-video', data: {
        'prompt': prompt,
        'style': style,
        'duration': duration,
        'resolution': resolution,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiGenerateVideo error: $e');
      return null;
    }
  }

  /// AI Audio Enhancement – تحسين الصوت
  Future<Map<String, dynamic>?> aiEnhanceAudio(String videoPath, Map<String, dynamic> settings) async {
    try {
      final response = await _dio.post('/api/ai/enhance-audio', data: {
        'video_path': videoPath,
        'settings': settings,
      });
      return response.data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ApiClient] aiEnhanceAudio error: $e');
      return null;
    }
  }
}

