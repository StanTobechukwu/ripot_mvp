import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/features/reports/data/public_template_catalog.dart';
import 'package:ripot/features/reports/data/reports_repository.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:ripot/features/reports/domain/public_template_links.dart';
import 'package:ripot/features/reports/providers/report_editor_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const slug = 'colonoscopy-report-template';

Map<String, dynamic> section(String id, [List<dynamic> children = const []]) => {
  'type': 'section', 'id': id, 'title': id, 'children': children,
};

Map<String, dynamic> payload() => {
  'app': 'Ripot', 'ripotFileType': 'template', 'ripotExportVersion': 1,
  'template': {'name': 'Published test structure', 'roots': [section('root')]},
};

class CatalogFixture {
  CatalogFixture(this.document) {
    bytes = utf8.encode(jsonEncode(document));
    final digest = sha256.convert(bytes).toString();
    version = digest.substring(0, 16);
    entry = {
      'slug': slug, 'status': 'approved', 'version': version,
      'sha256': digest,
      'url': '/templates/catalog/$slug/$version.ripottemplate.json',
    };
    entries = [entry];
  }

  final Map<String, dynamic> document;
  late List<int> bytes;
  late String version;
  late Map<String, dynamic> entry;
  late List<Map<String, dynamic>> entries;
  final requests = <Uri>[];
  int status = 200;

