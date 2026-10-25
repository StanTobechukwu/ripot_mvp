import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ripot/core/firebase/account_session.dart';
import 'package:ripot/core/firebase/firestore_values.dart';
import 'package:ripot/core/firebase/rest_json_client.dart';
import 'package:ripot/core/firebase/windows_cloud_documents.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/data/account_access_cache.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAccountSession implements AccountSession {
  AccountUser? user = const AccountUser(
    uid: 'account-a',
    email: 'demo@example.invalid',
  );
  Completer<String?>? tokenGate;
  int tokenRequests = 0;
  @override
  AccountUser? get currentUser => user;
  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    tokenRequests++;
    return tokenGate == null ? 'id-${user?.uid}' : tokenGate!.future;
  }

  @override
  Future<void> signOut() async {
    user = null;
  }

  @override
  Stream<AccountUser?> authStateChanges() => Stream.value(user);
  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeAccountSession session;
  late List<http.Request> requests;
  late Future<http.Response> Function(http.Request) handler;
  late WindowsCloudDocuments documents;
  Map<String, dynamic> ownership() => {
    'ownerType': 'user',
    'ownerId': 'account-a',
    'authUid': 'account-a',
  };
  http.Response document(Map<String, dynamic> fields) => http.Response(
    jsonEncode({'fields': FirestoreValues.encodeFields(fields)}),
    200,
  );
  Matcher cloudError(String code) =>
      isA<CloudDocumentException>().having((error) => error.code, 'code', code);

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'access.installationId': 'fictional-installation',
    });
    session = FakeAccountSession();
    requests = [];
    handler = (_) async => document({});
    documents = WindowsCloudDocuments(
      projectId: 'demo-ripot-windows',
      session: session,
      client: RestJsonClient(
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      ),
    );
  });

  test(
    'typed fields preserve template structures, E-prime text and timestamps',
    () {
      final values = <String, dynamic>{
        'roots': [
          {'type': 'number', 'label': 'E/E′', 'value': 10.74, 'visible': true},
          {'type': 'section', 'children': []},
        ],
        'empty': <String, dynamic>{},
        'missing': null,
        'count': 3,
        'createdAt': DateTime.utc(2026, 9, 30),
      };
      expect(
        FirestoreValues.decodeFields(FirestoreValues.encodeFields(values)),
        values,
      );
      expect(
        FirestoreValues.mergeMask({
          'layout': {'font': 'Inter'},
          'empty': <String, dynamic>{},
          'a.b': true,
          'odd`key': 1,
        }),
        ['layout.font', 'empty', '`a.b`', r'`odd\`key`'],
      );
    },
  );

  test(
    'configuration is read publicly; entitlements use the signed-in Firebase token',
    () async {
      handler = (_) async => document({
        'plan': 'premium',
        'playEntitlementExpiresAtIso': '2026-10-30T00:00:00Z',
      });
      await documents.get('ripot_app_config', 'access');
      expect(requests.first.headers.containsKey('authorization'), isFalse);
      expect(session.tokenRequests, 0);
      expect(
        (await documents.get(
          'ripot_user_access',
          'account-a',
          serverOnly: true,
        ))?['plan'],
        'premium',
      );
      expect(requests.last.headers['authorization'], 'Bearer id-account-a');
      expect(requests.last.url.pathSegments, [
        'v1',
        'projects',
        'demo-ripot-windows',
        'databases',
        '(default)',
        'documents',
        'ripot_user_access',
        'account-a',
      ]);
      expect(requests.last.followRedirects, isFalse);
    },
  );

  test('query scopes template structures to the signed-in account', () async {
    handler = (_) async => http.Response(
      jsonEncode([
        {
          'document': {
            'name':
                'projects/demo-ripot-windows/databases/(default)/documents/ripot_template_structures/account-a_echo',
            'fields': FirestoreValues.encodeFields({
              ...ownership(),
              'templateId': 'echo',
              'name': 'Demo echo',
            }),
          },
        },
        {'readTime': '2026-09-30T00:00:00Z'},
      ]),
      200,
    );
    final result = await documents.query(
      'ripot_template_structures',
      equals: {
        'ownerType': 'user',
        'ownerId': 'account-a',
        'templateId': 'echo',
      },
      limit: 1,
    );
    expect(result.single.id, 'account-a_echo');
    expect(result.single.data['name'], 'Demo echo');
    expect(requests.single.url.path, endsWith('/documents:runQuery'));
    final query = jsonDecode(requests.single.body)['structuredQuery'];
    expect(query['limit'], 1);
    expect(query['where']['compositeFilter']['filters'], hasLength(3));
    expect(query['from'], [
      {'collectionId': 'ripot_template_structures'},
    ]);
  });

  test(
    'metadata merge masks never replace a server-owned entitlement',
    () async {
      await documents.merge('ripot_user_access', 'account-a', {
        ...ownership(),
        'lastSeenInstallationId': 'fictional-installation',
      });
      final request = requests.single;
      expect(request.method, 'PATCH');
      expect(
        request.url.queryParametersAll['updateMask.fieldPaths'],
        unorderedEquals([
          'ownerType',
          'ownerId',
          'authUid',
          'lastSeenInstallationId',
        ]),
      );
      expect(request.body, isNot(contains('plan')));
      await expectLater(
        documents.merge('ripot_user_access', 'account-a', {
          ...ownership(),
          'plan': 'premium',
        }),
        throwsA(cloudError('permission-denied')),
      );
      await expectLater(
        documents.delete('ripot_user_access', 'account-a'),
        throwsA(cloudError('permission-denied')),
      );
      expect(requests, hasLength(1));
    },
  );

  test(
    'template merge preserves nested siblings and empty-map semantics',
    () async {
      await documents.merge('ripot_template_structures', 'account-a_demo', {
        ...ownership(),
        'layout': {'font': 'Inter'},
        'roots': [],
        'empty': <String, dynamic>{},
      });
      expect(
        requests.single.url.queryParametersAll['updateMask.fieldPaths'],
        containsAll(['layout.font', 'roots', 'empty']),
      );
      expect(jsonDecode(requests.single.body)['fields']['roots'], {
        'arrayValue': {'values': []},
      });
      await documents.delete('ripot_template_structures', 'account-a_demo');
      expect(requests.last.method, 'DELETE');
    },
  );

  test(
    'anonymous, cross-account, unscoped and configuration writes are rejected locally',
    () async {
      await expectLater(
        documents.get('ripot_user_access', 'account-b'),
        throwsA(cloudError('permission-denied')),
      );
      await expectLater(
        documents.query(
          'ripot_template_structures',
          equals: {'ownerType': 'local'},
        ),
        throwsA(cloudError('permission-denied')),
      );
      await expectLater(
        documents.merge('ripot_app_config', 'access', {
          'premiumBillingEnabled': true,
        }),
        throwsA(cloudError('permission-denied')),
      );
      await expectLater(
        documents.get('ripot_user_access', '../account-b'),
        throwsA(cloudError('invalid-document')),
      );
      await session.signOut();
      await expectLater(
        documents.get('ripot_user_access', 'account-a'),
        throwsA(cloudError('unauthenticated')),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'account change during token refresh prevents the old request from being sent',
    () async {
      session.tokenGate = Completer<String?>();
      final pending = expectLater(
        documents.get('ripot_user_access', 'account-a'),
        throwsA(cloudError('unauthenticated')),
      );
      await session.signOut();
      session.tokenGate!.complete('old-token');
      await pending;
      expect(requests, isEmpty);
    },
  );

  test(
    'account change while a request is pending discards the response',
    () async {
      final reply = Completer<http.Response>();
      final started = Completer<void>();
      handler = (_) {
        started.complete();
        return reply.future;
      };
      final pending = expectLater(
        documents.get('ripot_user_access', 'account-a'),
        throwsA(cloudError('account-changed')),
      );
      await started.future;
      session.user = const AccountUser(uid: 'account-b');
      reply.complete(document({'plan': 'premium'}));
      await pending;
    },
  );

  test(
    'missing documents and denied reads do not look like verified entitlements',
    () async {
      handler = (_) async => http.Response('{}', 404);
      expect(await documents.get('ripot_user_access', 'account-a'), isNull);
      handler = (_) async =>
          http.Response('{"error":{"message":"private server details"}}', 403);
      await expectLater(
        documents.get('ripot_user_access', 'account-a'),
        throwsA(cloudError('permission-denied')),
      );
    },
  );

  test(
    'server entitlement loads into the UID cache without writing paid fields',
    () async {
      final expiry = DateTime.now().add(const Duration(days: 2));
      handler = (request) async {
        if (request.method == 'PATCH') return document({});
        return request.url.path.endsWith('/access')
            ? document({})
            : document({
                'plan': 'premium',
                'playEntitlementExpiresAtIso': expiry.toIso8601String(),
                'billingLastVerifiedAtIso': DateTime.now().toIso8601String(),
              });
      };
      final repo = AccessRepository(session: session, documents: documents);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isTrue);
      expect((await repo.loadCached())?.isPremiumLike, isTrue);
      await Future<void>.delayed(Duration.zero);
      final writes = requests.where((request) => request.method == 'PATCH');
      expect(writes, isNotEmpty);
      expect(
        writes.every(
          (request) => !jsonDecode(request.body)['fields'].containsKey('plan'),
        ),
        isTrue,
      );
      await session.signOut();
      expect(await repo.loadCached(), isNull);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
    },
  );

  test(
    'offline access requires a verified, unexpired cache for the same UID',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = AccessRepository(session: session, documents: documents);
      handler = (_) async => throw http.ClientException('offline');
      Future<void> cache(AccessState state) => prefs.setString(
        AccountAccessCache.keyForUid('account-a'),
        AccountAccessCache.encode(authUid: 'account-a', state: state),
      );
      final premium =
          AccessState.initial(installationId: 'fictional-installation')
              .copyWith(
                plan: RipotPlan.premium,
                premiumExpiresAt: DateTime.now().add(const Duration(hours: 2)),
              )
              .verifiedNow();
      await cache(premium);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isTrue);
      session.user = const AccountUser(uid: 'account-b');
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      session.user = const AccountUser(uid: 'account-a');
      await cache(
        premium.copyWith(
          premiumExpiresAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      );
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      await cache(premium.copyWith(premiumExpiresAt: null));
      expect(await repo.loadCached(), isNull);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
    },
  );

  test(
    'a revoked session during entitlement loading cannot fall back to old Premium',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final state =
          AccessState.initial(
            installationId: 'fictional-installation',
          ).copyWith(
            plan: RipotPlan.premium,
            premiumExpiresAt: DateTime.now().add(const Duration(hours: 1)),
          );
      await prefs.setString(
        AccountAccessCache.keyForUid('account-a'),
        AccountAccessCache.encode(authUid: 'account-a', state: state),
      );
      handler = (request) async {
        if (request.url.path.endsWith('/access')) return document({});
        await session.signOut();
        throw http.ClientException('session revoked');
      };
      final repo = AccessRepository(session: session, documents: documents);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      expect(await repo.loadCached(), isNull);
    },
  );
}
