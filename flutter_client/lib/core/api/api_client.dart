import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

sealed class ApiResult<T> {
  const ApiResult();
}

final class Success<T> extends ApiResult<T> {
  final T data;
  const Success(this.data);
}

final class Failure<T> extends ApiResult<T> {
  final String message;
  final int? statusCode;
  final String? endpoint;
  const Failure(this.message, {this.statusCode, this.endpoint});
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  
  late final Dio _dio;
  
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(minutes: 5),
      headers: {
        'Content-Type': 'application/json',
      },
    ));
  }

  Dio get dio => _dio;

  Future<ApiResult<Map<String, dynamic>>> getSettings() async {
    try {
      final response = await _dio.get('/api/settings');
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/settings');
    }
  }

  Future<ApiResult<bool>> postSettings(Map<String, dynamic> settings) async {
    try {
      final response = await _dio.post('/api/settings', data: settings);
      return Success(response.data['status'] == 'success');
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/settings');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> clearCache() async {
    try {
      final response = await _dio.post('/api/clear-cache');
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/clear-cache');
    }
  }

  Future<ApiResult<String>> downloadYoutube(String url) async {
    try {
      final response = await _dio.post('/api/download-youtube', data: {'url': url});
      return Success(response.data['session_id'] as String);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/download-youtube');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> getSessionStatus(String sessionId) async {
    try {
      final response = await _dio.get('/api/status', queryParameters: {'session_id': sessionId});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/status');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> transcribe(String videoPath) async {
    try {
      final response = await _dio.post('/api/transcribe', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/transcribe');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> detectSilence(String videoPath, {int minSilenceDurationMs = 500, double threshold = 0.5}) async {
    try {
      final response = await _dio.post('/api/detect-silence', data: {
        'video_path': videoPath,
        'min_silence_duration_ms': minSilenceDurationMs,
        'threshold': threshold,
      });
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/detect-silence');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> copilotChat({
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
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/copilot/chat');
    }
  }

  Future<ApiResult<String>> analyzeVideo(String videoPath, {String contentType = 'podcast'}) async {
    try {
      final response = await _dio.post('/api/analyze-video', data: {
        'video_path': videoPath,
        'content_type': contentType,
      });
      return Success(response.data['session_id'] as String);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/analyze-video');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> generatePlan({
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
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/generate-plan');
    }
  }

  Future<ApiResult<String>> renderPlan({
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
      return Success(response.data['session_id'] as String);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/render-plan');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> getAITools() async {
    try {
      final response = await _dio.get('/api/ai/tools');
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/ai/tools');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> executeAIActions(List<Map<String, dynamic>> actions, Map<String, dynamic> timelineState) async {
    try {
      final response = await _dio.post('/api/ai/execute', data: {
        'actions': actions,
        'timeline_state': timelineState,
      });
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/ai/execute');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> saveProject(Map<String, dynamic> timeline, {String? outputPath}) async {
    try {
      final response = await _dio.post('/api/project/save', data: {
        'timeline': timeline,
        'output_path': outputPath,
      });
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/save');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> loadProject(String path) async {
    try {
      final response = await _dio.get('/api/project/load', queryParameters: {'path': path});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/load');
    }
  }

  Future<ApiResult<List<dynamic>>> getRecentProjects() async {
    try {
      final response = await _dio.get('/api/project/recent');
      return Success(response.data as List<dynamic>? ?? []);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/recent');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> renderTimeline(Map<String, dynamic> timeline, {String? outputFilename}) async {
    try {
      final response = await _dio.post('/api/project/render/timeline', data: {
        'timeline': timeline,
        'output_filename': outputFilename,
      });
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/render/timeline');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> exportXml(Map<String, dynamic> timeline, {String? outputPath, String format = 'davinci'}) async {
    try {
      final response = await _dio.post('/api/project/export/xml', data: {
        'timeline': timeline,
        'output_path': outputPath,
        'format': format,
      });
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/export/xml');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> getMediaInfo(String videoPath, {double? timestampSec}) async {
    try {
      final Map<String, dynamic> payload = {'path': videoPath};
      if (timestampSec != null) {
        payload['timestamp_sec'] = timestampSec;
      }
      final response = await _dio.post('/api/media-info', data: payload);
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/media-info');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> analyzeBeats(String audioPath) async {
    try {
      final response = await _dio.post('/api/analyze-beats', data: {'audio_path': audioPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/analyze-beats');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> styleAnalyze(String videoPath) async {
    try {
      final response = await _dio.post('/api/style/analyze-reference', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/style/analyze-reference');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> styleImitate(String videoPath, String styleProfile) async {
    try {
      final response = await _dio.post('/api/style/imitate', data: {'video_path': videoPath, 'style_profile': styleProfile});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/style/imitate');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> brollSearch(String query) async {
    try {
      final response = await _dio.post('/api/broll/search', data: {'query': query});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/broll/search');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> brollDownload(String downloadUrl) async {
    try {
      final response = await _dio.post('/api/broll/download', data: {'download_url': downloadUrl});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/broll/download');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> audioSeparate(String videoPath) async {
    try {
      final response = await _dio.post('/api/audio/separate', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/audio/separate');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> audioDucking(String videoPath) async {
    try {
      final response = await _dio.post('/api/audio/ducking', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/audio/ducking');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> viralRecommendations(String videoPath) async {
    try {
      final response = await _dio.post('/api/viral/recommendations', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/viral/recommendations');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> autoFraming(String videoPath) async {
    try {
      final response = await _dio.post('/api/project/ai/autoframing', data: {'video_path': videoPath});
      return Success(response.data as Map<String, dynamic>);
    } catch (e) {

      return Failure(_parseError(e), endpoint: '/api/project/ai/autoframing');
    }
  }

  Future<ApiResult<Map<String, dynamic>>> aiUpscale(String videoPath, {int factor = 2, String model = 'realesrgan'}) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/upscale');
  }

  Future<ApiResult<Map<String, dynamic>>> aiInterpolate(String videoPath, {int fps = 60, String method = 'rife'}) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/interpolate');
  }

  Future<ApiResult<Map<String, dynamic>>> aiRemoveObject(String videoPath, Map<String, dynamic> region, {String method = 'propainter'}) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/remove-object');
  }

  Future<ApiResult<Map<String, dynamic>>> aiBackgroundReplace(String videoPath, Map<String, dynamic> settings) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/background-replace');
  }

  Future<ApiResult<Map<String, dynamic>>> aiGenerateVideo(String prompt, {String style = 'cinematic', int duration = 5, String resolution = '720p'}) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/generate-video');
  }

  Future<ApiResult<Map<String, dynamic>>> aiEnhanceAudio(String videoPath, Map<String, dynamic> settings) async {
    return const Failure('Feature not available (requires backend plugin)', endpoint: '/api/ai/enhance-audio');
  }

  static String _parseError(Object e) {
    if (e is DioException) {
      return e.message ?? e.toString();
    }
    return e.toString();
  }
}
