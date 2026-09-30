import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/billing/providers/billing_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Windows billing does not touch a store or require Firebase startup',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final access = AccessProvider(repo: AccessRepository());
      final billing = BillingProvider(accessProvider: access);
      addTearDown(billing.dispose);
      addTearDown(access.dispose);

      await Future<void>.delayed(Duration.zero);
      await billing.load();
      expect(billing.available, isFalse);
      expect(billing.canPurchase, isFalse);
      expect(billing.canRestore, isFalse);
      expect(await billing.purchaseMonthly(), isFalse);
      expect(await billing.purchaseAnnual(), isFalse);
      await billing.restorePurchases();
      expect(billing.error, isNull);
    },
  );

  test('disposing before deferred billing load is safe', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final access = AccessProvider(repo: AccessRepository());
    BillingProvider(accessProvider: access).dispose();
    await Future<void>.delayed(Duration.zero);
    access.dispose();
  });
}
