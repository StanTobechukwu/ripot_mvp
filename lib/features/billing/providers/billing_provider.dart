import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../../access/providers/access_provider.dart';

class BillingProvider extends ChangeNotifier {
  static const premiumProductId = 'ripot_premium';
  static const monthlyBasePlanId = 'monthly';
  static const annualBasePlanId = 'annual';
  static const foundingOfferId = 'founding-100-annual-25';
  static const foundingOfferTag = 'founding-100';

  AccessProvider _accessProvider;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  bool _loading = false;
  bool _available = false;
  bool _purchasePending = false;
  bool _founderDiscountEligible = false;
  String? _message;
  String? _error;
  ProductDetails? _monthly;
  ProductDetails? _annual;
  ProductDetails? _founderAnnual;

  BillingProvider({required AccessProvider accessProvider})
    : _accessProvider = accessProvider {
    _purchaseSubscription = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error) {
        _purchasePending = false;
        _error = 'Google Play purchase update failed.';
        notifyListeners();
      },
    );
    Future<void>.microtask(load);
  }

  void updateAccessProvider(AccessProvider accessProvider) =>
      _accessProvider = accessProvider;
  bool get loading => _loading;
  bool get available => _available;
  bool get purchasePending => _purchasePending;
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
      FirebaseAuth.instance.currentUser != null;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
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
      notifyListeners();
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
    if (index == null || offers == null || index < 0 || index >= offers.length)
      return null;
    return offers[index];
  }

  Future<bool> purchaseMonthly() async {
    if (_monthly == null) {
      _error = 'Monthly Premium is not available from Google Play.';
      notifyListeners();
      return false;
    }
    return _purchase(_monthly!);
  }

  Future<bool> purchaseAnnual() async {
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _error = 'Sign in to restore Premium purchases.';
      notifyListeners();
      return;
    }
    _purchasePending = true;
    _message = 'Checking Google Play purchases…';
    _error = null;
    notifyListeners();
    try {
      await _iap.restorePurchases(applicationUserName: user.uid);
      await _refreshServerEntitlement();
    } catch (_) {
      _purchasePending = false;
      _error = 'Unable to restore Google Play purchases right now.';
      notifyListeners();
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID != premiumProductId) continue;
      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
        _message = 'Google Play is processing your purchase…';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _purchasePending = false;
        _error = purchase.error?.message ?? 'The Google Play purchase failed.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _purchasePending = false;
        _message = 'Purchase cancelled.';
        notifyListeners();
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final verified = await _verifyWithServer(purchase);
        if (verified) {
          if (purchase.pendingCompletePurchase)
            await _iap.completePurchase(purchase);
          await _accessProvider.refresh();
          await _refreshEligibility();
          _purchasePending = false;
          _message = 'Ripot Premium is active.';
          _error = null;
          notifyListeners();
        } else {
          _purchasePending = false;
          _error = 'Google Play purchase verification was not completed.';
          notifyListeners();
        }
      }
    }
  }

  Future<bool> _verifyWithServer(PurchaseDetails purchase) async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    final token = purchase.verificationData.serverVerificationData.trim();
    if (token.isEmpty) return false;
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('verifyGooglePlaySubscription')
          .call(<String, dynamic>{
            'purchaseToken': token,
            'productId': purchase.productID,
            'purchaseId': purchase.purchaseID,
          });
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['entitled'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _refreshServerEntitlement() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refreshPlayEntitlement')
          .call(<String, dynamic>{});
      await _accessProvider.refresh();
      await _refreshEligibility();
      _purchasePending = false;
      _message = _accessProvider.safeState.isPremiumLike
          ? 'Ripot Premium is active.'
          : 'No active Google Play Premium subscription was found.';
      notifyListeners();
    } catch (_) {
      _purchasePending = false;
      _error = 'Unable to refresh Premium status right now.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }
}
