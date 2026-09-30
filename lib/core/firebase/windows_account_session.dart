import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';

import 'account_session.dart';
import 'rest_json_client.dart';
import 'windows_session_store.dart';

/// Firebase email/password authentication through its documented REST API.
/// Passwords are sent only to Firebase and are never persisted. Only the
/// refresh credential is stored, using Windows encrypted storage.
class WindowsAccountSession implements AccountSession {
  WindowsAccountSession({
    required this.projectId,
    required this.apiKey,
    required SessionStore store,
    RestJsonClient? client,
    DateTime Function()? now,
  }) : _store = store,
       _client = client ?? RestJsonClient(),
       _now = now ?? DateTime.now;

  final String projectId;
  final String apiKey;
  final SessionStore _store;
  final RestJsonClient _client;
  final DateTime Function() _now;
  final _changes = StreamController<AccountUser?>.broadcast(sync: true);
  Future<void> _storageQueue = Future<void>.value();
  Future<void>? _initialization;
  Future<String?>? _refreshing;
  int _refreshGeneration = -1;
  int _generation = 0;
  AccountUser? _user;
  String? _refreshToken;
  String? _idToken;
  DateTime? _expiresAt;

  @override
  AccountUser? get currentUser => _user;

  @override
  Stream<AccountUser?> authStateChanges() => Stream.multi((controller) {
    final subscription = _changes.stream.listen(
      controller.addSync,
      onError: controller.addErrorSync,
      onDone: controller.closeSync,
    );
    controller.add(_user);
    controller.onCancel = subscription.cancel;
  });

  Future<void> initialize() => _initialization ??= _restore();

