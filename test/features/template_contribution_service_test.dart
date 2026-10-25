import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/core/firebase/callable_http_client.dart';
import 'package:ripot/features/reports/data/template_contribution_service.dart';

void main() {
  Future<void> probe(int status, String body) => http.runWithClient(
    checkTemplateContributionService,
    () => MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.queryParameters['health'], '1');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return http.Response(body, status);
    }),
  );
  test('missing service is distinguished from a connectivity problem', () async {
    await expectLater(probe(404, '<html>Not found</html>'), throwsA(
      isA<AccountFunctionException>().having((e) => e.code, 'code', 'service-not-deployed')));
    expect(templateContributionError(const AccountFunctionException(code: 'service-not-deployed')), contains('not available on the server'));
  });
  test('health protocol requires explicit support and accepts ready response', () async {
    await probe(200, '{"schemaVersion":1,"contributions":"ready"}');
    for (final body in ['<html>app</html>', '{"schemaVersion":1,"templates":[]}', '[]']) {
      await expectLater(probe(200, body), throwsA(isA<AccountFunctionException>().having((e) => e.code, 'code', 'service-update-required')));
    }
    await expectLater(probe(503, '{}'), throwsA(isA<AccountFunctionException>().having((e) => e.code, 'code', 'unavailable')));
  });
  test('SDK and Windows errors give actionable messages without exposing server text', () {
    for (final code in ['unauthenticated','permission-denied','invalid-argument','resource-exhausted','failed-precondition','deadline-exceeded','not-found','internal']) {
      final sdk = FirebaseFunctionsException(code: code, message: 'PRIVATE SERVER DETAIL');
      final native = AccountFunctionException(code: code);
      expect(templateContributionError(sdk), templateContributionError(native));
      expect(templateContributionError(sdk), isNot(contains('PRIVATE')));
    }
    expect(templateContributionError(TimeoutException('timeout'),submitting:true),contains('may already have arrived'));
    expect(templateContributionError(const AccountFunctionException(code:'invalid-argument'),submitting:true),contains('entries are kept'));
    expect(templateContributionError(const AccountFunctionException(code:'invalid-argument')),isNot(contains('Check your connection')));
  });
}
