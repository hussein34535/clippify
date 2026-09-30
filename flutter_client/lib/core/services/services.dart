import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/timeline_models.dart';
import '../storage/local_storage.dart';

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

  void start(TimelineState Function() getState, {
    Duration interval = const Duration(minutes: 5),
    List<Map<String, dynamic>> Function()? getMediaFiles,
  }) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) {
      try {
        saveNow(getState(), mediaFiles: getMediaFiles?.call());
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
