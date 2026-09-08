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

    final now = DateTime.now();

    // Trial dates are created once. They must never be refreshed by an app
    // update, reinstall, logout/login, or later configuration change.
    final startAt = current.trialStartAt ?? now;
    final endsAt =
        current.trialEndsAt ??
        startAt.add(Duration(days: current.trialLengthDays));

    final next = current.copyWith(
      plan: RipotPlan.trial,
      trialStartAt: startAt,
      trialEndsAt: endsAt,
      hasUsedTrial: true,
      updatedAt: now,
    );
    _state = next;
    notifyListeners();
    await repo.save(next);
    return true;
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
    await refresh();
  }
}
