import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'auth_service.dart';

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
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
  static const String proMonthlyProductId = 'dbpilot_pro_monthly';

  SubscriptionService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream => _inAppPurchase.purchaseStream;

  Future<bool> isStoreAvailable() => _inAppPurchase.isAvailable();

  Future<SubscriptionProduct?> loadProProduct() async {
    final available = await isStoreAvailable();
    if (!available) return null;

    final response = await _inAppPurchase.queryProductDetails(
      const {proMonthlyProductId},
    );

    if (response.productDetails.isEmpty) return null;
    final product = response.productDetails.first;
    return SubscriptionProduct(
      id: product.id,
      title: product.title,
      description: product.description,
      price: product.price,
    );
  }

  Future<void> buyPro(SubscriptionProduct product) async {
    final response = await _inAppPurchase.queryProductDetails({product.id});
    if (response.productDetails.isEmpty) {
      throw Exception('Subscription product not found.');
    }

    final purchaseParam = PurchaseParam(productDetails: response.productDetails.first);
    await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() => _inAppPurchase.restorePurchases();

  Future<SubscriptionPurchaseResult?> handlePurchaseUpdate({
    required String uid,
    required PurchaseDetails purchase,
  }) async {
    if (purchase.productID != proMonthlyProductId) return null;

    if (purchase.status == PurchaseStatus.error) {
      return SubscriptionPurchaseResult(
        plan: SubscriptionPlan.free,
        message: purchase.error?.message ?? 'Purchase failed.',
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
    // TODO: Send uid + productId + purchaseToken to the DBPilot backend.
    // The backend must verify the token with Google Play Developer API and
    // return the entitlement. Until that endpoint exists, keep the user Free.
    if (uid.trim().isEmpty || productId.trim().isEmpty || purchaseToken.trim().isEmpty) {
      return SubscriptionPlan.free;
    }
    return SubscriptionPlan.free;
  }
}
