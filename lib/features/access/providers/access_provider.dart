import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/access_repository.dart';
import '../domain/access_state.dart';

class AccessProvider extends ChangeNotifier {
  final AccessRepository repo;

  AccessProvider({required this.repo});

  AccessState? _state;
  bool _loading = false;
  int _loadGeneration = 0;
  bool _disposed = false;
  Timer? _expiryTimer;
  DateTime? _lastRecheckAttempt;

  void _accessChanged() {
    if (_disposed) return;
    _expiryTimer?.cancel();
    final now = DateTime.now();
    final dates = [
      safeState.offlineAccessUntil,
      safeState.premiumExpiresAt,
      safeState.trialEndsAt,
    ].whereType<DateTime>().where((date) => date.isAfter(now)).toList()..sort();
    if (dates.isNotEmpty) {
      _expiryTimer = Timer(dates.first.difference(now), _accessChanged);
    }
    notifyListeners();
  }

  Future<void> recheckIfDue() async {
    if (_disposed || _loading) return;
    final now = DateTime.now();
    final last = _lastRecheckAttempt;
    if (last != null &&
        now.difference(last).inSeconds >= 0 &&
        now.difference(last) < const Duration(minutes: 1))
      return;
    _lastRecheckAttempt = now;
    try {
      await refresh();
    } catch (_) {
      // Existing access is bounded by its offline deadline. Connectivity must
      // never interrupt editing or access to saved PDFs.
    }
  }

  bool get loading => _loading;
  AccessState? get state => _state;
  AccessState get safeState =>
      _state ?? AccessState.initial(installationId: 'local');

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    _accessChanged();
    try {
      final cached = await repo.loadCached();
      if (generation != _loadGeneration) return;
      if (cached != null) {
        _state = cached;
        _accessChanged();
      }
      final next = await repo.load();
      if (generation == _loadGeneration) _state = next;
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        _accessChanged();
      }
    }
  }

  Future<bool> activatePremiumTrial() async {
    final current = safeState;
    if (!current.canActivatePremiumTrial) return false;
    final generation = _loadGeneration;

    // Trial creation is server-authoritative. The backend atomically decides
    // Founding 100 vs standard trial and writes fixed start/end dates.
    final activated = await repo.activatePremiumTrialForSignedInAccount();
    if (generation != _loadGeneration) return false;
    if (activated == null) {
      await refresh(refreshPlay: false);
      return safeState.isPremiumLike;
    }
    _loadGeneration++;
    _state = activated;
    _loading = false;
    _accessChanged();
    unawaited(repo.save(activated).catchError((Object _) {}));
    return safeState.isPremiumLike;
  }

  Future<bool> startTrial() => activatePremiumTrial();

  Future<void> markPremium() async {
    if (!kDebugMode) return;
    // Debug-only session override. Never persist this as verified account access.
    _loadGeneration++;
    _state = safeState
        .copyWith(
          plan: RipotPlan.premium,
          premiumExpiresAt: DateTime.now().add(const Duration(hours: 1)),
        )
        .verifiedNow();
    _loading = false;
    _accessChanged();
  }

  /// Called only with an authenticated subscription-verification response.
  void acceptVerifiedPremium(DateTime expiresAt) {
    if (!expiresAt.isAfter(DateTime.now())) return;
    _loadGeneration++;
    final now = DateTime.now();
    final next = safeState
        .copyWith(
          plan: RipotPlan.premium,
          premiumStartedAt: now,
          premiumExpiresAt: expiresAt,
          updatedAt: now,
        )
        .verifiedNow();
    _state = next;
    _loading = false;
    _accessChanged();
    unawaited(repo.save(next).catchError((Object _) {}));
  }

  Future<void> refresh({bool refreshPlay = true}) async {
    final generation = ++_loadGeneration;
    _loading = true;
    _accessChanged();
    try {
      final next = await repo.load(refreshPlay: refreshPlay);
      if (generation == _loadGeneration) _state = next;
    } finally {
      if (generation == _loadGeneration) {
        _loading = false;
        _accessChanged();
      }
    }
  }

  /// Immediately removes account-owned access while Firebase Auth changes.
  /// The incoming account is then loaded from its own server/cache state.
  void resetForAccountChange() {
    _loadGeneration++;
    _lastRecheckAttempt = null;
    _loading = false;
    final current = safeState;
    _state = AccessState.initial(installationId: current.installationId)
        .copyWith(
          premiumBillingEnabled: current.premiumBillingEnabled,
          premiumMessageTitle: current.premiumMessageTitle,
          premiumMessageBody: current.premiumMessageBody,
        );
    _accessChanged();
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    await repo.migrateCloudIdentityToSignedInUser();
    await repo.syncFounderEntitlementForSignedInAccount();
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _expiryTimer?.cancel();
    super.dispose();
  }
}
