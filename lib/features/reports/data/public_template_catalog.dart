import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';

/// Loads only approved, versioned, patient-free templates from Ripot's catalogue.
/// No arbitrary remote URLs are accepted from the browser query string.
class PublicTemplateCatalog {
  static const _origin = 'https://ripot.app';
  static final _slug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static final _version = RegExp(r'^[a-f0-9]{16}$');

  static Future<TemplateDoc?> resolve(Uri uri) async {
    final slug = uri.queryParameters['template'];
    if (slug == null || !_slug.hasMatch(slug) || slug.length > 100) return null;
    final requestedVersion = uri.queryParameters['version'];
    if (requestedVersion != null && !_version.hasMatch(requestedVersion)) return null;
    final client = http.Client();
    try {
      final index = await client.get(Uri.parse('$_origin/templates/catalog/manifest.json'))
          .timeout(const Duration(seconds: 8));
      if (index.statusCode != 200 || index.bodyBytes.length > 200000) return null;
      final catalog = jsonDecode(utf8.decode(index.bodyBytes));
      if (catalog is! Map || catalog['schemaVersion'] != 1 || catalog['templates'] is! List) return null;
      final entries = (catalog['templates'] as List).whereType<Map>().where((entry) =>
          entry['slug'] == slug && entry['status'] == 'approved' &&
          (requestedVersion == null || entry['version'] == requestedVersion)).toList();
      if (entries.length != 1) return null;
      final entry = entries.single;
      final version = entry['version'];
      if (version is! String || !_version.hasMatch(version)) return null;
      final path = '/templates/catalog/$slug/$version.ripottemplate.json';
      if (entry['url'] != path) return null;
      final response = await client.get(Uri.parse('$_origin$path'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.bodyBytes.length > 250000) return null;
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map || payload['app'] != 'Ripot' ||
          payload['ripotFileType'] != 'template' || payload['ripotExportVersion'] != 1 ||
          payload['template'] is! Map) return null;
      final raw = Map<String, dynamic>.from(payload['template'] as Map);
      if (raw['name'] is! String || (raw['name'] as String).trim().isEmpty ||
          raw['roots'] is! List) return null;
      var count = 0;
      final ids = <String>{};
      bool validate(List nodes, int depth) {
        if (depth > 8 || count + nodes.length > 200) return false;
        for (final node in nodes) {
          if (node is! Map || node['type'] != 'section' && node['type'] != 'content') return false;
          final id = node['id'];
          if (id is! String || id.isEmpty || id.length > 120 || !ids.add(id)) return false;
          if (node['title'] is String && (node['title'] as String).length > 250) return false;
          count++;
          final children = node['children'];
          if (children != null && (children is! List || !validate(children, depth + 1))) return false;
        }
        return true;
      }
      if (!validate(raw['roots'] as List, 0) || count == 0) return null;
      // Prevent a public template from bringing saved patient or signature data.
      raw['templateId'] = 'public_$slug' + '_$version';
      raw['recordsConfigured'] = false;
      raw['signature'] = <String, dynamic>{};
      return TemplateCodec.templateFromJson(raw);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
