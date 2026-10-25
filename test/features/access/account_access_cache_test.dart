import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/data/account_access_cache.dart';
import 'package:ripot/features/access/domain/access_state.dart';

void main() {
  test('account cache is accepted only for its Firebase UID', () {
    final now = DateTime.utc(2026, 9, 10);
    final state = AccessState(
      installationId: 'install-1',
      plan: RipotPlan.trial,
      isEarlyUser: false,
      createdAt: now,
      updatedAt: now,
      trialStartAt: now,
      trialEndsAt: now.add(const Duration(days: 21)),
      hasUsedTrial: true,
    );
    final encoded = AccountAccessCache.encode(
      authUid: 'account-a',
      state: state,
    );

    expect(
      AccountAccessCache.decodeForUid(
        encoded,
        authUid: 'account-a',
      )?.hasUsedTrial,
      isTrue,
    );
    expect(
      AccountAccessCache.decodeForUid(encoded, authUid: 'account-b'),
      isNull,
    );
  });

  test('malformed and unversioned cache values are rejected', () {
    expect(
      AccountAccessCache.decodeForUid('not-json', authUid: 'account-a'),
      isNull,
    );
    expect(
      AccountAccessCache.decodeForUid(
        '{"authUid":"account-a","state":{}}',
        authUid: 'account-a',
      ),
      isNull,
    );
  });
}