  Future<TemplateDoc?> resolve({String? query}) => http.runWithClient(
    () => PublicTemplateCatalog.resolveForEditor(Uri.parse(
      'https://ripot-web.web.app/?${query ?? 'template=$slug&version=$version'}',
    )),
    () => MockClient((request) async {
      requests.add(request.url);
      expect(request.url.origin, 'https://ripot.app');
      if (request.url.path == '/templates/catalog/manifest.json') {
        return http.Response(jsonEncode({
          'schemaVersion': 1, 'templates': entries,
        }), status);
      }
      expect(request.url.path,
          '/templates/catalog/$slug/$version.ripottemplate.json');
      return http.Response.bytes(bytes, status);
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('versioned built-in slug opens published structure, not bundled copy', () async {
    final f = CatalogFixture(payload());
    final template = (await f.resolve())!;
    expect(template.templateId, 'public_${slug}_${f.version}');
    expect(template.name, 'Published test structure');
    expect(template.roots.single.id, 'root');
    expect(f.requests, hasLength(2));
  });

  test('old unversioned starter link still works without a network request', () async {
    final f = CatalogFixture(payload());
    final template = (await f.resolve(query: 'template=$slug'))!;
    expect(template.templateId, PublicTemplateLinks.ids[slug]);
    expect(f.requests, isEmpty);
  });

  test('new specialty can load without a bundled template', () async {
    const newSlug = 'new-specialty';
    final f = CatalogFixture(payload());
    f.entry['slug'] = newSlug;
    f.entry['url'] = '/templates/catalog/$newSlug/${f.version}.ripottemplate.json';
    final result = await http.runWithClient(
      () => PublicTemplateCatalog.resolveForEditor(Uri.parse(
        'https://ripot-web.web.app/?template=$newSlug&version=${f.version}',
      )),
      () => MockClient((request) async {
        expect(request.url.origin, 'https://ripot.app');
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response(jsonEncode({'schemaVersion': 1, 'templates': f.entries}), 200);
        }
        expect(request.url.path, f.entry['url']);
        return http.Response.bytes(f.bytes, 200);
      }),
    );
    expect(result!.templateId, 'public_${newSlug}_${f.version}');
  });

  for (final file in Directory('landing/y/templates/downloads')
      .listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    test('published export ${file.uri.pathSegments.last} opens a blank report', () async {
      final f = CatalogFixture(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
      final template = (await f.resolve())!;
      final editor = ReportEditorProvider(
        repo: ReportsRepository(), templatesRepo: TemplatesRepository(),
      );
      addTearDown(editor.dispose);
      editor.newReportFromTemplate(template);
      expect(editor.doc.sourceTemplateId, template.templateId);
      expect(editor.doc.subjectInfo.values.values.every((v) => v.isEmpty), isTrue);
      expect(editor.doc.images, isEmpty);
      expect(editor.doc.roots, isNotEmpty);
      expect(template.signature.name, isEmpty);
      expect(template.signature.signatureFilePath, isNull);
    });
  }

  for (final query in [
    'template=https://evil.example/template',
    'template=../private',
    'template=$slug&version=latest',
    'template=$slug&version=',
  ]) {
    test('invalid link is rejected before fetching: $query', () async {
      final f = CatalogFixture(payload());
      expect(await f.resolve(query: query), isNull);
      expect(f.requests, isEmpty);
    });
  }

  test('missing requested version does not fall back to bundled template', () async {
    final f = CatalogFixture(payload());
    expect(await f.resolve(query: 'template=$slug&version=0000000000000000'), isNull);
    expect(f.requests, hasLength(1));
  });

  test('unapproved and duplicate entries are rejected', () async {
    final f = CatalogFixture(payload());
    f.entry['status'] = 'draft';
    expect(await f.resolve(), isNull);
    f.entry['status'] = 'approved';
    f.entries.add(Map<String, dynamic>.from(f.entry));
    expect(await f.resolve(), isNull);
    expect(f.requests.every((u) => u.path.endsWith('manifest.json')), isTrue);
  });

  test('external payload URL cannot be fetched', () async {
    final f = CatalogFixture(payload());
    f.entry['url'] = 'https://evil.example/template.json';
    expect(await f.resolve(), isNull);
    expect(f.requests, hasLength(1));
  });

  test('changed bytes fail checksum verification', () async {
    final f = CatalogFixture(payload());
    f.bytes = [...f.bytes, 32];
    expect(await f.resolve(), isNull);
  });

  test('HTTP failures and invalid JSON fail without throwing', () async {
    final f = CatalogFixture(payload());
    f.status = 503;
    expect(await f.resolve(), isNull);
    final result = await http.runWithClient(
      () => PublicTemplateCatalog.resolve(Uri.parse('https://ripot-web.web.app/?template=$slug')),
      () => MockClient((_) async => http.Response('invalid json', 200)),
    );
    expect(result, isNull);
  });

  test('signature and registry/logbook settings are cleared recursively', () async {
    final doc = payload();
    doc['template']['signature'] = {'name': 'Example signer', 'signatureFilePath': '/private/signature.png'};
    doc['template']['recordsConfigured'] = true;
    doc['template']['roots'] = [
      {...section('parent', [{...section('child'), 'addToRecords': true, 'addToLog': true}]),
        'addToRecords': true, 'addToLog': true},
    ];
    final template = (await CatalogFixture(doc).resolve())!;
    expect(template.recordsConfigured, isFalse);
    expect(template.signature.name, isEmpty);
    expect(template.signature.signatureFilePath, isNull);
    for (final node in [template.roots.single, template.roots.single.children.single as SectionNode]) {
      expect(node.addToRecords, isFalse);
      expect(node.addToLog, isFalse);
    }
  });

  test('content roots, duplicate IDs, and empty roots are rejected', () async {
    for (final roots in [
      [{'type': 'content', 'id': 'bad', 'text': ''}],
      [section('duplicate'), section('duplicate')],
      [],
    ]) {
      final doc = payload();
      doc['template']['roots'] = roots;
      expect(await CatalogFixture(doc).resolve(), isNull);
    }
  });

  test('total node limit includes siblings after a nested subtree', () async {
    final doc = payload();
    doc['template']['roots'] = [
      section('parent', List.generate(199, (i) => section('child$i'))),
      section('last-sibling'),
    ];
    expect(await CatalogFixture(doc).resolve(), isNull);
  });

  test('excessive nesting is rejected', () async {
    var node = section('leaf');
    for (var i = 0; i < 10; i++) { node = section('level$i', [node]); }
    final doc = payload();
    doc['template']['roots'] = [node];
    expect(await CatalogFixture(doc).resolve(), isNull);
  });
}
