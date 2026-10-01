import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/local_storage.dart';
import 'reference_dna.dart';

/// حفظ/تحميل بصمات القنوات المرجعية — `Documents/Clippify/style_dna/*.json`.
///
/// الملف كيلوبايتات (البصمة لا الفيديو — المرجعي يُمسح بعد الاستخراج).
class ReferenceDnaStore {
  static final ReferenceDnaStore _instance = ReferenceDnaStore._internal();
  factory ReferenceDnaStore() => _instance;
  ReferenceDnaStore._internal();

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'Clippify', 'style_dna'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _fileName(String name) {
    final safe = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim();
    final base = safe.isEmpty ? 'style' : safe;
    return base.endsWith('.json') ? base : '$base.json';
  }

  Future<void> save(String name, ReferenceDna dna) async {
    final dir = await _dir();
    await writeFileAtomically(
        File(p.join(dir.path, _fileName(name))), dna.encode());
  }

  Future<ReferenceDna?> load(String name) async {
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, _fileName(name)));
      if (!await file.exists()) return null;
      return ReferenceDna.decode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> list() async {
    try {
      final dir = await _dir();
      final out = <String>[];
      await for (final e in dir.list()) {
        if (e is File && e.path.toLowerCase().endsWith('.json')) {
          out.add(p.basenameWithoutExtension(e.path));
        }
      }
      out.sort();
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<bool> delete(String name) async {
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, _fileName(name)));
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// تصدير/استيراد نصي (مشاركة بصمة كنص).
  String exportText(ReferenceDna dna) => dna.encode();

  ReferenceDna? importText(String raw) {
    try {
      return ReferenceDna.decode(raw);
    } catch (_) {
      return null;
    }
  }

  /// قراءة خام لاختبارات التوافق.
  Map<String, dynamic>? tryDecode(String raw) {
    try {
      final data = jsonDecode(raw);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }
}