  Future<void> _restore() async {
    final generation = _generation;
    try {
      final raw = await _store.read();
      if (raw == null || generation != _generation) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != 1 || data['projectId'] != projectId) {
        throw const FormatException('Invalid saved session.');
      }
      final uid = _requiredString(data, 'uid');
      final refresh = _requiredString(data, 'refreshToken');
      final email = data['email'];
      if (email != null && email is! String) throw const FormatException();
      _user = AccountUser(uid: uid, email: email as String?);
      _refreshToken = refresh;
      // No persisted ID token or expiry: the next remote operation must refresh.
      _changes.add(_user);
    } catch (_) {
      if (generation != _generation) return;
      // A corrupt or inaccessible credential must not make local work unusable.
      await _invalidate(generation, ignoreStorageFailure: true);
    }
  }

  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) => _authenticate('signInWithPassword', email, password);

  @override
  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) => _authenticate('signUp', email, password);

  Future<void> _authenticate(
    String operation,
    String email,
    String password,
  ) async {
    final generation = ++_generation;
    final data = await _authRequest(operation, {
      'email': email.trim(),
      'password': password,
      'returnSecureToken': true,
    });
    _checkGeneration(generation);
    if (data['mfaPendingCredential'] != null) {
      throw FirebaseAuthException(
        code: 'unsupported-second-factor',
        message:
            'This account requires a second sign-in factor. Use Ripot on the web for this account.',
      );
    }
    try {
      final user = AccountUser(
        uid: _requiredString(data, 'localId'),
        email: data['email'] as String? ?? email.trim(),
      );
      await _commit(
        user,
        _requiredString(data, 'idToken'),
        _requiredString(data, 'refreshToken'),
        _expiry(data['expiresIn']),
        generation,
      );
    } on FormatException {
      throw _invalidResponse();
    } on TypeError {
      throw _invalidResponse();
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    await _authRequest('sendOobCode', {
      'requestType': 'PASSWORD_RESET',
      'email': email.trim(),
    });
  }

  Future<Map<String, dynamic>> _authRequest(
    String operation,
    Map<String, dynamic> body,
  ) async {
    final response = await _request(
      Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:$operation', {
        'key': apiKey,
      }),
      body,
    );
    if (response.status != 200) throw _serverError(response);
    if (response.data is! Map<String, dynamic>) throw _invalidResponse();
    return response.data as Map<String, dynamic>;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    if (_user == null) return null;
    if (!forceRefresh &&
        _idToken != null &&
        (_expiresAt?.isAfter(_now().add(const Duration(minutes: 1))) ??
            false)) {
      return _idToken;
    }
    final generation = _generation;
    if (_refreshGeneration == generation && _refreshing != null) {
      return _refreshing;
    }
    _refreshGeneration = generation;
    final future = _refresh(generation, _user!, _refreshToken!);
    _refreshing = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<String?> _refresh(
    int generation,
    AccountUser user,
    String refreshToken,
  ) async {
    final response = await _request(
      Uri.https('securetoken.googleapis.com', '/v1/token', {'key': apiKey}),
      {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      form: true,
    );
    _checkGeneration(generation);
    if (response.status != 200) {
      final error = _serverError(response);
      if (const {
        'user-disabled',
        'user-token-expired',
        'invalid-user-token',
        'user-not-found',
      }.contains(error.code)) {
        await _invalidate(generation);
      }
      throw error;
    }
    try {
      final data = response.data as Map<String, dynamic>;
      if (_requiredString(data, 'user_id') != user.uid) {
        await _invalidate(generation);
        throw FirebaseAuthException(
          code: 'invalid-user-token',
          message: 'Please sign in again.',
        );
      }
      final token = _requiredString(data, 'id_token');
      await _commit(
        user,
        token,
        _requiredString(data, 'refresh_token'),
        _expiry(data['expires_in']),
        generation,
      );
      return token;
    } on FormatException {
      throw _invalidResponse();
    } on TypeError {
      throw _invalidResponse();
    }
  }

  Future<void> _commit(
    AccountUser user,
    String idToken,
    String refreshToken,
    DateTime expiresAt,
    int generation,
  ) async {
    _checkGeneration(generation);
    try {
      await _withStorage(() async {
        _checkGeneration(generation);
        await _store.write(
          jsonEncode({
            'version': 1,
            'projectId': projectId,
            'uid': user.uid,
            'email': user.email,
            'refreshToken': refreshToken,
          }),
        );
      });
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      await _invalidate(generation, ignoreStorageFailure: true);
      throw FirebaseAuthException(
        code: 'secure-storage-unavailable',
        message:
            'Windows could not securely save this sign-in. Please try again.',
      );
    }
    _checkGeneration(generation);
    final changed = _user?.uid != user.uid || _user?.email != user.email;
    _user = user;
    _idToken = idToken;
    _refreshToken = refreshToken;
    _expiresAt = expiresAt;
    if (changed) _changes.add(user);
  }

  @override
  Future<void> signOut() => _invalidate(_generation);

  Future<void> _invalidate(
    int generation, {
    bool ignoreStorageFailure = false,
  }) async {
    if (generation != _generation) return;
    ++_generation;
    _user = null;
    _refreshToken = null;
    _idToken = null;
    _expiresAt = null;
    _changes.add(null);
    try {
      // Always queue deletion after earlier writes. A later login writes after
      // this deletion, so it cannot be erased by a late sign-out completion.
      await _withStorage(_store.clear);
    } catch (_) {
      if (!ignoreStorageFailure) {
        throw FirebaseAuthException(
          code: 'secure-storage-unavailable',
          message:
              'Signed out of this session, but Windows could not clear the saved sign-in. Retry sign-out before closing Ripot.',
        );
      }
    }
  }

  Future<void> _withStorage(Future<void> Function() action) {
    final operation = _storageQueue.then((_) => action());
    _storageQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _checkGeneration(int generation) {
    if (_generation != generation) {
      throw FirebaseAuthException(
        code: 'operation-cancelled',
        message: 'The account changed. Please try again.',
      );
    }
  }

  DateTime _expiry(dynamic seconds) {
    final value = int.tryParse('$seconds');
    if (value == null || value <= 0 || value > 86400) {
      throw const FormatException();
    }
    return _now().add(Duration(seconds: value));
  }

  static String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.trim().isEmpty) throw const FormatException();
    return value;
  }

  Future<RestResponse> _request(
    Uri uri,
    Map<String, dynamic> body, {
    bool form = false,
  }) async {
    try {
      return await _client.request('POST', uri, body: body, form: form);
    } on RestTransportException {
      throw FirebaseAuthException(
        code: 'network-request-failed',
        message:
            'Could not connect. Check your internet connection and try again.',
      );
    }
  }

  static FirebaseAuthException _invalidResponse() => FirebaseAuthException(
    code: 'internal-error',
    message: 'Could not complete sign-in. Please try again.',
  );

  static FirebaseAuthException _serverError(RestResponse response) {
    final data = response.data;
    final error = data is Map ? data['error'] : null;
    final message = error is Map ? error['message'] : null;
    final reason = message is String ? message.split(' : ').first : '';
    final code = switch (reason) {
      'EMAIL_NOT_FOUND' ||
      'INVALID_PASSWORD' ||
      'INVALID_LOGIN_CREDENTIALS' => 'invalid-credential',
      'EMAIL_EXISTS' => 'email-already-in-use',
      'WEAK_PASSWORD' => 'weak-password',
      'INVALID_EMAIL' || 'MISSING_EMAIL' => 'invalid-email',
      'TOO_MANY_ATTEMPTS_TRY_LATER' ||
      'TOO_MANY_REQUESTS' => 'too-many-requests',
      'USER_DISABLED' => 'user-disabled',
      'USER_NOT_FOUND' => 'user-not-found',
      'TOKEN_EXPIRED' => 'user-token-expired',
      'INVALID_REFRESH_TOKEN' || 'INVALID_ID_TOKEN' => 'invalid-user-token',
      'OPERATION_NOT_ALLOWED' ||
      'PASSWORD_LOGIN_DISABLED' => 'operation-not-allowed',
      _ => response.status == 429 ? 'too-many-requests' : 'internal-error',
    };
    final friendly = switch (code) {
      'user-disabled' => 'This account has been disabled. Contact support.',
      'user-token-expired' ||
      'invalid-user-token' => 'Your sign-in has expired. Please sign in again.',
      'operation-not-allowed' =>
        'Email sign-in is not available for this build. Contact support.',
      _ => 'Could not complete this account request. Please try again.',
    };
    return FirebaseAuthException(code: code, message: friendly);
  }
}
