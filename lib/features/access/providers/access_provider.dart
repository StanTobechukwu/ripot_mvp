import 'package:flutter/foundation.dart';

import '../data/access_repository.dart';
import '../domain/access_state.dart';

class AccessProvider extends ChangeNotifier {
  final AccessRepository repo;

  AccessProvider({required this.repo});

  AccessState? _state;
  bool _loading = false;

  bool get loading => _loading;
  AccessState? get state => _state;
  AccessState get safeState =>
      _state ?? AccessState.initial(installationId: 'local', isEarlyUser: true);

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _state = await repo.load();
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
    _state = await repo.load();
    notifyListeners();
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    await repo.migrateCloudIdentityToSignedInUser();
    await repo.syncFounderEntitlementForSignedInAccount();
    await refresh();
  }
}
