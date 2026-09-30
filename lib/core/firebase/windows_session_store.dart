import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// Credentials use the Windows encrypted storage implementation. Preferences
/// contain only a signed-out marker, never a password, token or account ID.
class WindowsSessionStore implements SessionStore {
  WindowsSessionStore(String projectId, {FlutterSecureStorage? storage})
    : _key = 'ripot.windows.account.$projectId.v1',
      _storage = storage ?? const FlutterSecureStorage();
  final String _key;
  final FlutterSecureStorage _storage;
  String get _enabledKey => '$_key.enabled';

  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) != true) return null;
    return _storage.read(key: _key);
  }

  @override
  Future<void> write(String value) async {
    await _storage.write(key: _key, value: value);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool(_enabledKey, true)) {
      throw StateError('Could not persist the sign-in state.');
    }
  }

  @override
  Future<void> clear() async {
    // This tombstone prevents a stored token from signing the user back in if
    // the subsequent secure-storage deletion fails or the app closes mid-way.
    var disabled = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      disabled = await prefs.setBool(_enabledKey, false);
    } catch (_) {
      // Deleting the credential also makes restoration impossible.
    }
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      if (!disabled) throw StateError('Could not persist sign-out.');
    }
  }
}
