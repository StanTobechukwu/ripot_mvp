import 'account_session.dart';
import 'cloud_documents.dart';
import 'firestore_values.dart';
import 'rest_json_client.dart';

class CloudDocumentException implements Exception {
  const CloudDocumentException(this.code);
  final String code;
  @override
  String toString() => 'Account data request failed ($code).';
}

/// Firebase ID tokens keep every request subject to the existing Firestore
/// Security Rules. This client never uses an administrator/service-account key.
class WindowsCloudDocuments implements CloudDocuments {
  WindowsCloudDocuments({
    required this.projectId,
    required this.session,
    RestJsonClient? client,
  }) : _client = client ?? RestJsonClient();
  final String projectId;
  final AccountSession session;
  final RestJsonClient _client;
  static const _config = 'ripot_app_config';
  static const _access = 'ripot_user_access';
  static const _templates = 'ripot_template_structures';
  static const _metadataKeys = {
    'ownerType',
    'ownerId',
    'authUid',
    'installationId',
    'lastSeenInstallationId',
    'lastClientSeenAtIso',
    'legacyInstallationIdObserved',
    'lastMigrationCheckAtIso',
  };

  Uri _uri([String? collection, String? id, Map<String, dynamic>? query]) =>
      Uri(
        scheme: 'https',
        host: 'firestore.googleapis.com',
        pathSegments: [
          'v1',
          'projects',
          projectId,
          'databases',
          '(default)',
          collection == null ? 'documents:runQuery' : 'documents',
          ?collection,
          ?id,
        ],
        queryParameters: query,
      );

  String? _owner(String collection, {String? id, bool write = false}) {
    if (id != null &&
        (id.isEmpty || id.contains('/') || id == '.' || id == '..')) {
      throw const CloudDocumentException('invalid-document');
    }
    if (collection == _config && id == 'access' && !write) return null;
    if (collection != _access && collection != _templates) {
      throw const CloudDocumentException('permission-denied');
    }
    final uid = session.currentUser?.uid;
    if (uid == null) throw const CloudDocumentException('unauthenticated');
    if ((collection == _access && id != uid) ||
        (collection == _templates && id != null && !id.startsWith('${uid}_'))) {
      throw const CloudDocumentException('permission-denied');
    }
    return uid;
  }

  Future<RestResponse> _send(
    String method,
    Uri uri,
    String? uid, {
    Object? body,
  }) async {
    final token = uid == null ? null : await session.idToken();
    if (uid != null &&
        (token == null || token.isEmpty || session.currentUser?.uid != uid)) {
      throw const CloudDocumentException('unauthenticated');
    }
    final response = await _client.request(
      method,
      uri,
      body: body,
      idToken: token,
    );
    if (uid != null && session.currentUser?.uid != uid) {
      throw const CloudDocumentException('account-changed');
    }
    return response;
  }

  void _success(RestResponse response) {
    if (response.status >= 200 && response.status < 300) return;
    throw CloudDocumentException(switch (response.status) {
      401 => 'unauthenticated',
      403 => 'permission-denied',
      404 => 'not-found',
      429 => 'resource-exhausted',
      _ => 'unavailable',
    });
  }

  @override
  Future<Map<String, dynamic>?> get(
    String collection,
    String id, {
    bool serverOnly = false,
  }) async {
    final uid = _owner(collection, id: id);
    final response = await _send('GET', _uri(collection, id), uid);
    if (response.status == 404) return null;
    _success(response);
    return FirestoreValues.decodeFields((response.data as Map)['fields']);
  }

  @override
  Future<List<CloudDocument>> query(
    String collection, {
    required Map<String, Object?> equals,
    int? limit,
  }) async {
    if (collection != _templates) {
      throw const CloudDocumentException('permission-denied');
    }
    final uid = _owner(collection);
    if (equals['ownerType'] != 'user' || equals['ownerId'] != uid) {
      throw const CloudDocumentException('permission-denied');
    }
    if (limit != null && limit <= 0) throw ArgumentError.value(limit, 'limit');
    final response = await _send(
      'POST',
      _uri(),
      uid,
      body: {
        'structuredQuery': {
          'from': [
            {'collectionId': collection},
          ],
          'where': {
            'compositeFilter': {
              'op': 'AND',
              'filters': equals.entries
                  .map(
                    (entry) => {
                      'fieldFilter': {
                        'field': {'fieldPath': entry.key},
                        'op': 'EQUAL',
                        'value': FirestoreValues.encode(entry.value),
                      },
                    },
                  )
                  .toList(),
            },
          },
          'limit': ?limit,
        },
      },
    );
    _success(response);
    final result = <CloudDocument>[];
    for (final row in response.data as List) {
      final document = (row as Map)['document'];
      if (document == null) continue;
      final name = document['name'] as String;
      final data = FirestoreValues.decodeFields(document['fields']);
      if (data['ownerType'] != 'user' || data['ownerId'] != uid) {
        throw const CloudDocumentException('permission-denied');
      }
      result.add(CloudDocument(name.split('/').last, data));
    }
    return result;
  }

  @override
  Future<void> merge(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    final uid = _owner(collection, id: id, write: true);
    if (data['ownerType'] != 'user' ||
        data['ownerId'] != uid ||
        data['authUid'] != uid ||
        (collection == _access &&
            data.keys.any((key) => !_metadataKeys.contains(key)))) {
      throw const CloudDocumentException('permission-denied');
    }
    final response = await _send(
      'PATCH',
      _uri(collection, id, {
        'updateMask.fieldPaths': FirestoreValues.mergeMask(data),
      }),
      uid,
      body: {'fields': FirestoreValues.encodeFields(data)},
    );
    _success(response);
  }

  @override
  Future<void> delete(String collection, String id) async {
    if (collection != _templates) {
      throw const CloudDocumentException('permission-denied');
    }
    final response = await _send(
      'DELETE',
      _uri(collection, id),
      _owner(collection, id: id, write: true),
    );
    _success(response);
  }
}
