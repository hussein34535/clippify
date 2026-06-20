import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/timeline_models.dart';
import '../storage/local_storage.dart';
import '../api/api_client.dart';

class ServiceLocator {
  static final ServiceLocator _instance = ServiceLocator._internal();
  factory ServiceLocator() => _instance;
  ServiceLocator._internal();

  final Map<Type, dynamic> _services = {};

  T register<T>(T service) {
    _services[T] = service;
    return service;
  }

  T get<T>() {
    if (!_services.containsKey(T)) {
      throw Exception('Service $T not registered');
    }
    return _services[T] as T;
  }

  bool has<T>() => _services.containsKey(T);

  void unregister<T>() => _services.remove(T);

  void clear() => _services.clear();
}

/// Service for managing autosave logic
class AutosaveService {
  Timer? _timer;
  final LocalStorage _storage = LocalStorage();
  bool _enabled = true;

  bool get enabled => _enabled;

  void start(TimelineState Function() getState, {Duration interval = const Duration(minutes: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      try {
        final state = getState();
        saveNow(state);
      } catch (e) {
        debugPrint('[AutosaveService] Error: $e');
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) stop();
  }

  Future<void> saveNow(TimelineState state, {List<Map<String, dynamic>>? mediaFiles}) async {
    if (!_enabled) return;
    await _storage.saveAutosave(state.toJson(), mediaFiles: mediaFiles);
  }

  Future<TimelineState?> loadLast() async {
    final data = await _storage.loadAutosave();
    if (data == null) return null;
    final timelineData = data['timeline'] as Map<String, dynamic>?;
    if (timelineData == null) return null;
    return TimelineState.fromJson(timelineData);
  }

  Future<List<Map<String, dynamic>>?> loadMediaFiles() async {
    final data = await _storage.loadAutosave();
    if (data == null) return null;
    return data['mediaFiles'] as List<Map<String, dynamic>>?;
  }

  void dispose() {
    stop();
  }
}

class ExportResult {
  final bool success;
  final String? outputPath;
  final String? error;
  final String? sessionId;

  ExportResult({required this.success, this.outputPath, this.error, this.sessionId});
}

class ExportService {
  final ApiClient _api = ApiClient();
  ExportResult? _lastResult;

  ExportResult? get lastResult => _lastResult;

  Future<ExportResult> exportXml(Map<String, dynamic> timelineData, {
    required String outputPath,
    String format = 'premiere',
    bool includeSubtitles = true,
  }) async {
    try {
      final res = await _api.exportXml(timelineData, outputPath: outputPath, format: format);
      switch (res) {
        case Success(data: final data):
          _lastResult = ExportResult(
            success: data['status'] == 'success',
            outputPath: outputPath,
            error: data['error'] as String?,
          );
        case Failure():
          _lastResult = ExportResult(success: false, error: 'Export XML failed');
      }
      return _lastResult!;
    } catch (e) {
      _lastResult = ExportResult(success: false, error: e.toString());
      return _lastResult!;
    }
  }

  Future<ExportResult> exportVideo({
    required String videoPath,
    required List<Map<String, dynamic>> clips,
    String? outputPath,
    String quality = 'high',
    String? presetName,
    String? codec,
    String? pixelFormat,
  }) async {
    try {
      if (videoPath.isEmpty) {
        return ExportResult(success: false, error: 'Video path is required');
      }
      final sid = await _api.renderPlan(
        videoPath: videoPath,
        clips: clips,
        exportQuality: quality,
        presetName: presetName,
        codec: codec,
        pixelFormat: pixelFormat,
      );
      switch (sid) {
        case Success(data: final sessionId):
          _lastResult = ExportResult(
            success: true,
            outputPath: outputPath,
            sessionId: sessionId,
            error: null,
          );
        case Failure():
          _lastResult = ExportResult(success: false, outputPath: outputPath, error: 'Render plan failed');
      }
      return _lastResult!;
    } catch (e) {
      _lastResult = ExportResult(success: false, error: e.toString());
      return _lastResult!;
    }
  }
}
