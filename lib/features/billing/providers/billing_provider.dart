import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../access/domain/access_state.dart';
import '../../access/providers/access_provider.dart';

class BillingProvider extends ChangeNotifier {
  static const premiumProductId = 'ripot_premium';
  static const monthlyBasePlanId = 'monthly';
  static const annualBasePlanId = 'annual';
  static const foundingOfferId = 'founding-100-annual-25';
  static const foundingOfferTag = 'founding-100';

  AccessProvider _accessProvider;
  // InAppPurchase has no Windows implementation. Do not even resolve its
  // singleton or purchase stream on platforms without Google Play billing.
  static bool get supportsGooglePlay =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  late final InAppPurchase _iap = InAppPurchase.instance;
  bool _disposed = false;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _loading = false;
  bool _available = false;
  bool _purchasePending = false;
  bool _restoreInProgress = false;
  bool _restorePurchaseSeen = false;
  bool _founderDiscountEligible = false;
  String? _message;
  String? _error;
  ProductDetails? _monthly;
  ProductDetails? _annual;
  ProductDetails? _founderAnnual;

  BillingProvider({required AccessProvider accessProvider})
    : _accessProvider = accessProvider {
    if (supportsGooglePlay) {
      _purchaseSubscription = _iap.purchaseStream.listen(
        _onPurchaseUpdates,
        onError: (Object error) {
          _purchasePending = false;
          _restoreInProgress = false;
          _error = 'Google Play purchase update failed.';
          notifyListeners();
        },
      );
    }
    Future<void>.microtask(load);
  }

  void updateAccessProvider(AccessProvider accessProvider) =>
      _accessProvider = accessProvider;
  bool get loading => _loading;
  bool get available => _available;
  bool get purchasePending => _purchasePending;
  bool get restoring => _restoreInProgress;
  bool get founderDiscountEligible => _founderDiscountEligible;
  String? get message => _message;
  String? get error => _error;
  ProductDetails? get monthlyProduct => _monthly;
  ProductDetails? get annualProduct => _annual;
  ProductDetails? get founderAnnualProduct => _founderAnnual;
  String get monthlyPrice => _monthly?.price ?? '';
  String get annualPrice => _annual?.price ?? '';
  String get founderAnnualPrice => _founderAnnual?.price ?? '';
  bool get canPurchase =>
      _available &&
      !_loading &&
      !_purchasePending &&
      FirebaseAuth.instance.currentUser != null &&
      !_accessProvider.safeState.isTrialActive;
  bool get canRestore =>
      _available &&
      !_loading &&
      !_purchasePending &&
      FirebaseAuth.instance.currentUser != null;

  Future<void> load() async {
    if (_loading || _disposed) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (!supportsGooglePlay) {
        _available = false;
        return;
      }
      _available = await _iap.isAvailable();
      if (!_available) return;
      final response = await _iap.queryProductDetails({premiumProductId});
      if (response.error != null) _error = response.error!.message;
      if (response.notFoundIDs.contains(premiumProductId)) {
        _error =
            'Ripot Premium is not available from Google Play for this account.';
      }
      _monthly = null;
      _annual = null;
      _founderAnnual = null;
      for (final product in response.productDetails) {
        if (product is! GooglePlayProductDetails) continue;
        final offer = _offerFor(product);
        if (offer == null) continue;
        if (offer.basePlanId == monthlyBasePlanId && offer.offerId == null) {
          _monthly ??= product;
        } else if (offer.basePlanId == annualBasePlanId &&
            offer.offerId == null) {
          _annual ??= product;
        } else if (offer.basePlanId == annualBasePlanId &&
            (offer.offerId == foundingOfferId ||
                offer.offerTags.contains(foundingOfferTag))) {
          _founderAnnual ??= product;
        }
      }
      await _refreshEligibility();
    } catch (_) {
      _error = 'Unable to load Google Play Premium plans right now.';
    } finally {
      _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _refreshEligibility() async {
    if (FirebaseAuth.instance.currentUser == null) {
      _founderDiscountEligible = false;
      return;
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getBillingEligibility')
          .call(<String, dynamic>{});
      final data = Map<String, dynamic>.from(result.data as Map);
      _founderDiscountEligible = data['founderDiscountEligible'] == true;
    } catch (_) {
      _founderDiscountEligible = false;
    }
  }

  dynamic _offerFor(GooglePlayProductDetails product) {
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null ||
        offers == null ||
        index < 0 ||
        index >= offers.length) {
      return null;
    }
    return offers[index];
  }

  Future<bool> purchaseMonthly() async {
    if (!supportsGooglePlay) return false;
    if (_monthly == null) {
      _error = 'Monthly Premium is not available from Google Play.';
      notifyListeners();
      return false;
    }
    return _purchase(_monthly!);
  }

  Future<bool> purchaseAnnual() async {
    if (!supportsGooglePlay) return false;
    await _refreshEligibility();
    final product = _founderDiscountEligible && _founderAnnual != null
        ? _founderAnnual
        : _annual;
    if (product == null) {
      _error = 'Annual Premium is not available from Google Play.';
      notifyListeners();
      return false;
    }
    return _purchase(product);
  }

