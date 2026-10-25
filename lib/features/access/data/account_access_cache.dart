import 'dart:convert';

import '../domain/access_state.dart';

/// Encodes entitlement cache entries with an explicit Firebase UID owner.
/// A cache entry is valid only for the same authenticated account.
class AccountAccessCache {
  static const int version = 2;
  static const String _keyPrefix = 'access.state.user.';

  static String keyForUid(String authUid) => '$_keyPrefix$authUid';

  static String encode({required String authUid, required AccessState state}) {
    return jsonEncode({
      'cacheVersion': version,
      'authUid': authUid,
      'state': state.toJson(),
    });
  }

  static AccessState? decodeForUid(String raw, {required String authUid}) {
    if (raw.trim().isEmpty) return null;
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      if (envelope['cacheVersion'] != version) return null;
      if (envelope['authUid'] != authUid) return null;
      final stateJson = envelope['state'];
      if (stateJson is! Map) return null;
      return AccessState.fromJson(stateJson.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
