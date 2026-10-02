import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/core/firebase/account_session.dart';
import 'package:ripot/core/firebase/cloud_documents.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/data/account_access_cache.dart';
import 'package:ripot/features/access/data/windows_access_cache.dart';
import 'package:ripot/features/access/domain/access_state.dart';

class Session extends Fake implements AccountSession {
  AccountUser? user = const AccountUser(uid: 'a');
  @override
  AccountUser? get currentUser => user;
}

class Documents extends Fake implements CloudDocuments {
  bool offline = false;
  Map<String, dynamic>? access;
  @override
  Future<Map<String, dynamic>?> get(
    String collection,
    String id, {
    bool serverOnly = false,
  }) async {
    if (offline) throw StateError('offline');
    if (collection == 'ripot_app_config') return {};
    expect(serverOnly, isTrue);
    return access;
  }

  @override
  Future<void> merge(
    String collection,
    String id,
    Map<String, dynamic> data,
  ) async {
    expect(data.containsKey('plan'), isFalse);
  }
}

class ProtectedCache implements ProtectedAccessCache {
  final entries = <String, String>{};
  bool unavailable = false;
  @override
  Future<String?> read(String uid) async {
    if (unavailable) throw StateError('secure storage unavailable');
    return entries[uid];
  }

  @override
  Future<void> write(String uid, String value) async {
    if (unavailable) throw StateError('secure storage unavailable');
    entries[uid] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Session session;
  late Documents documents;
  late ProtectedCache cache;
  late AccessRepository repo;
  AccessState paid() => AccessState.initial(installationId: 'demo')
      .copyWith(
        plan: RipotPlan.premium,
        premiumExpiresAt: DateTime.now().add(const Duration(days: 365)),
        hasUsedTrial: true,
      )
      .verifiedNow();
  void remember(AccessState state) {
    cache.entries['a'] = AccountAccessCache.encode(authUid: 'a', state: state);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    session = Session();
    documents = Documents();
    cache = ProtectedCache();
    repo = AccessRepository(
      session: session,
      documents: documents,
      protectedCache: cache,
    );
    documents.access = {
      'plan': 'premium',
      'playEntitlementExpiresAtIso': DateTime.now()
          .add(const Duration(days: 365))
          .toIso8601String(),
      'billingLastVerifiedAtIso': DateTime.now().toIso8601String(),
    };
  });

  test(
    'verified access survives reopening offline without extending its deadline',
    () async {
      final online = await repo.load(refreshPlay: false);
      expect(online.isPremiumLike, isTrue);
      final deadline = online.offlineAccessUntil;
      expect(
        deadline!.difference(DateTime.now()).inHours,
        lessThanOrEqualTo(72),
      );
      documents.offline = true;
      final reopened = AccessRepository(
        session: session,
        documents: documents,
        protectedCache: cache,
      );
      expect((await reopened.loadCached())?.isPremiumLike, isTrue);
      final offline = await reopened.load(refreshPlay: false);
      expect(offline.isPremiumLike, isTrue);
      expect(offline.offlineAccessUntil, deadline);
    },
  );

  test(
    'stale cache stops new Premium work and retains trial history',
    () async {
      remember(
        paid().copyWith(
          offlineAccessUntil: DateTime.now().subtract(
            const Duration(minutes: 1),
          ),
        ),
      );
      documents.offline = true;
      final state = await repo.load(refreshPlay: false);
      expect(state.isPremiumLike, isFalse);
      expect(state.needsOnlineVerification, isTrue);
      expect(state.hasUsedTrial, isTrue);
      expect(state.canActivatePremiumTrial, isFalse);
    },
  );

  test(
    'stale Play verification cannot be renewed by repeatedly reading Firestore',
    () async {
      documents.access!['billingLastVerifiedAtIso'] = DateTime.now()
          .subtract(const Duration(days: 4))
          .toIso8601String();
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      documents.access!['billingLastVerifiedAtIso'] = DateTime.now()
          .toIso8601String();
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isTrue);
    },
  );

  test(
    'preferences tampering and a different account cannot unlock Windows',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AccountAccessCache.keyForUid('a'),
        AccountAccessCache.encode(authUid: 'a', state: paid()),
      );
      documents.offline = true;
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      remember(paid());
      expect((await repo.loadCached())?.isPremiumLike, isTrue);
      cache.entries['b'] = cache.entries['a']!;
      session.user = const AccountUser(uid: 'b');
      expect(await repo.loadCached(), isNull);
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      session.user = null;
      expect(await repo.loadCached(), isNull);
    },
  );

  test(
    'legacy cache, clock rollback, expiry and unavailable secure storage fail closed',
    () async {
      documents.offline = true;
      for (final state in [
        paid().copyWith(accessVerifiedAt: null, offlineAccessUntil: null),
        paid().copyWith(
          accessLastSeenAt: DateTime.now().add(const Duration(hours: 1)),
        ),
        paid().copyWith(
          premiumExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        ),
      ]) {
        remember(state);
        expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
      }
      remember(paid());
      cache.unavailable = true;
      expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
    },
  );

  test('server revocation replaces cached Premium immediately', () async {
    remember(paid());
    documents.access = {'plan': 'free', 'hasUsedTrial': true};
    final state = await repo.load(refreshPlay: false);
    expect(state.isPremiumLike, isFalse);
    expect(state.hasCurrentVerification, isTrue);
    expect(state.canActivatePremiumTrial, isFalse);
    documents.offline = true;
    expect((await repo.load(refreshPlay: false)).isPremiumLike, isFalse);
  });

  test(
    'stale offline trial does not become eligibility for another trial or purchase',
    () {
      final state = AccessState.initial(installationId: 'demo').copyWith(
        plan: RipotPlan.trial,
        hasUsedTrial: true,
        trialEndsAt: DateTime.now().add(const Duration(days: 10)),
        offlineAccessUntil: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(state.isPremiumLike, isFalse);
      expect(state.canActivatePremiumTrial, isFalse);
      expect(state.isTrialActive, isTrue);
    },
  );
}
