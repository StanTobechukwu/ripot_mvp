import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/letterhead_template.dart';

class LetterheadsRepository {
  static const _indexKey = 'letterheads.index';
  static const _prefix = 'letterheads.doc.';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();
  String _key(String id) => '$_prefix$id';

  Future<List<String>> _readIndexIds() async {
    final prefs = await _prefs;
    return prefs.getStringList(_indexKey) ?? <String>[];
  }

  Future<void> _writeIndexIds(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_indexKey, ids);
  }

  Future<List<LetterheadTemplate>> listLetterheads() async {
    final ids = await _readIndexIds();
    final items = <LetterheadTemplate>[];
    for (final id in ids) {
      try {
        items.add(await loadLetterhead(id));
      } catch (_) {}
    }
    return items;
  }

  Future<List<LetterheadTemplate>> loadAll() => listLetterheads();

  Future<LetterheadTemplate> loadLetterhead(String letterheadId) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_key(letterheadId));
    if (raw == null || raw.trim().isEmpty) {
      throw Exception('Letterhead not found');
    }
    return LetterheadTemplate.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveLetterhead(LetterheadTemplate t) async {
    final prefs = await _prefs;
    await prefs.setString(_key(t.letterheadId), jsonEncode(t.toJson()));
    final ids = await _readIndexIds();
    if (!ids.contains(t.letterheadId)) {
      ids.insert(0, t.letterheadId);
      await _writeIndexIds(ids);
    }
  }

  Future<void> deleteLetterhead(String letterheadId) async {
    final prefs = await _prefs;
    await prefs.remove(_key(letterheadId));
    final ids = await _readIndexIds();
    ids.remove(letterheadId);
    await _writeIndexIds(ids);
  }
}
