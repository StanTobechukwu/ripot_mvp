import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ripot/features/reports/ui/template_actions.dart';

class DelayedAccessRepository extends AccessRepository {
  AccessState? cached;
  final remote = Completer<AccessState>();
  final trial = Completer<AccessState?>();
  @override
  Future<AccessState?> loadCached() async => cached;
  @override
  Future<AccessState> load({bool refreshPlay = true}) => remote.future;
  @override
  Future<AccessState?> activatePremiumTrialForSignedInAccount() => trial.future;
  @override
  Future<void> save(AccessState state) async {}
}

void main() {
  test(
    'cached account access is visible while remote check is pending',
    () async {
      final repo = DelayedAccessRepository();
      repo.cached = AccessState.initial(installationId: 'a').copyWith(
        plan: RipotPlan.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 1)),
      );
      final provider = AccessProvider(repo: repo);
      final pending = provider.load();
      await Future<void>.delayed(Duration.zero);
      expect(provider.safeState.canUseRecords, isTrue);
      provider.resetForAccountChange();
      repo.remote.complete(repo.cached!);
      await pending;
      expect(provider.safeState.canUseRecords, isFalse);
      expect(provider.loading, isFalse);
      provider.dispose();
    },
  );
  test(
    'trial response unlocks features without another network refresh',
    () async {
      final repo = DelayedAccessRepository();
      final provider = AccessProvider(repo: repo);
      final activation = provider.activatePremiumTrial();
      repo.trial.complete(
        AccessState.initial(installationId: 'a').copyWith(
          plan: RipotPlan.trial,
          trialEndsAt: DateTime.now().add(const Duration(days: 21)),
          hasUsedTrial: true,
        ),
      );
      expect(await activation, isTrue);
      expect(provider.safeState.canUseRecords, isTrue);
      provider.dispose();
    },
  );
  test('account change discards pending trial response', () async {
    final repo = DelayedAccessRepository();
    final provider = AccessProvider(repo: repo);
    final activation = provider.activatePremiumTrial();
    provider.resetForAccountChange();
    repo.trial.complete(
      AccessState.initial(installationId: 'a').copyWith(
        plan: RipotPlan.trial,
        trialEndsAt: DateTime.now().add(const Duration(days: 21)),
      ),
    );
    expect(await activation, isFalse);
    expect(provider.safeState.canUseRecords, isFalse);
    provider.dispose();
  });
  test(
    'verified paid response invalidates an older pending free response',
    () async {
      final repo = DelayedAccessRepository();
      final provider = AccessProvider(repo: repo);
      final pending = provider.refresh();
      provider.acceptVerifiedPremium(
        DateTime.now().add(const Duration(days: 30)),
      );
      repo.remote.complete(AccessState.initial(installationId: 'a'));
      await pending;
      expect(provider.safeState.canUseRecords, isTrue);
      provider.dispose();
    },
  );
  test('expired subscription does not unlock features', () {
    final state = AccessState.initial(installationId: 'a').copyWith(
      plan: RipotPlan.premium,
      premiumExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect(state.canUseRecords, isFalse);
    expect(
      AccessState.fromJson(state.toJson()).premiumExpiresAt,
      state.premiumExpiresAt,
    );
  });
  test(
    'four personal templates are separate from starters and starter copies count',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = TemplatesRepository();
      final starters = await repo.listTemplates();
      expect(starters.where((t) => !t.isBuiltIn), isEmpty);
      final builtIn = await repo.loadTemplate(starters.first.templateId);
      await repo.saveTemplate(copyTemplate(builtIn, 'My version'));
      expect(
        (await repo.listTemplates()).where((t) => !t.isBuiltIn),
        hasLength(1),
      );
      expect(AccessState.initial(installationId: 'a').maxSavedTemplates, 4);
    },
  );
}
