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
  static const String _apiBaseUrl = 'https://dbpilot-5g16.onrender.com';
  static const String proMonthlyProductId = 'dbpilot_pro_monthly';

  SubscriptionService({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;

  Stream<List<PurchaseDetails>> get purchaseStream =>
      _inAppPurchase.purchaseStream;

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
}
