import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/features/reports/data/public_template_catalog.dart';

void main() {
  const slug = 'recovery-test';
  final bytes = utf8.encode(jsonEncode({
    'app': 'Ripot', 'ripotFileType': 'template', 'ripotExportVersion': 2,
    'template': {'name': 'Recovery QA', 'roots': [
      {'type': 'section', 'id': 'observation', 'title': 'Observation', 'children': []},
    ]},
  }));
  final digest = sha256.convert(bytes).toString();
  final version = digest.substring(0, 16);
  final entry = <String, dynamic>{
    'slug': slug, 'version': version, 'status': 'approved', 'sha256': digest,
    'url': '/templates/catalog/$slug/$version.ripottemplate.json',
  };
  final link = Uri(queryParameters: {'template': slug, 'version': version});
  http.Response manifest([Map<String, dynamic>? row]) => http.Response(
    jsonEncode({'schemaVersion': 1, 'templates': [row ?? entry]}), 200);

  testWidgets('downloads slower than eight seconds still open the exact version', (tester) async {
    var requests = 0;
    final pending = http.runWithClient(() => PublicTemplateCatalog.load(link, forEditor: true),
      () => MockClient((request) async {
        requests++;
        await Future<void>.delayed(const Duration(seconds: 9));
        return request.url.path.endsWith('manifest.json') ? manifest() : http.Response.bytes(bytes, 200);
      }));
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    final result = await pending;
    expect(result.template?.sourceVersion, version);
    expect(result.failure, isNull);
    expect(requests, 2);
  });

  test('transient manifest and payload failures recover once without changing version', () async {
    var manifests = 0, payloads = 0;
    final result = await http.runWithClient(() => PublicTemplateCatalog.load(link),
      () => MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          manifests++;
          if (manifests == 1) return http.Response('Unavailable', 503);
          expect(request.url.queryParameters['templateVersion'], version);
          expect(request.url.queryParameters.containsKey('ripotRetry'), isTrue);
          return manifest();
        }
        payloads++;
        if (payloads == 1) throw TimeoutException('Temporary download delay');
        return http.Response.bytes(bytes, 200);
      }));
    expect(result.template?.sourceVersion, version);
    expect(result.failure, isNull);
    expect(manifests, 2);
    expect(payloads, 2);
  });

  for (final fails in ['manifest', 'payload']) {
    test('persistent $fails failure is a connection error and retries are bounded', () async {
      var failures = 0;
      final result = await http.runWithClient(() => PublicTemplateCatalog.load(link),
        () => MockClient((request) async {
          final index = request.url.path.endsWith('manifest.json');
          if (index == (fails == 'manifest')) {
            failures++;
            throw http.ClientException('Offline', request.url);
          }
          return index ? manifest() : http.Response.bytes(bytes, 200);
        }));
      expect(result.template, isNull);
      expect(result.failure, PublicTemplateLoadFailure.connection);
      expect(failures, 2);
    });
  }

  test('stale manifest is refreshed once before rejecting a newly published version', () async {
    var manifests = 0, payloads = 0;
    final result = await http.runWithClient(() => PublicTemplateCatalog.load(link),
      () => MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          manifests++;
          if (manifests == 1) return manifest({...entry, 'version': '0000000000000000', 'versions': []});
          expect(request.url.queryParameters.containsKey('ripotRefresh'), isTrue);
          return manifest();
        }
        payloads++;
        return http.Response.bytes(bytes, 200);
      }));
    expect(result.template?.sourceVersion, version);
    expect(result.latestVersion, version);
    expect(manifests, 2);
    expect(payloads, 1);
  });

  test('404 does not retry and is distinct from a connection error', () async {
    var payloads = 0;
    final result = await http.runWithClient(() => PublicTemplateCatalog.load(link),
      () => MockClient((request) async {
        if (request.url.path.endsWith('manifest.json')) return manifest();
        payloads++;
        return http.Response('Not found', 404);
      }));
    expect(result.template, isNull);
    expect(result.failure, PublicTemplateLoadFailure.unavailable);
    expect(payloads, 1);
  });

  test('recovery does not accept substituted bytes or withdrawn approval', () async {
    for (final withdrawn in [false, true]) {
      var manifests = 0;
      final result = await http.runWithClient(() => PublicTemplateCatalog.load(link),
        () => MockClient((request) async {
          if (request.url.path.endsWith('manifest.json')) {
            manifests++;
            return manifest({...entry, if (withdrawn) 'status': 'withdrawn'});
          }
          return http.Response.bytes([...bytes, 32], 200);
        }));
      expect(result.template, isNull);
      expect(result.failure, PublicTemplateLoadFailure.unavailable);
      expect(manifests, 1);
    }
  });
}
