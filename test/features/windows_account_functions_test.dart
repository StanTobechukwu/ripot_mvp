import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/core/firebase/callable_http_client.dart';

void main() {
  Future<dynamic> call(
    MockClient client, {
    Duration? timeout,
    String token = 'test-id-token',
  }) => CallableHttpClient(clientFactory: () => client).call(
    projectId: 'ripot-test-project',
    name: 'activatePremiumTrial',
    idToken: token,
    timeout: timeout ?? const Duration(seconds: 1),
  );

  Matcher code(String value) => isA<AccountFunctionException>().having(
    (error) => error.code,
    'code',
    value,
  );

  test(
    'sends account token to fixed HTTPS callable endpoint without redirects',
    () async {
      final result = await call(
        MockClient((request) async {
          expect(
            request.url.toString(),
            'https://us-central1-ripot-test-project.cloudfunctions.net/activatePremiumTrial',
          );
          expect(request.method, 'POST');
          expect(request.headers['Authorization'], 'Bearer test-id-token');
          expect(jsonDecode(request.body), {'data': <String, dynamic>{}});
          expect(request.followRedirects, isFalse);
          return http.Response('{"result":{"activated":true}}', 200);
        }),
      );
      expect(result, {'activated': true});
    },
  );

  test('missing authentication never sends a request', () async {
    await expectLater(
      call(
        MockClient((_) async {
          fail('An unauthenticated request was sent.');
        }),
        token: '',
      ),
      throwsA(code('unauthenticated')),
    );
  });

  test('server denial takes priority even with HTTP 200 and a result', () async {
    await expectLater(
      call(
        MockClient(
          (_) async => http.Response(
            '{"error":{"status":"PERMISSION_DENIED"},"result":{"activated":true}}',
            200,
          ),
        ),
      ),
      throwsA(code('permission-denied')),
    );
  });

  test(
    'non-JSON, missing result, redirect and error response never grant access',
    () async {
      for (final response in [
        http.Response('<html>error</html>', 502),
        http.Response('{}', 200),
        http.Response('{"result":{"activated":true}}', 302),
        http.Response('{"result":{"activated":true}}', 403),
        http.Response('{"error":{"status":"OK"}}', 200),
      ]) {
        await expectLater(
          call(MockClient((_) async => response)),
          throwsA(code('internal')),
        );
      }
    },
  );

  test('connection failure and timeout have bounded failures', () async {
    await expectLater(
      call(MockClient((_) async => throw http.ClientException('offline'))),
      throwsA(code('unavailable')),
    );
    final pending = Completer<http.Response>();
    await expectLater(
      call(
        MockClient((_) => pending.future),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(code('deadline-exceeded')),
    );
    pending.complete(http.Response('{"result":null}', 200));
  });
}
