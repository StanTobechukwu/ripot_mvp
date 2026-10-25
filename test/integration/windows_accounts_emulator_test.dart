import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ripot/core/firebase/firestore_values.dart';
import 'package:ripot/core/firebase/rest_json_client.dart';
import 'package:ripot/core/firebase/windows_account_session.dart';
import 'package:ripot/core/firebase/windows_cloud_documents.dart';
import 'package:ripot/core/firebase/windows_session_store.dart';

// Only tests can redirect the real REST client to these fixed loopback ports.
// There is no emulator switch or cleartext credential path in production code.
class _EmulatorTransport extends http.BaseClient {
  final http.Client _client = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final host = request.url.host;
    if (!const {
      'identitytoolkit.googleapis.com',
      'securetoken.googleapis.com',
      'firestore.googleapis.com',
    }.contains(host)) {
      throw StateError('Unexpected emulator endpoint.');
    }
    final firestore = host == 'firestore.googleapis.com';
    final uri = Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: firestore ? 8088 : 9098,
      path: firestore ? request.url.path : '/$host${request.url.path}',
      query: request.url.query,
    );
    final forwarded = http.Request(request.method, uri)
      ..followRedirects = false
      ..headers.addAll(request.headers)
      ..bodyBytes = await request.finalize().toBytes();
    return _client.send(forwarded);
  }

  @override
  void close() => _client.close();
}

class _Store implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  const enabled = bool.fromEnvironment('RIPOT_ACCOUNT_EMULATORS');
  const project = 'demo-ripot-windows';
  test(
    'real Auth/Firestore emulators accept the Windows protocol and enforce existing ownership rules',
    () async {
      final client = RestJsonClient(clientFactory: _EmulatorTransport.new);
      final store = _Store();
      final account = WindowsAccountSession(
        projectId: project,
        apiKey: 'emulator-only-key',
        store: store,
        client: client,
      );
      final email =
          'windows-${DateTime.now().microsecondsSinceEpoch}@example.invalid';
      await account.createUserWithEmailAndPassword(
        email: email,
        password: 'fictional-test-password-928',
      );
      final uid = account.currentUser!.uid;
      await account.idToken(forceRefresh: true);
      final documents = WindowsCloudDocuments(
        projectId: project,
        session: account,
        client: client,
      );
      final ownership = <String, dynamic>{
        'ownerType': 'user',
        'ownerId': uid,
        'authUid': uid,
      };
      await documents.merge('ripot_user_access', uid, {
        ...ownership,
        'installationId': 'emulator-installation',
      });
      expect(
        (await documents.get('ripot_user_access', uid))?['installationId'],
        'emulator-installation',
      );
      await documents.merge('ripot_template_structures', '${uid}_demo', {
        ...ownership,
        'templateId': 'demo',
        'name': 'Demo E′ template',
        'layout': {'font': 'Inter', 'size': 12},
        'roots': [
          {'kind': 'number', 'value': 10.74},
        ],
      });
      await documents.merge('ripot_template_structures', '${uid}_demo', {
        ...ownership,
        'layout': {'font': 'Noto'},
      });
      final templates = await documents.query(
        'ripot_template_structures',
        equals: {'ownerType': 'user', 'ownerId': uid},
        limit: 1,
      );
      expect(templates.single.data['name'], 'Demo E′ template');
      expect(templates.single.data['layout'], {'font': 'Noto', 'size': 12});

      // Bypass only the local client allowlist, not Firestore's rules, to prove a
      // regular Firebase ID token cannot grant itself Premium or read another UID.
      final token = await account.idToken();
      final base =
          'https://firestore.googleapis.com/v1/projects/$project/databases/(default)/documents';
      final forbidden = await client.request(
        'PATCH',
        Uri.parse('$base/ripot_user_access/$uid?updateMask.fieldPaths=plan'),
        idToken: token,
        body: {
          'fields': FirestoreValues.encodeFields({'plan': 'premium'}),
        },
      );
      expect(forbidden.status, 403);
      final other = await client.request(
        'GET',
        Uri.parse('$base/ripot_user_access/another-account'),
        idToken: token,
      );
      expect(other.status, 403);

      await documents.delete('ripot_template_structures', '${uid}_demo');
      expect(
        await documents.query(
          'ripot_template_structures',
          equals: {'ownerType': 'user', 'ownerId': uid},
        ),
        isEmpty,
      );
      await account.sendPasswordResetEmail(email: email);
      final restarted = WindowsAccountSession(
        projectId: project,
        apiKey: 'emulator-only-key',
        store: store,
        client: client,
      );
      await restarted.initialize();
      expect(restarted.currentUser?.uid, uid);
      expect(await restarted.idToken(), isNotEmpty);
      await restarted.signOut();
      expect(store.value, isNull);
      await restarted.signInWithEmailAndPassword(
        email: email,
        password: 'fictional-test-password-928',
      );
      expect(restarted.currentUser?.uid, uid);
      expect(jsonDecode(store.value!)['uid'], uid);
      await restarted.signOut();
    },
    skip: !enabled
        ? 'Run with local Auth/Firestore emulators and --dart-define=RIPOT_ACCOUNT_EMULATORS=true.'
        : false,
  );
}
