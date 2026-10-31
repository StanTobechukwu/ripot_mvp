import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/features/reports/data/public_template_catalog.dart';
import 'package:ripot/features/reports/domain/models/nodes.dart';
import 'package:ripot/features/reports/domain/serialization/template_codec.dart';

void main() {
  final entries = jsonDecode(File('tools/landing/additional_catalog.json').readAsStringSync()) as List;
  final fixtures = jsonDecode(File('tools/landing/example_values.json').readAsStringSync()) as Map;
  test('catalogue expansion preserves the four released starter payloads', () {
    const originals = {
      'upper-gi-endoscopy-report-template':'b1282b15fe6950b5',
      'colonoscopy-report-template':'3f11bbf4563cef14',
      'abdominal-ultrasound-report-template':'a3ac8bcbf9744e83',
      'echocardiogram-report-template':'466590d1d23cf128',
    };
    for (final entry in originals.entries) {
      expect(sha256.convert(File('landing/y/templates/catalog/${entry.key}/${entry.value}.ripottemplate.json').readAsBytesSync()).toString().substring(0,16),entry.value);
    }
    expect(entries, hasLength(13));
    expect(entries.map((e) => e['slug']).toSet(), hasLength(13));
  });
  for (final entry in entries) {
    final slug = entry['slug'] as String;
    test('$slug loads through the actual remote importer with blank values and intact field types', () async {
      final bytes = File('landing/y/templates/downloads/$slug.ripottemplate.json').readAsBytesSync();
      final digest = sha256.convert(bytes).toString(), version = digest.substring(0,16);
      final path = '/templates/catalog/$slug/$version.ripottemplate.json';
      final result = await http.runWithClient(
        () => PublicTemplateCatalog.resolveForEditor(Uri(queryParameters:{'template':slug,'version':version})),
        () => MockClient((request) async {
          expect(request.url.origin,'https://ripot.app');
          if(request.url.path.endsWith('manifest.json')) {
            return http.Response(jsonEncode({'schemaVersion':1,'templates':[{
              'slug':slug,'version':version,'status':'approved','sha256':digest,'url':path,
            }]}),200);
          }
          expect(request.url.path,path);
          return http.Response.bytes(bytes,200);
        }),
      );
      expect(result,isNotNull);
      final doc=result!;
      expect(doc.sourceSlug,slug);
      expect(doc.sourceVersion,version);
      final leafIds=<String>{}, allIds=<String>{};
      void inspect(SectionNode node) {
        expect(allIds.add(node.id),isTrue,reason:'Duplicate ID');
        expect(node.addToRecords,isFalse);
        expect(node.addToLog,isFalse);
        final children=node.children.whereType<SectionNode>().toList();
        if(children.isEmpty)leafIds.add(node.id);
        for(final value in node.children.whereType<ContentNode>()) { expect(value.text,isEmpty); }
        for(final child in children) { inspect(child); }
      }
      for(final root in doc.roots) { inspect(root); }
      expect(leafIds, (fixtures[slug] as Map).keys.toSet());
      final roundTrip = TemplateCodec.templateFromJson(TemplateCodec.templateToJson(doc));
      expect(roundTrip.roots.length,doc.roots.length);
      final encoded=jsonEncode(TemplateCodec.templateToJson(roundTrip));
      expect(encoded, isNot(contains('FICTIONAL PATIENT')));
      expect(encoded, isNot(contains('fictional')));
      expect(allIds.length,lessThanOrEqualTo(200));
    });
  }
}
