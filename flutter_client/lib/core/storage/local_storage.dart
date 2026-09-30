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
  ///
  /// حفظ جزئي (بدون [mediaFiles]/[comments]) **لا يمسح المكتبة ولا التعليقات**:
  /// يُقرأ الملف القائم ويُحتفظ بالمفاتيح. رايتر الـ debounce بعد كل تعديل
  /// لا يملك قائمة الملفات ولا يحق له حذفها — وإلا اختفت المكتبة بعد إعادة التشغيل.
  Future<void> saveAutosave(Map<String, dynamic> projectData,
      {List<Map<String, dynamic>>? mediaFiles,
      List<Map<String, dynamic>>? comments}) async {
    try {
      final dir = await _storageDir;
      final file = File(p.join(dir, _autosaveFileName));
      dynamic preservedMedia = mediaFiles;
      dynamic preservedComments = comments;
      if ((preservedMedia == null || preservedComments == null) &&
          await file.exists()) {
        try {
          final existing = jsonDecode(await file.readAsString());
          if (existing is Map<String, dynamic>) {
            preservedMedia ??= existing['mediaFiles'];
            preservedComments ??= existing['comments'];
          }
        } catch (_) {
          // ملف تالف — نكتبه من جديد من دون إسقاط البيانات الجديدة.
        }
      }
      final Map<String, dynamic> payload = {
        'timeline': projectData,
        if (preservedMedia != null) 'mediaFiles': preservedMedia,
        if (preservedComments != null) 'comments': preservedComments,
      };
      await writeFileAtomically(file, jsonEncode(payload));
      debugPrint('[LocalStorage] Autosave saved.');
    } catch (e) {
      debugPrint('[LocalStorage] Autosave error: $e');
    }
  }

  /// تحميل حالة المشروع من الملف المحلي — مع fallback لملف ‎.tmp إن انقطع
  /// البرنامج بين الحذف وإعادة التسمية أثناء كتابة ذرية سابقة.
  Future<Map<String, dynamic>?> loadAutosave() async {
    try {
      final dir = await _storageDir;
      final file = File(p.join(dir, _autosaveFileName));
      final target = await file.exists()
          ? file
          : File('${file.path}.tmp');
      if (await target.exists()) {
        final content = await target.readAsString();
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

/// كتابة ذرية: ملف مؤقت + flush + إعادة تسمية — انقطاع التيار أثناء
/// الكتابة لا يترك ملفًا مبتورًا (0-byte) بدل المشروع.
Future<void> writeFileAtomically(File target, String content) async {
  final tmp = File('${target.path}.tmp');
  await tmp.writeAsString(content, flush: true);
  if (await target.exists()) {
    await target.delete();
  }
  await tmp.rename(target.path);
}
