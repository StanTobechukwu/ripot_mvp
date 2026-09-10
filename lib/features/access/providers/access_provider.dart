import 'package:flutter/foundation.dart';

import '../data/access_repository.dart';
import '../domain/access_state.dart';

class AccessProvider extends ChangeNotifier {
  final AccessRepository repo;

  AccessProvider({required this.repo});

  AccessState? _state;
  bool _loading = false;
  int _loadGeneration = 0;

  bool get loading => _loading;
  AccessState? get state => _state;
  AccessState get safeState =>
      _state ?? AccessState.initial(installationId: 'local');

  Future<void> load() async {
    final generation = ++_loadGeneration;
    _loading = true;
    notifyListeners();
    final next = await repo.load();
    if (generation != _loadGeneration) return;
    _state = next;
    _loading = false;
    notifyListeners();
  }

  Future<bool> activatePremiumTrial() async {
    final current = safeState;
    if (!current.canActivatePremiumTrial) return false;

    // Trial creation is server-authoritative. The backend atomically decides
    // Founding 100 vs standard trial and writes fixed start/end dates.
    final activated = await repo.activatePremiumTrialForSignedInAccount();
    if (!activated) return false;

    await refresh();
    return safeState.isTrialActive;
  }

  Future<bool> startTrial() => activatePremiumTrial();

  Future<void> markPremium() async {
    final now = DateTime.now();
    final next = safeState.copyWith(
      plan: RipotPlan.premium,
      premiumStartedAt: now,
      updatedAt: now,
    );
    _state = next;
    notifyListeners();
    await repo.save(next);
  }

  Future<void> refresh() async {
    final generation = ++_loadGeneration;
    final next = await repo.load();
    if (generation != _loadGeneration) return;
    _state = next;
    notifyListeners();
  }

  /// Immediately removes account-owned access while Firebase Auth changes.
  /// The incoming account is then loaded from its own server/cache state.
  void resetForAccountChange() {
    _loadGeneration++;
    _loading = false;
    final current = safeState;
    _state = AccessState.initial(installationId: current.installationId)
        .copyWith(
          premiumBillingEnabled: current.premiumBillingEnabled,
          premiumMessageTitle: current.premiumMessageTitle,
          premiumMessageBody: current.premiumMessageBody,
        );
    notifyListeners();
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    await repo.migrateCloudIdentityToSignedInUser();
    await repo.syncFounderEntitlementForSignedInAccount();
    await refresh();
  }
}
