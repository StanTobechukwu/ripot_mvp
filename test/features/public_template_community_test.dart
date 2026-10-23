import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/features/reports/data/public_template_catalog.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:ripot/features/reports/domain/models/template_doc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const slug = 'community-s-example';
  final payload = jsonEncode({'app':'Ripot','ripotFileType':'template','ripotExportVersion':1,'template':{'name':'Community structure','roots':[{'type':'section','id':'field','title':'Finding'}]}});
  final hash = sha256.convert(utf8.encode(payload)).toString();
  final version = hash.substring(0,16);
  final detail = {'slug':slug,'version':version,'sha256':hash,'status':'approved','name':'Community structure','specialty':'Endoscopy','contributor':'Dr Example','payload':payload};
  Future<TemplateDoc?> resolve(Map<String,dynamic> row) => http.runWithClient(
    () => PublicTemplateCatalog.resolve(Uri(queryParameters:{'template':slug,'version':version})),
    () => MockClient((r) async {
      expect(r.url.toString().startsWith(PublicTemplateCatalog.communityEndpoint),true);
      expect(r.url.queryParameters['version'],version);
      return http.Response(jsonEncode(row),200);
    }),
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('approved community version preserves provenance and personal edits across local reload', () async {
    final template = (await resolve(detail))!;
    expect(template.sourceSlug,slug); expect(template.sourceVersion,version); expect(template.contributor,'Dr Example');
    final repo = TemplatesRepository();
    await repo.saveTemplate(template.copyWith(name:'My edited structure'));
    final reloaded = await repo.loadTemplate(template.templateId);
    expect(reloaded.name,'My edited structure'); expect(reloaded.sourceVersion,version); expect(reloaded.contributor,'Dr Example');
  });
  test('unapproved, substituted or corrupted community payloads cannot open', () async {
    for (final row in [
      {...detail,'status':'pending'}, {...detail,'slug':'community-other'},
      {...detail,'version':'0'*16}, {...detail,'payload':'$payload '},
    ]) { expect(await resolve(row),isNull); }
  });
  test('catalogue retains starters when community service is unavailable', () async {
    final page = await http.runWithClient(loadOnlineTemplates, () => MockClient((r) async => r.url.host == 'ripot.app'
      ? http.Response(jsonEncode({'schemaVersion':1,'templates':[{...detail,'slug':'starter'}]}),200)
      : http.Response('{}',503)));
    expect(page.entries.single['slug'],'starter');
    expect(page.unavailable,['Community templates']);
  });
  test('catalogue follows community pagination without requesting arbitrary URLs', () async {
    final urls=<Uri>[];
    final page=await http.runWithClient(loadOnlineTemplates, () => MockClient((r) async {
      urls.add(r.url);
      if(r.url.host=='ripot.app') return http.Response('{"schemaVersion":1,"templates":[]}',200);
      return http.Response(jsonEncode({'schemaVersion':1,'templates':[detail], 'cursor':r.url.queryParameters.containsKey('cursor') ? null : 'next-page'}),200);
    }));
    expect(page.entries.length,2); expect(urls.last.queryParameters['cursor'],'next-page');
    expect(page.unavailable,isEmpty);
  });
}
