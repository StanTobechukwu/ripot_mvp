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
  AccessState get safeState => _state ?? AccessState.initial(installationId: 'local', isEarlyUser: true);

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
    var startAt = current.trialStartAt ?? now;
    var endsAt = startAt.add(Duration(days: current.trialLengthDays));

    // Existing users who were blocked by an older, shorter trial should not
    // remain stuck. If their historical trial window is already outside the
    // current early-access window, give them a fresh configured window.
    if (current.isEarlyUser && endsAt.isBefore(now)) {
      startAt = now;
      endsAt = now.add(Duration(days: current.trialLengthDays));
    }

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
