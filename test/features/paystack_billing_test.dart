import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/billing/paystack_billing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const plan = PaystackPlan(
    id: 'usd_monthly',
    amount: 599,
    currency: 'USD',
    interval: 'monthly',
    markets: ['international'],
  );
  Map<String, dynamic> catalog({String? locked}) => {
    'enabled': true,
    'mode': 'live',
    'internationalEnabled': true,
    'locked': locked,
    'plans': [
      {
        'id': plan.id,
        'amount': plan.amount,
        'currency': plan.currency,
        'interval': plan.interval,
        'markets': plan.markets,
      },
    ],
  };
  test('displays exact subunit prices and billing periods', () {
    expect(plan.price, 'US\$5.99');
    expect(plan.period, 'month');
    expect(
      const PaystackPlan(
        id: 'ng',
        amount: 2500000,
        currency: 'NGN',
        interval: 'annually',
        markets: ['NG'],
      ).price,
      '₦25,000.00',
    );
  });
  test(
    'checkout sends only server plan id and market, never an amount or UID',
    () async {
      final calls = <String>[];
      var refreshes = 0, launches = 0;
      final billing = PaystackBilling(
        currentUid: () => 'alice',
        refreshAccess: () async {
          refreshes++;
        },
        call: (name, data) async {
          calls.add(name);
          if (name == 'getPaystackPlans') return catalog();
          expect(data, {'planId': 'usd_monthly', 'market': 'international'});
          return {'authorizationUrl': 'https://checkout.paystack.com/fixture'};
        },
        launch: (_) async {
          launches++;
          return true;
        },
      );
      addTearDown(billing.dispose);
      await billing.load();
      await billing.checkout(plan, 'international');
      expect(calls, ['getPaystackPlans', 'startPaystackCheckout']);
      expect(launches, 1);
      expect(refreshes, 0); // No client-side grant from success/redirect.
    },
  );
  test('trial and existing paid access block another checkout', () async {
    for (final lock in ['trial', 'paid']) {
      var calls = 0;
      final billing = PaystackBilling(
        currentUid: () => 'alice',
        refreshAccess: () async {},
        call: (_, _) async {
          calls++;
          return catalog(locked: lock);
        },
      );
      await billing.load();
      await billing.checkout(plan, 'international');
      expect(calls, 1);
      billing.dispose();
    }
  });
  test('account switch discards an in-flight checkout URL', () async {
    var uid = 'alice', launched = false;
    final pending = Completer<dynamic>();
    final billing = PaystackBilling(
      currentUid: () => uid,
      refreshAccess: () async {},
      call: (name, _) async =>
          name == 'getPaystackPlans' ? catalog() : pending.future,
      launch: (_) async {
        launched = true;
        return true;
      },
    );
    addTearDown(billing.dispose);
    await billing.load();
    final work = billing.checkout(plan, 'international');
    uid = 'bob';
    billing.reset();
    pending.complete({
      'authorizationUrl': 'https://checkout.paystack.com/fixture',
    });
    await work;
    expect(launched, false);
    expect(billing.plans, isEmpty);
  });
  test('rejects unexpected checkout domains and credentials in URLs', () async {
    for (final url in [
      'https://checkout.paystack.com.evil.test/x',
      'http://checkout.paystack.com/x',
      'https://alice@checkout.paystack.com/x',
    ]) {
      var launched = false;
      final billing = PaystackBilling(
        currentUid: () => 'alice',
        refreshAccess: () async {},
        call: (name, _) async =>
            name == 'getPaystackPlans' ? catalog() : {'authorizationUrl': url},
        launch: (_) async {
          launched = true;
          return true;
        },
      );
      await billing.load();
      await billing.checkout(plan, 'international');
      expect(launched, false);
      expect(billing.error, isNotNull);
      billing.dispose();
    }
  });
  test('payment check refreshes authoritative account state', () async {
    var refreshes = 0;
    final billing = PaystackBilling(
      currentUid: () => 'alice',
      refreshAccess: () async {
        refreshes++;
      },
      call: (name, _) async => name == 'getPaystackPlans'
          ? catalog()
          : {'mode': 'test', 'entitled': true},
    );
    addTearDown(billing.dispose);
    await billing.load(refreshPayment: true);
    expect(refreshes, 1);
    expect(billing.message, contains('No live Premium access was changed'));
  });
  test('Android does not expose Paystack checkout', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PaystackBilling.supported, false);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(PaystackBilling.supported, true);
    debugDefaultTargetPlatformOverride = null;
  });
}
