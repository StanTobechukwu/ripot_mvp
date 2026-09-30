import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/core/firebase/rest_json_client.dart';
import 'package:ripot/core/firebase/windows_account_session.dart';
import 'package:ripot/core/firebase/windows_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySessionStore implements SessionStore {
  String? value;
  Completer<void>? writeGate;
  Completer<void>? writeStarted;
  bool failWrite = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> clear() async {
    value = null;
  }

  @override
  Future<void> write(String data) async {
    writeStarted?.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('Storage failure');
    value = data;
  }
}

http.Response loginResponse([String uid = 'account-a']) => http.Response(
  jsonEncode({
    'localId': uid,
    'email': '$uid@example.invalid',
    'idToken': 'id-$uid',
    'refreshToken': 'refresh-$uid',
    'expiresIn': '3600',
  }),
  200,
);
http.Response refreshResponse([String uid = 'account-a']) => http.Response(
  jsonEncode({
    'user_id': uid,
    'id_token': 'new-id-$uid',
    'refresh_token': 'rotated-$uid',
    'expires_in': '3600',
  }),
  200,
);
Matcher authError(String code) =>
    isA<FirebaseAuthException>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemorySessionStore store;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  late DateTime clock;
  late WindowsAccountSession session;

  WindowsAccountSession makeSession() => WindowsAccountSession(
    projectId: 'demo-ripot-windows',
    apiKey: 'test-api-key',
    store: store,
    now: () => clock,
    client: RestJsonClient(
      clientFactory: () => MockClient((request) async {
        requests.add(request);
        return handler(request);
      }),
    ),
  );

  Future<void> login() => session.signInWithEmailAndPassword(
    email: 'account-a@example.invalid',
    password: 'fictional-password',
  );
  setUp(() {
    store = MemorySessionStore();
    requests = [];
    clock = DateTime.utc(2026, 9, 30);
    handler = (_) async => loginResponse();
    session = makeSession();
  });

  test(
    'email login persists only the refresh credential, never password or ID token',
    () async {
      await login();
      expect(session.currentUser?.uid, 'account-a');
      expect(await session.idToken(), 'id-account-a');
      expect(requests.single.url.host, 'identitytoolkit.googleapis.com');
      expect(requests.single.url.path, '/v1/accounts:signInWithPassword');
      expect(requests.single.url.queryParameters['key'], 'test-api-key');
      expect(requests.single.followRedirects, isFalse);
      expect(jsonDecode(requests.single.body), {
        'email': 'account-a@example.invalid',
        'password': 'fictional-password',
        'returnSecureToken': true,
      });
      final persisted = jsonDecode(store.value!) as Map;
      expect(persisted['refreshToken'], 'refresh-account-a');
      expect(persisted.containsKey('password'), isFalse);
      expect(persisted.containsKey('idToken'), isFalse);
      expect(store.value, isNot(contains('fictional-password')));
    },
  );

  test(
    'signup and reset use Firebase endpoints and the existing account email',
    () async {
      await session.createUserWithEmailAndPassword(
        email: ' account-a@example.invalid ',
        password: 'fictional-password',
      );
      expect(requests.single.url.path, '/v1/accounts:signUp');
      handler = (_) async => http.Response('{}', 200);
      await session.sendPasswordResetEmail(
        email: ' account-a@example.invalid ',
      );
      expect(requests.last.url.path, '/v1/accounts:sendOobCode');
      expect(jsonDecode(requests.last.body), {
        'requestType': 'PASSWORD_RESET',
        'email': 'account-a@example.invalid',
      });
    },
  );

  test(
    'restart restores account offline, then refreshes before any remote operation',
    () async {
      await login();
      final restarted = makeSession();
      await restarted.initialize();
      expect(restarted.currentUser?.uid, 'account-a');
      expect(requests, hasLength(1));
      handler = (_) async => refreshResponse();
      expect(await restarted.idToken(), 'new-id-account-a');
      expect(requests.last.url.host, 'securetoken.googleapis.com');
      expect(Uri.splitQueryString(requests.last.body), {
        'grant_type': 'refresh_token',
        'refresh_token': 'refresh-account-a',
      });
      expect(
        requests.last.headers['content-type'],
        startsWith('application/x-www-form-urlencoded'),
      );
      expect(jsonDecode(store.value!)['refreshToken'], 'rotated-account-a');
    },
  );

  test(
    'expired tokens refresh once for concurrent callers and rotate saved credential',
    () async {
      await login();
      clock = clock.add(const Duration(hours: 2));
      final reply = Completer<http.Response>();
      handler = (_) => reply.future;
      final first = session.idToken();
      final second = session.idToken();
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(2));
      reply.complete(refreshResponse());
      expect(await first, 'new-id-account-a');
      expect(await second, 'new-id-account-a');
      expect(await session.idToken(), 'new-id-account-a');
      expect(requests, hasLength(2));
    },
  );

  for (final error in {
    'TOKEN_EXPIRED': 'user-token-expired',
    'USER_DISABLED': 'user-disabled',
    'USER_NOT_FOUND': 'user-not-found',
    'INVALID_REFRESH_TOKEN': 'invalid-user-token',
  }.entries) {
    test('${error.key} signs out and clears the saved credential', () async {
      await login();
      handler = (_) async => http.Response(
        jsonEncode({
          'error': {'message': error.key},
        }),
        400,
      );
      await expectLater(
        session.idToken(forceRefresh: true),
        throwsA(authError(error.value)),
      );
      expect(session.currentUser, isNull);
      expect(store.value, isNull);
    });
  }

  test(
    'network failure cannot extend an expired token or destroy an offline session',
    () async {
      await login();
      clock = clock.add(const Duration(hours: 2));
      handler = (_) async =>
          throw http.ClientException('sensitive request details');
      await expectLater(
        session.idToken(),
        throwsA(authError('network-request-failed')),
      );
      expect(session.currentUser?.uid, 'account-a');
      expect(store.value, isNotNull);
      handler = (_) async => refreshResponse();
      expect(await session.idToken(), 'new-id-account-a');
    },
  );

  test('a refresh for a different UID invalidates the session', () async {
    await login();
    handler = (_) async => refreshResponse('account-b');
    await expectLater(
      session.idToken(forceRefresh: true),
      throwsA(authError('invalid-user-token')),
    );
    expect(session.currentUser, isNull);
    expect(store.value, isNull);
  });

  test('sign-out wins over an in-flight sign-in response', () async {
    final reply = Completer<http.Response>();
    handler = (_) => reply.future;
    final pending = expectLater(
      login(),
      throwsA(authError('operation-cancelled')),
    );
    await session.signOut();
    reply.complete(loginResponse());
    await pending;
    expect(session.currentUser, isNull);
    expect(store.value, isNull);
  });

  test('sign-out is serialized after an in-flight credential write', () async {
    store.writeGate = Completer<void>();
    store.writeStarted = Completer<void>();
    final pending = expectLater(
      login(),
      throwsA(authError('operation-cancelled')),
    );
    await store.writeStarted!.future;
    final logout = session.signOut();
    store.writeGate!.complete();
    await pending;
    await logout;
    expect(store.value, isNull);
    expect(session.currentUser, isNull);
  });

  test('late refresh cannot overwrite a newly signed-in account', () async {
    await login();
    final reply = Completer<http.Response>();
    handler = (request) => request.url.host == 'securetoken.googleapis.com'
        ? reply.future
        : Future.value(loginResponse('account-b'));
    final pending = expectLater(
      session.idToken(forceRefresh: true),
      throwsA(authError('operation-cancelled')),
    );
    await session.signOut();
    await session.signInWithEmailAndPassword(
      email: 'account-b@example.invalid',
      password: 'other-fictional-password',
    );
    reply.complete(refreshResponse());
    await pending;
    expect(session.currentUser?.uid, 'account-b');
    expect(jsonDecode(store.value!)['uid'], 'account-b');
  });

  test(
    'a corrupt or foreign saved session is discarded without blocking startup',
    () async {
      store.value = '{bad-json';
      await session.initialize();
      expect(session.currentUser, isNull);
      expect(store.value, isNull);
      store.value = jsonEncode({
        'version': 1,
        'projectId': 'another-project',
        'uid': 'other',
        'refreshToken': 'other',
      });
      await makeSession().initialize();
      expect(store.value, isNull);
      expect(requests, isEmpty);
    },
  );

  test('a failed secure write never falls back to plaintext sign-in', () async {
    store.failWrite = true;
    await expectLater(
      login(),
      throwsA(authError('secure-storage-unavailable')),
    );
    expect(session.currentUser, isNull);
    expect(store.value, isNull);
  });

  test(
    'credential errors have controlled codes and never expose response details',
    () async {
      handler = (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'INVALID_LOGIN_CREDENTIALS'},
        }),
        400,
      );
      await expectLater(login(), throwsA(authError('invalid-credential')));
      handler = (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'WEAK_PASSWORD : secret details'},
        }),
        400,
      );
      await expectLater(login(), throwsA(authError('weak-password')));
      handler = (_) async => http.Response(
        jsonEncode({
          'error': {'message': 'secret details'},
        }),
        500,
      );
      try {
        await login();
        fail('Expected failure');
      } on FirebaseAuthException catch (error) {
        expect(error.toString(), isNot(contains('secret details')));
      }
    },
  );

  test(
    'malformed credentials or unsupported second factor cannot create a session',
    () async {
      handler = (_) async =>
          http.Response('{"mfaPendingCredential":"challenge"}', 200);
      await expectLater(
        login(),
        throwsA(authError('unsupported-second-factor')),
      );
      handler = (_) async => http.Response('{"localId":"account-a"}', 200);
      await expectLater(login(), throwsA(authError('internal-error')));
      expect(store.value, isNull);
      expect(session.currentUser, isNull);
    },
  );

  test(
    'auth observers receive initial state, sign-in and immediate sign-out',
    () async {
      final events = <String?>[];
      final subscription = session.authStateChanges().listen(
        (user) => events.add(user?.uid),
      );
      await Future<void>.delayed(Duration.zero);
      await login();
      await session.signOut();
      expect(events, [null, 'account-a', null]);
      await subscription.cancel();
    },
  );

  test('transport refuses redirects without forwarding credentials', () async {
    handler = (_) async => http.Response(
      '',
      302,
      headers: {'location': 'https://example.invalid/collect'},
    );
    await expectLater(login(), throwsA(authError('network-request-failed')));
    expect(requests, hasLength(1));
    expect(requests.single.followRedirects, isFalse);
  });

  test(
    'Windows store puts only an enabled marker in shared preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final secure = WindowsSessionStore('demo-ripot-windows');
      await secure.write('fictional-encrypted-credential');
      expect(await secure.read(), 'fictional-encrypted-credential');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), {
        'ripot.windows.account.demo-ripot-windows.v1.enabled',
      });
      expect(preferences.get(preferences.getKeys().single), true);
      await secure.clear();
      expect(await secure.read(), isNull);
      expect(
        await const FlutterSecureStorage().read(
          key: 'ripot.windows.account.demo-ripot-windows.v1',
        ),
        isNull,
      );
    },
  );
}
