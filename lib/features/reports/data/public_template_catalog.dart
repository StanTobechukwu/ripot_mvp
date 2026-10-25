import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import '../domain/models/template_doc.dart';
import '../domain/serialization/template_codec.dart';
import '../domain/public_template_links.dart';

/// Loads only approved, versioned, patient-free templates from Ripot's catalogue.
/// No arbitrary remote URLs are accepted from the browser query string.
class PublicTemplateCatalog {
  static const _origin = 'https://ripot.app';
  static const communityEndpoint = 'https://us-central1-ripot-4edf7.cloudfunctions.net/publicTemplateLibrary';
  static final _slug = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');
  static final _version = RegExp(r'^[a-f0-9]{16}$');

  /// Versioned links must resolve the exact published payload, never a bundled
  /// template with a potentially different structure. Keep old unversioned
  /// starter links usable offline.
  static Future<TemplateDoc?> resolveForEditor(Uri uri, {void Function(String)? onLatestVersion}) async {
    if (!uri.queryParameters.containsKey('version')) {
      final bundled = PublicTemplateLinks.resolve(uri);
      if (bundled != null) return bundled;
    }
    return resolve(uri, onLatestVersion: onLatestVersion);
  }

  static Future<TemplateDoc?> resolve(Uri uri, {void Function(String)? onLatestVersion}) async {
    final slug = uri.queryParameters['template'];
    if (slug == null || !_slug.hasMatch(slug) || slug.length > 100) return null;
    final requestedVersion = uri.queryParameters['version'];
    if (requestedVersion != null && !_version.hasMatch(requestedVersion)) return null;
    final client = http.Client();
    try {
      Map entry;
      List<int> bytes;
      if (slug.startsWith('community-')) {
        final response = await client.get(Uri.parse(communityEndpoint).replace(
          queryParameters: {'template': slug, if (requestedVersion != null) 'version': requestedVersion},
        )).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 || response.bodyBytes.length > 350000) return null;
        final detail = jsonDecode(utf8.decode(response.bodyBytes));
        if (detail is! Map || detail['slug'] != slug || detail['status'] != 'approved' || detail['payload'] is! String) return null;
        entry = detail;
        if (detail['latestVersion'] is String) onLatestVersion?.call(detail['latestVersion'] as String);
        bytes = utf8.encode(detail['payload'] as String);
      } else {
        final index = await client.get(Uri.parse('$_origin/templates/catalog/manifest.json'))
            .timeout(const Duration(seconds: 8));
        if (index.statusCode != 200 || index.bodyBytes.length > 200000) return null;
        final catalog = jsonDecode(utf8.decode(index.bodyBytes));
        if (catalog is! Map || catalog['schemaVersion'] != 1 || catalog['templates'] is! List) return null;
        final entries = (catalog['templates'] as List).whereType<Map>().where((entry) =>
            entry['slug'] == slug && entry['status'] == 'approved').toList();
        if (entries.length != 1) return null;
        entry = entries.single;
        if (entry['version'] is String) onLatestVersion?.call(entry['version'] as String);
        if (requestedVersion != null && entry['version'] != requestedVersion) {
          final history = entry['versions'];
          if (history is! List) return null;
          final matches = history.whereType<Map>().where((v) => v['version'] == requestedVersion).toList();
          if (matches.length != 1) return null;
          entry = {...entry, ...matches.single, 'status': 'approved'};
        }
        final path = '/templates/catalog/$slug/${entry['version']}.ripottemplate.json';
        if (entry['url'] != path) return null;
        final response = await client.get(Uri.parse('$_origin$path'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;
        bytes = response.bodyBytes;
      }
      final version = entry['version'];
      if (version is! String || !_version.hasMatch(version) ||
          (requestedVersion != null && requestedVersion != version) || bytes.length > 250000) return null;
      final expectedHash = entry['sha256'];
      if (expectedHash is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash) ||
          crypto.sha256.convert(bytes).toString() != expectedHash ||
          expectedHash.substring(0, 16) != version) return null;
      final payload = jsonDecode(utf8.decode(bytes));
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
          if (count > 200) return false;
          // A public catalogue must not configure patient registry or logbook writes.
          node['addToRecords'] = false;
          node['addToLog'] = false;
          final children = node['children'];
          if (children != null && (children is! List || !validate(children, depth + 1))) return false;
        }
        return true;
      }
      // The decoder expects top-level sections, never content nodes.
      if ((raw['roots'] as List).any((node) => node is! Map || node['type'] != 'section')) return null;
      if (!validate(raw['roots'] as List, 0) || count == 0) return null;
      // Prevent a public template from bringing saved patient or signature data.
      raw['templateId'] = 'public_$slug' + '_$version';
      raw['sourceSlug'] = slug;
      raw['sourceVersion'] = version;
      raw['contributor'] = entry['contributor'] is String ? entry['contributor'] : '';
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

class CatalogPage {
  const CatalogPage(this.entries, this.unavailable);
  final List<Map<String, dynamic>> entries;
  final List<String> unavailable;
}

Future<CatalogPage> loadOnlineTemplates() async {
  final entries = <Map<String, dynamic>>[];
  final unavailable = <String>[];
  final client = http.Client();
  try {
    for (final source in ['Starter templates', 'Community templates']) {
      try {
        String? cursor;
        var pages = 0;
        do {
          final uri = source == 'Starter templates'
              ? Uri.parse('https://ripot.app/templates/catalog/manifest.json')
              : Uri.parse(PublicTemplateCatalog.communityEndpoint).replace(queryParameters: {
                  if (cursor != null) 'cursor': cursor,
                });
          final response = await client.get(uri).timeout(const Duration(seconds: 8));
          if (response.statusCode != 200 || response.bodyBytes.length > 1000000) throw const FormatException();
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is! Map || data['schemaVersion'] != 1 || data['templates'] is! List) throw const FormatException();
          for (final item in data['templates'] as List) {
            if (item is! Map || item['status'] != 'approved' ||
                item['slug'] is! String || item['version'] is! String || item['name'] is! String ||
                !PublicTemplateCatalog._slug.hasMatch(item['slug']) ||
                !PublicTemplateCatalog._version.hasMatch(item['version'])) continue;
            entries.add(Map<String, dynamic>.from(item));
          }
          cursor = data['cursor'] as String?;
          if (++pages >= 20 && cursor != null) throw const FormatException();
        } while (cursor != null);
      } catch (_) { unavailable.add(source); }
    }
    return CatalogPage(entries, unavailable);
  } finally { client.close(); }
}
