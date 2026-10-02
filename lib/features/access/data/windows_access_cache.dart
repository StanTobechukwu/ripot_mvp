import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProtectedAccessCache {
  Future<String?> read(String uid);
  Future<void> write(String uid, String value);
}

/// Windows uses the same encrypted storage plugin as its account session.
/// Editing a plan or expiry in the ordinary preferences cannot grant access.
class WindowsAccessCache implements ProtectedAccessCache {
  const WindowsAccessCache({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;
  final FlutterSecureStorage _storage;
  String _key(String uid) => 'ripot.windows.verified-access.v1.$uid';

  @override
  Future<String?> read(String uid) => _storage.read(key: _key(uid));

  @override
  Future<void> write(String uid, String value) =>
      _storage.write(key: _key(uid), value: value);
}
