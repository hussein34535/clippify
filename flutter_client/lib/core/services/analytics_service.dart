import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _storageKey = 'clipai_analytics';
const int _maxEvents = 5000;

class AnalyticsEvent {
  final String type;
  final String? category;
  final String? toolName;
  final int? durationMs;
  final int timestamp;
  final String? projectId;

  AnalyticsEvent({
    required this.type,
    this.category,
    this.toolName,
    this.durationMs,
    required this.timestamp,
    this.projectId,
  });

  factory AnalyticsEvent.fromJson(Map<String, dynamic> json) => AnalyticsEvent(
        type: json['type'] as String,
        category: json['category'] as String?,
        toolName: json['toolName'] as String?,
        durationMs: json['durationMs'] as int?,
        timestamp: json['timestamp'] as int,
        projectId: json['projectId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        if (category != null) 'category': category,
        if (toolName != null) 'toolName': toolName,
        if (durationMs != null) 'durationMs': durationMs,
        'timestamp': timestamp,
        if (projectId != null) 'projectId': projectId,
      };
}

class AnalyticsSummary {
  final int totalEvents;
  final int totalAiActions;
  final int totalExports;
  final int totalComments;
  final int totalMacros;
  final int totalEdits;
  final int totalVoiceCommands;
  final List<MapEntry<String, int>> topTools;
  final List<MapEntry<String, int>> topCategories;
  final List<int> byHour;
  final List<int> byDay;
  final int averageEditMs;
  final int estimatedTimeSavedMin;

  AnalyticsSummary({
    required this.totalEvents,
    required this.totalAiActions,
    required this.totalExports,
    required this.totalComments,
    required this.totalMacros,
    required this.totalEdits,
    required this.totalVoiceCommands,
    required this.topTools,
    required this.topCategories,
    required this.byHour,
    required this.byDay,
    required this.averageEditMs,
    required this.estimatedTimeSavedMin,
  });
}

List<AnalyticsEvent> _loadEvents(List<dynamic> raw) {
  return raw.map((e) => AnalyticsEvent.fromJson(e as Map<String, dynamic>)).toList();
}

Future<List<AnalyticsEvent>> loadAnalytics() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return _loadEvents(list);
  } catch (e) {
    debugPrint('[Analytics] Load error: $e');
    return [];
  }
}

Future<void> trackEvent(String type, {String? category, String? toolName, int? durationMs, String? projectId}) async {
  final events = await loadAnalytics();
  events.add(AnalyticsEvent(
    type: type,
    category: category,
    toolName: toolName,
    durationMs: durationMs,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    projectId: projectId,
  ));
  final trimmed = events.take(_maxEvents).toList();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
}

Future<AnalyticsSummary> getAnalyticsSummary() async {
  final events = await loadAnalytics();
  final toolCounts = <String, int>{};
  final categoryCounts = <String, int>{};
  final byHour = List.filled(24, 0);
  final byDay = List.filled(7, 0);
  int totalEditMs = 0;
  int editCount = 0;
  final now = DateTime.now().millisecondsSinceEpoch;
  const dayMs = 24 * 60 * 60 * 1000;

  for (final e in events) {
    if (e.toolName != null) {
      toolCounts[e.toolName!] = (toolCounts[e.toolName!] ?? 0) + 1;
    }
    if (e.category != null) {
      categoryCounts[e.category!] = (categoryCounts[e.category!] ?? 0) + 1;
    }
    final hour = DateTime.fromMillisecondsSinceEpoch(e.timestamp).hour;
    byHour[hour]++;
    final daysAgo = ((now - e.timestamp) / dayMs).floor();
    if (daysAgo >= 0 && daysAgo < 7) byDay[6 - daysAgo]++;
    if (e.type == 'edit' && e.durationMs != null) {
      totalEditMs += e.durationMs!;
      editCount++;
    }
  }

  final sortedTools = toolCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final sortedCategories = categoryCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  return AnalyticsSummary(
    totalEvents: events.length,
    totalAiActions: events.where((e) => e.type == 'ai_action').length,
    totalExports: events.where((e) => e.type == 'export').length,
    totalComments: events.where((e) => e.type == 'comment').length,
    totalMacros: events.where((e) => e.type == 'macro').length,
    totalEdits: events.where((e) => e.type == 'edit').length,
    totalVoiceCommands: events.where((e) => e.type == 'voice').length,
    topTools: sortedTools.take(10).toList(),
    topCategories: sortedCategories.take(7).toList(),
    byHour: byHour,
    byDay: byDay,
    averageEditMs: editCount > 0 ? (totalEditMs / editCount).round() : 0,
    estimatedTimeSavedMin: (events.where((e) => e.type == 'ai_action').length * 0.5).round(),
  );
}

Future<void> clearAnalytics() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_storageKey);
}
