import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';

class TemplateSummary {
  final String templateId;
  final String name;
  final DateTime updatedAt;

  const TemplateSummary({
    required this.templateId,
    required this.name,
    required this.updatedAt,
  });
}

class TemplatesRepository {
  static const _indexKey = 'templates.index';
  static const _prefix = 'templates.doc.';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();
  String _key(String templateId) => '$_prefix$templateId';

  Future<List<String>> _readIndex() async {
    final prefs = await _prefs;
    return prefs.getStringList(_indexKey) ?? <String>[];
  }

  Future<void> _writeIndex(List<String> ids) async {
    final prefs = await _prefs;
    await prefs.setStringList(_indexKey, ids);
  }

  Future<void> saveTemplate(TemplateDoc t) async {
    final prefs = await _prefs;
    await prefs.setString(_key(t.templateId), jsonEncode(TemplateCodec.templateToJson(t)));
    final ids = await _readIndex();
    ids.remove(t.templateId);
    ids.insert(0, t.templateId);
    await _writeIndex(ids);
  }

  Future<TemplateDoc> loadTemplate(String templateId) async {
    final prefs = await _prefs;
    final text = prefs.getString(_key(templateId));
    if (text == null || text.trim().isEmpty) {
      throw Exception('Template not found');
    }
    return TemplateCodec.templateFromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(String templateId) async {
    final prefs = await _prefs;
    await prefs.remove(_key(templateId));
    final ids = await _readIndex();
    ids.remove(templateId);
    await _writeIndex(ids);
  }

  Future<List<TemplateSummary>> listTemplates() async {
    final prefs = await _prefs;
    final ids = await _readIndex();
    final out = <TemplateSummary>[];
    for (final id in ids) {
      final text = prefs.getString(_key(id));
      if (text == null || text.trim().isEmpty) continue;
      try {
        final j = jsonDecode(text) as Map<String, dynamic>;
        out.add(
          TemplateSummary(
            templateId: j['templateId'] as String,
            name: (j['name'] as String?) ?? 'Untitled Template',
            updatedAt: DateTime.parse(j['updatedAtIso'] as String),
          ),
        );
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
}
