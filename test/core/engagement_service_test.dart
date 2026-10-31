import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/core/services/engagement_service.dart';

void main() {
  test('review needs ten new shares and a ninety day cooldown', () {
    final now = DateTime(2026, 10, 31);
    expect(
      shouldRequestReview(shares: 9, lastRequestShares: 0, now: now),
      false,
    );
    expect(
      shouldRequestReview(shares: 10, lastRequestShares: 0, now: now),
      true,
    );
    expect(
      shouldRequestReview(
        shares: 20,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 89)),
      ),
      false,
    );
    expect(
      shouldRequestReview(
        shares: 19,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 91)),
      ),
      false,
    );
    expect(
      shouldRequestReview(
        shares: 20,
        lastRequestShares: 10,
        now: now,
        lastRequest: now.subtract(const Duration(days: 90)),
      ),
      true,
    );
  });
}
