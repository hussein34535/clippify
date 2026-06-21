import 'dart:io';
import 'package:flutter/material.dart';

class WorkspacePreset {
  final String id;
  final String name;
  final String description;
  final Map<String, double> panelFractions;

  const WorkspacePreset({
    required this.id, required this.name, required this.description,
    required this.panelFractions,
  });

  static const List<WorkspacePreset> presets = [
    WorkspacePreset(
      id: 'editing', name: 'مونتاج', description: 'تركيز على التايملاين',
      panelFractions: {'left': 0.15, 'right': 0.2, 'bottom': 0.4},
    ),
    WorkspacePreset(
      id: 'color', name: 'تلوين', description: 'تركيز على الألوان',
      panelFractions: {'left': 0.15, 'right': 0.35, 'bottom': 0.3},
    ),
    WorkspacePreset(
      id: 'audio', name: 'صوت', description: 'تركيز على الصوت',
      panelFractions: {'left': 0.2, 'right': 0.25, 'bottom': 0.35},
    ),
    WorkspacePreset(
      id: 'effects', name: 'تأثيرات', description: 'تركيز على التأثيرات',
      panelFractions: {'left': 0.2, 'right': 0.35, 'bottom': 0.3},
    ),
    WorkspacePreset(
      id: 'minimal', name: 'بسيط', description: 'أقل عدد من اللوحات',
      panelFractions: {'left': 0.15, 'right': 0.2, 'bottom': 0.45},
    ),
  ];
}

class WorkspaceManager {
  String _currentId = 'editing';

  String get currentId => _currentId;
  WorkspacePreset get current => WorkspacePreset.presets.firstWhere((p) => p.id == _currentId);

  void switchTo(String id) {
    if (WorkspacePreset.presets.any((p) => p.id == id)) {
      _currentId = id;
    }
  }

  Map<String, double> get fractions => current.panelFractions;
}



class SecondScreenManager {
  static bool get hasSecondScreen => false;

  static Future<void> openPreview(String videoPath) async {
    if (!hasSecondScreen) return;
    try {
      await Process.run(
        Platform.isWindows ? 'start' : (Platform.isMacOS ? 'open' : 'xdg-open'),
        [videoPath],
        runInShell: true,
      );
    } catch (_) {}
  }
}
