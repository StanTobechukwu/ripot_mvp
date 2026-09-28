import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/domain/access_state.dart';

void main() {
  group('AccessState server-authoritative trials', () {
    test('new installations are not assumed to be early users', () {
      final state = AccessState.initial(installationId: 'install-1');

      expect(state.isEarlyUser, isFalse);
      expect(state.earlyAccessEnabled, isFalse);
      expect(state.trialLengthDays, AccessState.defaultStandardTrialDays);
    });

    test(
      'uses the exact server trial end even when legacy flags say 84 days',
      () {
        final start = DateTime.utc(2026, 9, 10);
        final serverEnd = DateTime.utc(2026, 10, 1);
        final state = AccessState(
          installationId: 'install-1',
          plan: RipotPlan.trial,
          isEarlyUser: true,
          createdAt: start,
          updatedAt: start,
          trialStartAt: start,
          trialEndsAt: serverEnd,
          hasUsedTrial: true,
          earlyAccessEnabled: true,
          earlyAccessDurationDays: 84,
        );

        expect(state.effectiveTrialEndsAt, serverEnd);
        expect(state.trialLengthDays, 21);
        expect(state.toJson()['trialEndsAtIso'], serverEnd.toIso8601String());
      },
    );

    test('preserves an 84-day Founder grant written by the server', () {
      final start = DateTime.utc(2026, 9, 10);
      final serverEnd = start.add(const Duration(days: 84));
      final state = AccessState(
        installationId: 'install-1',
        plan: RipotPlan.trial,
        isEarlyUser: false,
        createdAt: start,
        updatedAt: start,
        trialStartAt: start,
        trialEndsAt: serverEnd,
        hasUsedTrial: true,
        founderCohort: 'founding_100',
        founderNumber: 100,
      );

      expect(state.effectiveTrialEndsAt, serverEnd);
      expect(state.trialLengthDays, 84);
      expect(state.isFounding100, isTrue);
    });

    test('Founder identity does not grant lifetime Premium', () {
      final state = AccessState.initial(installationId: 'install-1').copyWith(
        plan: RipotPlan.trial,
        founderCohort: 'founding_100',
        founderNumber: 1,
        hasUsedTrial: true,
        trialStartAt: DateTime.utc(2020, 1, 1),
        trialEndsAt: DateTime.utc(2020, 3, 25),
      );

      expect(state.isFounding100, isTrue);
      expect(state.isPremiumLike, isFalse);
      expect(state.canActivatePremiumTrial, isFalse);
    });

    test('invalid Founder numbers are not displayed as membership', () {
      final state = AccessState.initial(installationId: 'install-1');
      for (final number in [-1, 0, 101]) {
        expect(
          state.copyWith(
            founderCohort: 'founding_100',
            founderNumber: number,
          ).isFounding100,
          isFalse,
        );
      }
    });

    test('existing trial dates prevent a second activation invitation', () {
      final state = AccessState.initial(installationId: 'install-1').copyWith(
        trialStartAt: DateTime.utc(2020, 1, 1),
        trialEndsAt: DateTime.utc(2020, 1, 22),
      );
      expect(state.canActivatePremiumTrial, isFalse);
    });
  });
}
