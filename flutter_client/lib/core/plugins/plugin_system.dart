import 'dart:io';
import 'package:flutter/material.dart';

abstract class ClipAIPlugin {
  String get id;
  String get name;
  String get version;
  String get description;
  String get author;

  Future<bool> initialize();
  void dispose();
}

abstract class EffectPlugin extends ClipAIPlugin {
  Widget buildUI(Map<String, dynamic> params, ValueChanged<Map<String, dynamic>> onChanged);
  Map<String, dynamic> process(Map<String, dynamic> input, Map<String, dynamic> params);
}

abstract class ExportPlugin extends ClipAIPlugin {
  Future<bool> export(String inputPath, String outputPath, Map<String, dynamic> options,
    void Function(double progress) onProgress);
}

class PluginManager {
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;
  PluginManager._internal();

  final Map<String, ClipAIPlugin> _plugins = {};
  final List<String> _loadErrors = [];

  List<ClipAIPlugin> get plugins => _plugins.values.toList();
  List<String> get loadErrors => List.unmodifiable(_loadErrors);

  void register(ClipAIPlugin plugin) {
    _plugins[plugin.id] = plugin;
  }

  void unregister(String id) {
    _plugins.remove(id)?.dispose();
  }

  T? get<T extends ClipAIPlugin>(String id) {
    final plugin = _plugins[id];
    if (plugin is T) return plugin;
    return null;
  }

  List<T> getAll<T extends ClipAIPlugin>() =>
    _plugins.values.whereType<T>().toList();

  Future<void> loadFromDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;

    await for (final entry in dir.list()) {
      if (entry is File && entry.path.endsWith('.yaml')) {
        try {
          final content = await entry.readAsString();
          final config = _parsePluginConfig(content);
          if (config != null) {
            debugPrint('[PluginManager] Loaded plugin config: ${config['name']}');
          }
        } catch (e) {
          _loadErrors.add('Failed to load ${entry.path}: $e');
        }
      }
    }
  }

  Map<String, dynamic>? _parsePluginConfig(String yaml) {
    try {
      final lines = yaml.split('\n');
      final config = <String, dynamic>{};
      for (final line in lines) {
        final parts = line.split(':');
        if (parts.length >= 2) {
          config[parts[0].trim()] = parts.sublist(1).join(':').trim();
        }
      }
      return config;
    } catch (_) {
      return null;
    }
  }

  Future<bool> initializeAll() async {
    bool allSuccess = true;
    for (final plugin in _plugins.values) {
      try {
        final success = await plugin.initialize();
        if (!success) {
          allSuccess = false;
          _loadErrors.add('Failed to initialize ${plugin.id}');
        }
      } catch (e) {
        allSuccess = false;
        _loadErrors.add('Error initializing ${plugin.id}: $e');
      }
    }
    return allSuccess;
  }

  void disposeAll() {
    for (final plugin in _plugins.values) {
      plugin.dispose();
    }
    _plugins.clear();
    _loadErrors.clear();
  }
}

class PluginMarketplace {
  static const List<Map<String, dynamic>> availablePlugins = [
    {'id': 'glitch_effect', 'name': 'Glitch Effect Pack', 'author': 'ClipAI', 'price': 'Free', 'rating': 4.5, 'downloads': 1200},
    {'id': 'neon_text', 'name': 'Neon Text Animator', 'author': 'ClipAI', 'price': '\$4.99', 'rating': 4.8, 'downloads': 850},
    {'id': 'audio_viz', 'name': 'Audio Visualizer', 'author': 'ClipAI', 'price': 'Free', 'rating': 4.6, 'downloads': 2100},
    {'id': '3d_title', 'name': '3D Title Builder', 'author': 'ClipAI', 'price': '\$9.99', 'rating': 4.3, 'downloads': 450},
    {'id': 'vhs_effect', 'name': 'VHS Retro Effect', 'author': 'ClipAI', 'price': '\$2.99', 'rating': 4.7, 'downloads': 3200},
    {'id': 'light_leaks', 'name': 'Light Leaks Pack', 'author': 'ClipAI', 'price': 'Free', 'rating': 4.4, 'downloads': 1800},
  ];
}
