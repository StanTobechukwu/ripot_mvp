import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/features/reports/data/public_template_catalog.dart';

void main() {
  test('versioned payload starts before manifest finishes, without bypassing integrity checks', () async {
    final bytes=utf8.encode(jsonEncode({'app':'Ripot','ripotFileType':'template','ripotExportVersion':1,
      'template':{'name':'Parallel QA','roots':[{'type':'section','id':'test','title':'Observation','children':[]}]}}));
    final digest=sha256.convert(bytes).toString(), version=digest.substring(0,16);
    const slug='parallel-test';
    final path='/templates/catalog/$slug/$version.ripottemplate.json';
    for(final approved in [true,false]) {
      final payloadStarted=Completer<void>();
      final result=await http.runWithClient(()=>PublicTemplateCatalog.resolve(Uri(queryParameters:{'template':slug,'version':version})),
        ()=>MockClient((request) async {
          if(request.url.path.endsWith('manifest.json')) {
            await payloadStarted.future.timeout(const Duration(seconds:2));
            return http.Response(jsonEncode({'schemaVersion':1,'templates':[{'slug':slug,'version':version,'status':approved?'approved':'rejected','sha256':digest,'url':path}]}),200);
          }
          expect(request.url.path,path);
          payloadStarted.complete();
          return http.Response.bytes(bytes,200);
        }));
      expect(payloadStarted.isCompleted,isTrue);
      if(approved) { expect(result?.name,'Parallel QA'); } else { expect(result,isNull); }
    }
  });
}