  Future<bool> _purchase(ProductDetails product) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _error = 'Sign in to your Ripot account before purchasing Premium.';
      notifyListeners();
      return false;
    }
    if (_accessProvider.safeState.isTrialActive) {
      _error =
          'Your free Premium trial is active. You can subscribe after it ends.';
      notifyListeners();
      return false;
    }
    if (!canPurchase) return false;
    _purchasePending = true;
    _message = null;
    _error = null;
    notifyListeners();
    try {
      final PurchaseParam param = product is GooglePlayProductDetails
          ? GooglePlayPurchaseParam(
              productDetails: product,
              applicationUserName: user.uid,
              offerToken: product.offerToken,
            )
          : PurchaseParam(
              productDetails: product,
              applicationUserName: user.uid,
            );
      final launched = await _iap.buyNonConsumable(purchaseParam: param);
      if (!launched) {
        _purchasePending = false;
        _error = 'Google Play could not start the purchase.';
        notifyListeners();
      }
      return launched;
    } catch (_) {
      _purchasePending = false;
      _error = 'Google Play could not start the purchase.';
      notifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (!supportsGooglePlay) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _error = 'Sign in to restore Premium purchases.';
      notifyListeners();
      return;
    }
    if (!canRestore) return;
    _purchasePending = true;
    _restoreInProgress = true;
    _restorePurchaseSeen = false;
    _message = 'Restoring purchases…';
    _error = null;
    notifyListeners();
    try {
      await _iap
          .restorePurchases(applicationUserName: user.uid)
          .timeout(const Duration(seconds: 20));

      // Restored purchases arrive on purchaseStream. Give that stream a brief
      // chance to take ownership of completion; if it reports nothing, ask the
      // server whether this account already has a verified Play subscription.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!_restoreInProgress || _restorePurchaseSeen) return;
      await _refreshServerEntitlement();
    } on TimeoutException {
      _purchasePending = false;
      _restoreInProgress = false;
      _error = 'Google Play took too long to restore purchases. Please retry.';
      notifyListeners();
    } catch (_) {
      _purchasePending = false;
      _restoreInProgress = false;
      _error = 'Unable to restore Google Play purchases right now.';
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != premiumProductId) continue;
      if (_restoreInProgress &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        _restorePurchaseSeen = true;
      }
      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
        _message = 'Google Play is processing your purchase…';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _purchasePending = false;
        _restoreInProgress = false;
        _error = purchase.error?.message ?? 'The Google Play purchase failed.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
        _restoreInProgress = false;
        _message = 'Purchase cancelled.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        try {
          final entitlement = await _verifyWithServer(
            purchase,
          ).timeout(const Duration(seconds: 30), onTimeout: () => null);
          if (entitlement != true) {
            if (purchase.status == PurchaseStatus.restored &&
                entitlement == false) {
              await _refreshServerEntitlement();
              continue;
            }
            _purchasePending = false;
            _restoreInProgress = false;
            _error = 'Google Play purchase verification was not completed.';
            notifyListeners();
            continue;
          }
          if (purchase.pendingCompletePurchase) {
            await _iap
                .completePurchase(purchase)
                .timeout(const Duration(seconds: 20));
          }
          await _refreshEligibility().timeout(const Duration(seconds: 20));
          _purchasePending = false;
          _restoreInProgress = false;
          _message = 'Ripot Premium is active.';
          _error = null;
          notifyListeners();
        } catch (_) {
          _purchasePending = false;
          _restoreInProgress = false;
          _error = 'Premium verification could not be completed. Please retry.';
          notifyListeners();
        }
      }
    }
  }

  /// Returns true/false for a completed server check, and null when the check
  /// itself could not be completed.
  Future<bool?> _verifyWithServer(PurchaseDetails purchase) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final token = purchase.verificationData.serverVerificationData.trim();
    if (token.isEmpty) return null;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyGooglePlaySubscription')
          .call(<String, dynamic>{
            'purchaseToken': token,
            'productId': purchase.productID,
            'purchaseId': purchase.purchaseID,
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      if (FirebaseAuth.instance.currentUser?.uid != uid) return null;
      final expires = DateTime.tryParse(data['expiresAtIso']?.toString() ?? '');
      if (data['entitled'] == true) {
        if (expires == null || !expires.isAfter(DateTime.now())) return null;
        _accessProvider.acceptVerifiedPremium(expires);
      }
      return data['entitled'] == true;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refreshServerEntitlement() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refreshPlayEntitlement')
          .call(<String, dynamic>{});
      await _accessProvider.refresh(refreshPlay: false);
      await _refreshEligibility();
      _purchasePending = false;
      _restoreInProgress = false;
      _error = null;
      _message = _accessProvider.safeState.plan == RipotPlan.premium
          ? 'Ripot Premium is active.'
          : _accessProvider.safeState.isTrialActive
          ? 'No active Google Play subscription was found. Your free trial is unchanged.'
          : 'No active Google Play Premium subscription was found.';
      notifyListeners();
    } catch (_) {
      _purchasePending = false;
      _restoreInProgress = false;
      _error = 'Unable to refresh Premium status right now.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
