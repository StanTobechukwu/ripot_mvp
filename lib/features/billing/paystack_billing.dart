import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/firebase/account_functions.dart';

typedef PaymentCall = Future<dynamic> Function(
  String name,
  Map<String, dynamic> data,
);

class PaystackPlan {
  const PaystackPlan({
    required this.id,
    required this.amount,
    required this.currency,
    required this.interval,
    required this.markets,
  });
  final String id;
  final int amount;
  final String currency;
  final String interval;
  final List<String> markets;
  factory PaystackPlan.fromJson(Map<String, dynamic> data) => PaystackPlan(
    id: data['id'] as String,
    amount: data['amount'] as int,
    currency: data['currency'] as String,
    interval: data['interval'] as String,
    markets: List<String>.from(data['markets'] as List),
  );
  String get period => interval == 'monthly' ? 'month' : 'year';
  String get price {
    final parts = (amount / 100).toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${currency == 'NGN' ? '₦' : 'US\$'}$whole.${parts[1]}';
  }
}

class PaystackBilling extends ChangeNotifier {
  PaystackBilling({
    required this.currentUid,
    required this.refreshAccess,
    PaymentCall? call,
    Future<bool> Function(Uri)? launch,
  }) : _call =
           call ?? ((name, data) => AccountFunctions.call(name, data: data)),
       _launch =
           launch ??
           ((uri) => launchUrl(
             uri,
             mode: LaunchMode.externalApplication,
             webOnlyWindowName: '_self',
           ));
  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.windows;
  final String? Function() currentUid;
  final Future<void> Function() refreshAccess;
  final PaymentCall _call;
  final Future<bool> Function(Uri) _launch;
  bool busy = false,
      enabled = false,
      internationalEnabled = false,
      canManage = false;
  String mode = 'live';
  String? message,
      error,
      locked,
      provider,
      subscriptionStatus,
      pendingPlanId,
      pendingMarket;
  List<({String code, String label})> countries = [];
  List<PaystackPlan> plans = [];
  List<PaystackPlan> plansForCountry(String? country) {
    if (country == null || (country != 'NG' && !internationalEnabled))
      return [];
    final exact = plans.where((p) => p.markets.contains(country)).toList();
    if (exact.isNotEmpty || country == 'NG') return exact;
    return plans.where((p) => p.markets.contains('international')).toList();
  }

  int _generation = 0;
  bool _disposed = false;
  String? _owner;
  void reset() {
    _generation++;
    _owner = currentUid();
    plans = [];
    countries = [];
    pendingMarket = null;
    mode = 'live';
    enabled = false;
    canManage = false;
    busy = false;
    message = null;
    error = null;
    locked = null;
    provider = null;
    pendingPlanId = null;
    internationalEnabled = false;
    subscriptionStatus = null;
  }

  bool _valid(String uid, int generation) =>
      !_disposed && currentUid() == uid && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load({bool refreshPayment = false}) async {
    if (_owner != currentUid()) reset();
    final uid = currentUid();
    if (uid == null || busy || _disposed) return;
    final generation = _generation;
    busy = true;
    error = null;
    _notify();
    try {
      if (refreshPayment) {
        final result = await _call('refreshPaystackEntitlement', {});
        if (!_valid(uid, generation)) return;
        // A server result or browser callback never grants local Premium.
        // Only the account's authoritative access document may unlock features.
        await refreshAccess();
        if (!_valid(uid, generation)) return;
        message =
            result is Map &&
                result['mode'] == 'test' &&
                result['entitled'] == true
            ? 'Test payment verified. No live Premium access was changed.'
            : 'Payment status checked. Your account shows the confirmed access.';
      }
      final result = Map<String, dynamic>.from(
        await _call('getPaystackPlans', {}) as Map,
      );
      if (!_valid(uid, generation)) return;
      enabled = result['enabled'] == true;
      mode = result['mode']?.toString() ?? 'live';
      internationalEnabled = result['internationalEnabled'] == true;
      canManage = result['canManage'] == true;
      locked = result['locked']?.toString();
      provider = result['provider']?.toString();
      subscriptionStatus = result['subscriptionStatus']?.toString();
      pendingPlanId = result['pendingPlanId']?.toString();
      pendingMarket = result['pendingMarket']?.toString();
      countries = (result['billingCountries'] as List? ?? [])
          .map((c) => (code: c['code'] as String, label: c['label'] as String))
          .toList();
      // Keep older pending checkouts manageable across a country-pricing update.
      if (pendingMarket == 'international') {
        countries.add((
          code: 'international',
          label: 'Outside Nigeria (existing checkout)',
        ));
      }
      plans = (result['plans'] as List? ?? [])
          .map(
            (p) => PaystackPlan.fromJson(Map<String, dynamic>.from(p as Map)),
          )
          .toList();
    } catch (_) {
      if (_valid(uid, generation))
        error = 'Unable to check payment options. Please try again.';
    } finally {
      if (_valid(uid, generation)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> checkout(PaystackPlan plan, String market) async {
    if (!enabled ||
        busy ||
        locked != null ||
        !plansForCountry(market).any((p) => p.id == plan.id))
      return;
    await _open('startPaystackCheckout', {
      'planId': plan.id,
      'market': market,
    }, checkout: true);
  }

  Future<void> manage() async {
    if (!canManage || busy) return;
    await _open('managePaystackSubscription', {}, checkout: false);
  }

  Future<void> _open(
    String function,
    Map<String, dynamic> data, {
    required bool checkout,
  }) async {
    final uid = currentUid();
    if (uid == null || uid != _owner) return;
    final generation = _generation;
    busy = true;
    message = null;
    error = null;
    _notify();
    try {
      final result = Map<String, dynamic>.from(
        await _call(function, data) as Map,
      );
      if (!_valid(uid, generation)) return;
      final uri = Uri.parse(
        result[checkout ? 'authorizationUrl' : 'url'] as String,
      );
      final hostAllowed = checkout
          ? uri.host == 'checkout.paystack.com'
          : uri.host == 'paystack.com' || uri.host.endsWith('.paystack.com');
      if (uri.scheme != 'https' ||
          !hostAllowed ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort && uri.port != 443)
        throw const FormatException();
      if (!await _launch(uri)) throw StateError('Could not open checkout');
      if (_valid(uid, generation))
        message = checkout
            ? 'Complete payment in your browser, then check payment status here.'
            : 'Manage your subscription in your browser, then refresh your status here.';
    } catch (_) {
      if (_valid(uid, generation)) error = 'Unable to open payment. Refresh your status, then try again. Contact support@ripot.app if it persists.';
    } finally {
      if (_valid(uid, generation)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
