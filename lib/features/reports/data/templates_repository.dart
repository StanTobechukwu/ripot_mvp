import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
  Future<Directory> _templatesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/templates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _templateFile(String templateId) async {
    final dir = await _templatesDir();
    return File('${dir.path}/$templateId.json');
  }

  Future<void> saveTemplate(TemplateDoc t) async {
    final f = await _templateFile(t.templateId);
    await f.writeAsString(jsonEncode(TemplateCodec.templateToJson(t)), flush: true);
  }

  Future<TemplateDoc> loadTemplate(String templateId) async {
    final f = await _templateFile(templateId);
    final text = await f.readAsString();
    return TemplateCodec.templateFromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<void> deleteTemplate(String templateId) async {
    final f = await _templateFile(templateId);
    if (await f.exists()) await f.delete();
  }

  Future<List<TemplateSummary>> listTemplates() async {
    final dir = await _templatesDir();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();

    final out = <TemplateSummary>[];
    for (final f in files) {
      try {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        out.add(
          TemplateSummary(
            templateId: j['templateId'] as String,
            name: (j['name'] as String?) ?? 'Untitled Template',
            updatedAt: DateTime.parse(j['updatedAtIso'] as String),
          ),
        );
      } catch (_) {
        // ignore corrupted file
      }
    }

    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
}
