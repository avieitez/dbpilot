import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';

import 'auth_service.dart';

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.period,
  });

  final String id;
  final String title;
  final String description;
  final String price;
  final SubscriptionProductPeriod period;
}

enum SubscriptionProductPeriod {
  monthly,
  yearly,
}

extension SubscriptionProductPeriodLabel on SubscriptionProductPeriod {
  String get label {
    switch (this) {
      case SubscriptionProductPeriod.monthly:
        return 'Monthly';
      case SubscriptionProductPeriod.yearly:
        return 'Yearly';
    }
  }

  String get suffix {
    switch (this) {
      case SubscriptionProductPeriod.monthly:
        return 'month';
      case SubscriptionProductPeriod.yearly:
        return 'year';
    }
  }
}

class SubscriptionPurchaseResult {
  const SubscriptionPurchaseResult({
    required this.plan,
    required this.message,
    this.purchaseToken,
  });

  final SubscriptionPlan plan;
  final String message;
  final String? purchaseToken;
}

class SubscriptionService {
  static const String _apiBaseUrl = 'https://dbpilot-5g16.onrender.com';
  static const String proMonthlyProductId = 'dbpilot_pro_monthly';
  static const String proYearlyProductId = 'dbpilot_pro_yearly';
  static const Set<String> proProductIds = {
    proMonthlyProductId,
    proYearlyProductId,
  };

  SubscriptionService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

  Future<bool> isStoreAvailable() => _inAppPurchase.isAvailable();

  Future<List<SubscriptionProduct>> loadProProducts() async {
    final available = await isStoreAvailable();
    if (!available) return const [];

    final response = await _inAppPurchase.queryProductDetails(
      proProductIds,
    );

    if (response.productDetails.isEmpty) return const [];
    final products = response.productDetails
        .where((product) => proProductIds.contains(product.id))
        .map(
          (product) => SubscriptionProduct(
            id: product.id,
            title: product.title,
            description: product.description,
            price: product.price,
            period: _periodForProduct(product.id),
          ),
        )
        .toList()
      ..sort((a, b) => a.period.index.compareTo(b.period.index));
    return products;
  }

  Future<SubscriptionProduct?> loadProProduct() async {
    final products = await loadProProducts();
    if (products.isEmpty) return null;
    return products.first;
  }

  Future<void> buyPro(SubscriptionProduct product,
      {required String uid}) async {
    final response = await _inAppPurchase.queryProductDetails({product.id});
    if (response.productDetails.isEmpty) {
      throw Exception('Subscription product not found.');
    }

    final purchaseParam = PurchaseParam(
      productDetails: response.productDetails.first,
      applicationUserName: uid,
    );
    final started = await _inAppPurchase.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
    if (!started) {
      throw Exception('Purchase flow could not be started.');
    }
  }

  Future<void> restorePurchases() => _inAppPurchase.restorePurchases();

  Future<SubscriptionPurchaseResult?> restoreAndVerifyPurchases({
    required String uid,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (uid.trim().isEmpty) return null;

    final available = await isStoreAvailable();
    if (!available) return null;

    SubscriptionPurchaseResult? lastResult;
    final completer = Completer<SubscriptionPurchaseResult?>();
    late final StreamSubscription<List<PurchaseDetails>> subscription;

    subscription = purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (!proProductIds.contains(purchase.productID)) continue;

          final result = await handlePurchaseUpdate(
            uid: uid,
            purchase: purchase,
          );
          if (result == null) continue;

          lastResult = result;
          if (result.plan == SubscriptionPlan.pro && !completer.isCompleted) {
            completer.complete(result);
            return;
          }
        }
      },
      onError: (_) {
        if (!completer.isCompleted) completer.complete(lastResult);
      },
    );

    try {
      await restorePurchases();
      return await completer.future.timeout(
        timeout,
        onTimeout: () => lastResult,
      );
    } finally {
      await subscription.cancel();
    }
  }

  Future<SubscriptionPurchaseResult?> handlePurchaseUpdate({
    required String uid,
    required PurchaseDetails purchase,
  }) async {
    if (!proProductIds.contains(purchase.productID)) return null;

    if (purchase.status == PurchaseStatus.error) {
      return SubscriptionPurchaseResult(
        plan: SubscriptionPlan.free,
        message: purchase.error?.message ?? 'Purchase failed.',
      );
    }

    if (purchase.status == PurchaseStatus.canceled) {
      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
      return const SubscriptionPurchaseResult(
        plan: SubscriptionPlan.free,
        message: 'Purchase cancelled.',
      );
    }

    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return null;
    }

    final verification = purchase.verificationData;
    final purchaseToken = verification.serverVerificationData;

    final plan = await verifyPlayStoreSubscription(
      uid: uid,
      productId: purchase.productID,
      purchaseToken: purchaseToken,
    );

    if (purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }

    return SubscriptionPurchaseResult(
      plan: plan,
      purchaseToken: purchaseToken,
      message: plan == SubscriptionPlan.pro
          ? 'Pro subscription active.'
          : 'Purchase received. Backend verification is pending.',
    );
  }

  Future<SubscriptionPlan> verifyPlayStoreSubscription({
    required String uid,
    required String productId,
    required String purchaseToken,
  }) async {
    if (uid.trim().isEmpty ||
        productId.trim().isEmpty ||
        purchaseToken.trim().isEmpty) {
      return SubscriptionPlan.free;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) return SubscriptionPlan.free;

    try {
      final idToken = await user.getIdToken(true);
      if (idToken == null || idToken.isEmpty) return SubscriptionPlan.free;
      final response = await http
          .post(
            Uri.parse(
              '$_apiBaseUrl/api/v1/subscriptions/google-play/verify',
            ),
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'productId': productId,
              'purchaseToken': purchaseToken,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return SubscriptionPlan.free;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return payload['plan']?.toString().toLowerCase() == 'pro'
          ? SubscriptionPlan.pro
          : SubscriptionPlan.free;
    } catch (_) {
      return SubscriptionPlan.free;
    }
  }

  static SubscriptionProductPeriod _periodForProduct(String productId) {
    return productId == proYearlyProductId
        ? SubscriptionProductPeriod.yearly
        : SubscriptionProductPeriod.monthly;
  }

}
