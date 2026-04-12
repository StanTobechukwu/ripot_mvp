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

  Future<void> startTrial() async {
    final current = safeState;
    if (current.hasUsedTrial || current.isPremiumLike) return;
    final now = DateTime.now();
    final next = current.copyWith(
      plan: RipotPlan.trial,
      trialStartAt: now,
      trialEndsAt: now.add(Duration(days: current.trialLengthDays)),
      hasUsedTrial: true,
      updatedAt: now,
    );
    _state = next;
    notifyListeners();
    await repo.save(next);
  }

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
