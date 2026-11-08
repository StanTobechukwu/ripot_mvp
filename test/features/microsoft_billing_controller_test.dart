import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/billing/providers/microsoft_billing_controller.dart';
import 'package:ripot/features/billing/services/microsoft_store_client.dart';

class FakeStore implements MicrosoftStoreClient {
  int purchases = 0;
  String outcome = 'purchased';
  void Function()? onPurchase;
  @override
  Future<List<MicrosoftProduct>> products(
    String monthlyId,
    String annualId,
  ) async => [
    MicrosoftProduct(
      id: monthlyId,
      title: 'Monthly',
      price: r'$3',
      period: 'month',
      owned: false,
    ),
    MicrosoftProduct(
      id: annualId,
      title: 'Annual',
      price: r'$30',
      period: 'year',
      owned: false,
    ),
  ];
  @override
  Future<String> purchase(String id) async {
    purchases++;
    onPurchase?.call();
    return outcome;
  }

  @override
  Future<String> purchaseKey(String ticket, String publisherUserId) async =>
      'key-$publisherUserId';
}

void main() {
  late FakeStore store;
  late MicrosoftBillingController controller;
  late AccessState access;
  String? uid;
  var enabled = true, failVerification = false, entitled = false;
  var verifies = 0, refreshes = 0;
  setUp(() {
    uid = 'alice';
    store = FakeStore();
    enabled = true;
    failVerification = false;
    entitled = false;
    verifies = 0;
    refreshes = 0;
    access = AccessState.initial(
      installationId: 'device',
    ).copyWith(hasUsedTrial: true).verifiedNow();
    controller = MicrosoftBillingController(
      store: store,
      currentUid: () => uid,
      access: () => access,
      refreshAccess: () async {
        refreshes++;
      },
      call: (name, data) async {
        switch (name) {
          case 'getMicrosoftBillingConfig':
            return {
              'enabled': enabled,
              'monthlyId': 'monthly',
              'annualId': 'annual',
            };
          case 'getMicrosoftPurchaseTicket':
            return {'serviceTicket': 'restricted', 'publisherUserId': uid};
          case 'verifyMicrosoftSubscription':
            verifies++;
            if (failVerification) throw StateError('offline');
            return {'entitled': entitled || store.purchases > 0};
          default:
            throw StateError(name);
        }
      },
    );
  });
  tearDown(() => controller.dispose());
  test('disabled backend never opens the Store checkout', () async {
    enabled = false;
    await controller.load();
    expect(controller.canBuy, false);
    expect(controller.products, isEmpty);
    expect(store.purchases, 0);
  });
  test(
    'purchase requires verification before and after checkout; does not grant access locally',
    () async {
      await controller.load();
      expect(controller.canBuy, true);
      await controller.purchase(controller.products.first);
      expect(store.purchases, 1);
      expect(verifies, 2);
      expect(refreshes, 2);
      expect(access.plan, RipotPlan.free);
      expect(controller.message, contains('Premium is active'));
    },
  );
  test('cancelled checkout performs no post-purchase grant', () async {
    store.outcome = 'cancelled';
    await controller.load();
    await controller.purchase(controller.products.first);
    expect(verifies, 1);
    expect(controller.message, 'Purchase cancelled.');
    expect(access.plan, RipotPlan.free);
  });
  test(
    'failed preflight never charges; existing subscriptions restore instead',
    () async {
      await controller.load();
      failVerification = true;
      await controller.purchase(controller.products.first);
      expect(store.purchases, 0);
      failVerification = false;
      entitled = true;
      await controller.purchase(controller.products.first);
      expect(store.purchases, 0);
      expect(controller.message, contains('existing Microsoft subscription'));
    },
  );
  test(
    'account switch during checkout never verifies for the new account',
    () async {
      await controller.load();
      store.onPurchase = () => uid = 'bob';
      await controller.purchase(controller.products.first);
      expect(verifies, 1);
      expect(controller.canBuy, false);
      expect(controller.message, contains('Restore purchases'));
    },
  );
  test('active trial blocks purchase but allows restoration', () async {
    access = access.copyWith(
      plan: RipotPlan.trial,
      trialEndsAt: DateTime.now().add(const Duration(days: 2)),
    );
    await controller.load();
    expect(controller.canBuy, false);
    await controller.purchase(controller.products.first);
    expect(store.purchases, 0);
    await controller.restore();
    expect(verifies, 1);
  });
  test(
    'network failure after payment asks for restore and never grants locally',
    () async {
      await controller.load();
      store.onPurchase = () => failVerification = true;
      await controller.purchase(controller.products.first);
      expect(controller.message, contains('Restore purchases'));
      expect(access.plan, RipotPlan.free);
    },
  );
}
