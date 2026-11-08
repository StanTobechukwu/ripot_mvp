import 'package:flutter/foundation.dart';
import '../../access/domain/access_state.dart';
import '../services/microsoft_store_client.dart';

typedef MicrosoftCallable =
    Future<dynamic> Function(String name, Map<String, dynamic> data);

/// Purchase UI state only. AccessProvider accepts entitlements from the server;
/// a successful Windows purchase dialog can never enable Premium locally.
class MicrosoftBillingController extends ChangeNotifier {
  MicrosoftBillingController({
    required this.store,
    required this.call,
    required this.currentUid,
    required this.access,
    required this.refreshAccess,
  });
  final MicrosoftStoreClient store;
  final MicrosoftCallable call;
  final String? Function() currentUid;
  final AccessState Function() access;
  final Future<void> Function() refreshAccess;
  bool busy = false, enabled = false, _disposed = false;
  List<MicrosoftProduct> products = const [];
  String? message;
  String? _loadedUid;

  bool get canBuy {
    final a = access();
    return enabled &&
        !busy &&
        currentUid() != null &&
        currentUid() == _loadedUid &&
        a.hasCurrentVerification &&
        !a.isPremiumLike &&
        !a.isTrialActive &&
        !(a.plan == RipotPlan.premium &&
            (a.premiumExpiresAt == null ||
                DateTime.now().isBefore(a.premiumExpiresAt!)));
  }

  void _check(String uid) {
    if (_disposed || currentUid() != uid) throw StateError('account-changed');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map> _call(
    String name,
    String uid, [
    Map<String, dynamic> data = const {},
  ]) async {
    _check(uid);
    final result = await call(name, data);
    _check(uid);
    if (result is! Map) throw StateError('invalid-response');
    return result;
  }

  Future<bool> _verify(String uid) async {
    final ticket = await _call('getMicrosoftPurchaseTicket', uid);
    if (ticket['publisherUserId'] != uid ||
        ticket['serviceTicket'] is! String) {
      throw StateError('invalid-ticket');
    }
    final key = await store.purchaseKey(ticket['serviceTicket'] as String, uid);
    _check(uid);
    final result = await _call('verifyMicrosoftSubscription', uid, {
      'key': key,
    });
    await refreshAccess();
    _check(uid);
    return result['entitled'] == true;
  }

  Future<void> load() async {
    if (busy || _disposed) return;
    final uid = currentUid();
    if (uid == null) return;
    busy = true;
    enabled = false;
    products = const [];
    message = null;
    _notify();
    try {
      final config = await _call('getMicrosoftBillingConfig', uid);
      if (config['enabled'] != true) {
        message =
            'Microsoft Store subscriptions are not available yet. You can keep using Ripot Free.';
        return;
      }
      final monthly = config['monthlyId'] as String;
      final annual = config['annualId'] as String;
      final found = await store.products(monthly, annual);
      _check(uid);
      products = found
          .where(
            (p) =>
                p.price.isNotEmpty &&
                ((p.id == monthly && p.period == 'month') ||
                    (p.id == annual && p.period == 'year')),
          )
          .toList();
      enabled = true;
      _loadedUid = uid;
      if (products.length != 2) {
        products = const [];
        message =
            'Plans could not be loaded from Microsoft Store. Try again shortly.';
      }
    } catch (_) {
      message =
          'Could not connect to Microsoft Store. Check your connection and sign-in, then retry.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> restore() async {
    if (busy || !enabled || _disposed) return;
    final uid = currentUid();
    if (uid == null) return;
    busy = true;
    message = null;
    _notify();
    try {
      final entitled = await _verify(uid);
      message = entitled
          ? 'Your Microsoft subscription is restored.'
          : 'No active Ripot subscription was found for this Microsoft Store account.';
    } catch (_) {
      message =
          'Could not restore purchases. Check that Microsoft Store and Ripot are signed in to the accounts used for your purchase, then retry.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> purchase(MicrosoftProduct product) async {
    if (!canBuy || !products.any((p) => p.id == product.id)) return;
    final uid = currentUid()!;
    busy = true;
    message = null;
    var purchaseOpened = false;
    _notify();
    try {
      // Bind and verify the Store account BEFORE allowing a charge. Existing
      // purchases restore here instead of opening a second subscription.
      if (await _verify(uid)) {
        message = 'Your existing Microsoft subscription is active.';
        return;
      }
      final a = access();
      if (!a.hasCurrentVerification ||
          a.isPremiumLike ||
          a.isTrialActive ||
          (a.plan == RipotPlan.premium &&
              (a.premiumExpiresAt == null ||
                  DateTime.now().isBefore(a.premiumExpiresAt!)))) {
        message =
            'Refresh your Premium access before purchasing. An active plan or trial does not need another subscription.';
        return;
      }
      _check(uid);
      purchaseOpened = true;
      final outcome = await store.purchase(product.id);
      _check(uid);
      if (outcome == 'cancelled') {
        message = 'Purchase cancelled.';
        return;
      }
      if (outcome != 'purchased' && outcome != 'owned')
        throw StateError('purchase-failed');
      final entitled = await _verify(uid);
      message = entitled
          ? 'Premium is active. Thank you for subscribing.'
          : 'Your purchase is still being confirmed. Use Restore purchases shortly; do not buy again.';
    } catch (_) {
      message = purchaseOpened
          ? 'We could not confirm the purchase. Use Restore purchases before trying to buy again.'
          : 'We could not verify your account. No purchase was started. Check your connection or restore using your original Ripot account.';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
