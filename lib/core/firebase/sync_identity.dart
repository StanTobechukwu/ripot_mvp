import 'package:shared_preferences/shared_preferences.dart';
import 'account_runtime.dart';
import 'account_session.dart';

class SyncIdentity {
  const SyncIdentity({
    required this.ownerType,
    required this.ownerId,
    required this.installationId,
    this.authUid,
  });

  final String ownerType; // 'local' | 'user'
  final String ownerId;
  final String installationId;
  final String? authUid;

  bool get isSignedInUser =>
      ownerType == 'user' && authUid != null && authUid!.isNotEmpty;
  String get documentKey => ownerId;
}

class SyncIdentityResolver {
  SyncIdentityResolver({AccountSession? session}) : _session = session;
  final AccountSession? _session;
  static const _installationIdKey = 'access.installationId';

  Future<SyncIdentity> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    final installationId = (prefs.getString(_installationIdKey) ?? '').trim();
    if (installationId.isEmpty) {
      throw StateError(
        'Installation ID missing. Load access state first before resolving sync identity.',
      );
    }

    try {
      final currentUser = (_session ?? AccountRuntime.session)?.currentUser;
      final uid = currentUser?.uid;
      if (uid != null && uid.trim().isNotEmpty) {
        return SyncIdentity(
          ownerType: 'user',
          ownerId: uid,
          installationId: installationId,
          authUid: uid,
        );
      }
    } catch (_) {
      // Auth is optional for stability. Fall back to local identity.
    }

    return SyncIdentity(
      ownerType: 'local',
      ownerId: installationId,
      installationId: installationId,
    );
  }
}
