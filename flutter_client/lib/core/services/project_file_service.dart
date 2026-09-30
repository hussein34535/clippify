import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recent_project.dart';
import '../models/timeline_models.dart';

/// حفظ/فتح/قائمة آخر المشاريع كملفات `.clippify` محلية.
///
/// استبدل نداءات `/api/project/{save,load,recent}` التي تردّ 501 (stub في
/// `legacy_endpoints.rs`) — زر الحفظ كان يفشل دائمًا ولا يُكتب أي ملف،
/// وقائمة "آخر المشاريع" كانت فارغة بصمت. الملف شكل واحد: JSON لـ
/// [TimelineState.toJson] (يقرأ أيضًا غلاف `{timeline: ...}` للتوافق).
class ProjectFileService {
  static final ProjectFileService _instance = ProjectFileService._internal();
  factory ProjectFileService() => _instance;
  ProjectFileService._internal();

  static const int _maxRecent = 10;

  Future<File> _recentFile() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Clippify'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'recent_projects.json'));
  }

  /// كتابة المشروع إلى [path] وتسجيله في "آخر المشاريع".
  Future<void> saveProject(TimelineState timeline, String path) async {
    final file = File(path);
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    await file.writeAsString(jsonEncode(timeline.toJson()));
    await _recordRecent(path, timeline.projectName);
  }

  /// قراءة مشروع من مسار — يرمي [FileSystemException]/[FormatException]
  /// عند فشل القراءة؛ المتصل يعرض رسالة خطأ للمستخدم.
  Future<TimelineState> loadProject(String path) async {
    final content = await File(path).readAsString();
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('ملف المشروع ليس JSON صالحًا');
    }
    final inner = data['timeline'];
    final timelineJson = inner is Map<String, dynamic> ? inner : data;
    return TimelineState.fromJson(timelineJson);
  }

  /// آخر المشاريع المحفوظة (الأحدث أولًا).
  Future<List<RecentProject>> recentProjects() async {
    try {
      final file = await _recentFile();
      if (!await file.exists()) return const [];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return const [];
      final result = <RecentProject>[];
      for (final entry in data) {
        if (entry is! Map<String, dynamic>) continue;
        final path = entry['path'] as String?;
        if (path == null || path.isEmpty) continue;
        final name = (entry['name'] as String?) ??
            p.basenameWithoutExtension(path);
        result.add(RecentProject(name: name, path: path));
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _recordRecent(String path, String name) async {
    try {
      final file = await _recentFile();
      final existing = await recentProjects();
      final entries = <Map<String, dynamic>>[
        {'path': path, 'name': name.isEmpty ? p.basenameWithoutExtension(path) : name},
        for (final r in existing)
          if (r.path != path) {'path': r.path, 'name': r.name},
      ];
      await file.writeAsString(jsonEncode(entries.take(_maxRecent).toList()));
    } catch (e) {
      debugPrint('[ProjectFileService] recent update failed: $e');
    }
  }
}
