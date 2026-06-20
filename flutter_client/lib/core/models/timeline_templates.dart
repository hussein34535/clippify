import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TimelineTemplate {
  final String id;
  final String name;
  final String nameAr;
  final String category;
  final String? thumbnail;
  final Map<String, dynamic> state;
  final int createdAt;

  TimelineTemplate({
    required this.id,
    required this.name,
    required this.nameAr,
    required this.category,
    this.thumbnail,
    required this.state,
    required this.createdAt,
  });

  factory TimelineTemplate.fromJson(Map<String, dynamic> json) => TimelineTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        nameAr: json['nameAr'] as String? ?? '',
        category: json['category'] as String,
        thumbnail: json['thumbnail'] as String?,
        state: json['state'] as Map<String, dynamic>? ?? {},
        createdAt: json['createdAt'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'nameAr': nameAr,
        'category': category,
        'state': state,
        'createdAt': createdAt,
      };
}

const String _storageKey = 'clipai_templates';
const String _builtinKey = 'clipai_builtin_templates_seeded';

final List<TimelineTemplate> builtinTemplates = [
  TimelineTemplate(
    id: 'tpl_intro_classic',
    name: 'Classic Intro',
    nameAr: 'مقدمة كلاسيكية',
    category: 'intro',
    state: {
      'project_name': 'مقدمة كلاسيكية',
      'settings': {'width': 1080, 'height': 1920, 'fps': 30, 'sample_rate': 44100, 'aspect_ratio': '9:16'},
      'tracks': {
        'video': [{'id': 'v1', 'name': 'V1', 'index': 0, 'clips': []}],
        'audio': [{'id': 'a1', 'name': 'A1', 'index': 0, 'clips': []}],
        'subtitles': [{'id': 'sub1', 'clips': []}],
        'overlays': [{'id': 'ov1', 'clips': []}],
      },
    },
    createdAt: 0,
  ),
  TimelineTemplate(
    id: 'tpl_outro_subscribe',
    name: 'Subscribe Outro',
    nameAr: 'خاتمة (اشترك)',
    category: 'outro',
    state: {
      'project_name': 'خاتمة',
      'settings': {'width': 1080, 'height': 1920, 'fps': 30, 'sample_rate': 44100, 'aspect_ratio': '9:16'},
      'tracks': {
        'video': [{'id': 'v1', 'name': 'V1', 'index': 0, 'clips': []}],
        'audio': [{'id': 'a1', 'name': 'A1', 'index': 0, 'clips': []}],
        'subtitles': [{'id': 'sub1', 'clips': []}],
        'overlays': [{'id': 'ov1', 'clips': []}],
      },
    },
    createdAt: 0,
  ),
  TimelineTemplate(
    id: 'tpl_podcast',
    name: 'Podcast Style',
    nameAr: 'ستايل بودكاست',
    category: 'full',
    state: {
      'project_name': 'بودكاست',
      'settings': {'width': 1080, 'height': 1920, 'fps': 30, 'sample_rate': 44100, 'aspect_ratio': '9:16'},
      'tracks': {
        'video': [{'id': 'v1', 'name': 'V1', 'index': 0, 'clips': []}],
        'audio': [{'id': 'a1', 'name': 'Music', 'index': 0, 'clips': []}],
        'subtitles': [{'id': 'sub1', 'clips': []}],
        'overlays': [{'id': 'ov1', 'clips': []}],
      },
    },
    createdAt: 0,
  ),
];

Future<List<TimelineTemplate>> loadTemplates() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => TimelineTemplate.fromJson(e as Map<String, dynamic>)).toList();
  } catch (e) {
    debugPrint('[Templates] Load error: $e');
    return [];
  }
}

Future<void> ensureBuiltinTemplates() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final seeded = prefs.getString(_builtinKey);
    if (seeded != null) return;
    final existing = await loadTemplates();
    final merged = [...builtinTemplates, ...existing];
    await prefs.setString(_storageKey, jsonEncode(merged.map((t) => t.toJson()).toList()));
    await prefs.setString(_builtinKey, '1');
  } catch (e) {
    debugPrint('[Templates] Seed error: $e');
  }
}

Future<TimelineTemplate> saveTemplate(String name, String nameAr, String category, Map<String, dynamic> state) async {
  final tpl = TimelineTemplate(
    id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
    name: name,
    nameAr: nameAr,
    category: category,
    state: state,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
  final list = await loadTemplates();
  list.insert(0, tpl);
  final trimmed = list.take(100).toList();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey, jsonEncode(trimmed.map((t) => t.toJson()).toList()));
  return tpl;
}

Future<void> deleteTemplate(String id) async {
  final list = await loadTemplates();
  final keepPrefixes = ['tpl_intro', 'tpl_outro', 'tpl_podcast'];
  final filtered = list.where((t) => t.id != id || keepPrefixes.any((p) => id.startsWith(p))).toList();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey, jsonEncode(filtered.map((t) => t.toJson()).toList()));
}

Map<String, dynamic> applyTemplate(TimelineTemplate tpl, Map<String, dynamic> current) {
  return {
    ...current,
    'project_name': tpl.state['project_name'] ?? current['project_name'],
    'settings': tpl.state['settings'] ?? current['settings'],
    'tracks': tpl.state['tracks'] ?? current['tracks'],
  };
}
