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

class ThemePreset {
  final String name;
  final Color primaryColor;
  final Color surfaceColor;
  final Color backgroundColor;
  final Color textColor;
  final Brightness brightness;

  const ThemePreset({
    required this.name,
    required this.primaryColor,
    required this.surfaceColor,
    required this.backgroundColor,
    required this.textColor,
    this.brightness = Brightness.dark,
  });

  ThemeData toThemeData() {
    return ThemeData(
      brightness: brightness,
      colorSchemeSeed: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      useMaterial3: true,
    );
  }

  static const List<ThemePreset> presets = [
    ThemePreset(name: 'ClipAI Dark', primaryColor: Color(0xFF7C6AF7), surfaceColor: Color(0xFF131317), backgroundColor: Color(0xFF0A0A0D), textColor: Color(0xFFFFFFFF)),
    ThemePreset(name: 'ClipAI Light', primaryColor: Color(0xFF7C6AF7), surfaceColor: Color(0xFFF5F5F7), backgroundColor: Color(0xFFFFFFFF), textColor: Color(0xFF000000), brightness: Brightness.light),
    ThemePreset(name: 'Midnight', primaryColor: Color(0xFF00D4FF), surfaceColor: Color(0xFF0D1117), backgroundColor: Color(0xFF05080F), textColor: Color(0xFFFFFFFF)),
    ThemePreset(name: 'Sunset', primaryColor: Color(0xFFFF6B6B), surfaceColor: Color(0xFF1A1418), backgroundColor: Color(0xFF0F0A0E), textColor: Color(0xFFFFFFFF)),
    ThemePreset(name: 'Forest', primaryColor: Color(0xFF10B981), surfaceColor: Color(0xFF0F1713), backgroundColor: Color(0xFF070D09), textColor: Color(0xFFFFFFFF)),
    ThemePreset(name: 'Ocean', primaryColor: Color(0xFF38BDF8), surfaceColor: Color(0xFF0F172A), backgroundColor: Color(0xFF020617), textColor: Color(0xFFFFFFFF)),
  ];
}

class CustomThemeManager {
  String _currentId = 'ClipAI Dark';

  String get currentId => _currentId;
  ThemePreset get current => ThemePreset.presets.firstWhere((p) => p.name == _currentId);

  void switchTo(String name) {
    if (ThemePreset.presets.any((p) => p.name == name)) {
      _currentId = name;
    }
  }

  ThemeData get theme => current.toThemeData();
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
