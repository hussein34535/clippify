import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class LocalStorage {
  static final LocalStorage _instance = LocalStorage._internal();
  factory LocalStorage() => _instance;
  LocalStorage._internal();

  static const String _autosaveFileName = 'clippify_autosave.json';

  String? _cachedDir;

  Future<String> get _storageDir async {
    if (_cachedDir != null) return _cachedDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = p.join(appDir.path, 'Clippify');
    final dirObj = Directory(dir);
    if (!await dirObj.exists()) {
      await dirObj.create(recursive: true);
    }
    _cachedDir = dir;
    return dir;
  }

  /// حفظ حالة المشروع تلقائياً في ملف محلي (تضمين ملفات الميديا)
  Future<void> saveAutosave(Map<String, dynamic> projectData, {List<Map<String, dynamic>>? mediaFiles}) async {
    try {
      final dir = await _storageDir;
      final Map<String, dynamic> payload = {
        'timeline': projectData,
        if (mediaFiles != null) 'mediaFiles': mediaFiles,
      };
      final file = File(p.join(dir, _autosaveFileName));
      await file.writeAsString(jsonEncode(payload));
      debugPrint('[LocalStorage] Autosave saved.');
    } catch (e) {
      debugPrint('[LocalStorage] Autosave error: $e');
    }
  }

  /// تحميل حالة المشروع من الملف المحلي
  Future<Map<String, dynamic>?> loadAutosave() async {
    try {
      final dir = await _storageDir;
      final file = File(p.join(dir, _autosaveFileName));
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('[LocalStorage] Load autosave error: $e');
    }
    return null;
  }

  /// حذف ملف autosave (بعد الحفظ اليدوي مثلاً)
  Future<void> clearAutosave() async {
    try {
      final dir = await _storageDir;
      final file = File(p.join(dir, _autosaveFileName));
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[LocalStorage] Clear autosave error: $e');
    }
  }
}
