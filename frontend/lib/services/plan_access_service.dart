import 'auth_service.dart';

enum ProFeature {
  unlimitedConnections,
  voiceSql,
  advancedSql,
  fullHistory,
  exportFormats,
}

extension ProFeatureX on ProFeature {
  String get title {
    switch (this) {
      case ProFeature.unlimitedConnections:
        return 'Unlimited connections';
      case ProFeature.voiceSql:
        return 'Voice SQL';
      case ProFeature.advancedSql:
        return 'Advanced SQL';
      case ProFeature.fullHistory:
        return 'Full query history';
      case ProFeature.exportFormats:
        return 'All export formats';
    }
  }
}

class PlanAccessService {
  PlanAccessService._();

  static final PlanAccessService instance = PlanAccessService._();

  static const int freeConnectionLimit = 3;
  static const int freeHistoryLimit = 10;

  SubscriptionPlan _plan = SubscriptionPlan.free;
  String? _uid;

  SubscriptionPlan get plan => _plan;
  String? get uid => _uid;
  bool get isPro => _plan == SubscriptionPlan.pro;

  void updateSession(AppUserSession? session) {
    _uid = session?.uid;
    _plan = session?.plan ?? SubscriptionPlan.free;
  }

  bool canUse(ProFeature feature) => isPro;

  bool canCreateConnection({required int connectionCount}) {
    return isPro || connectionCount < freeConnectionLimit;
  }
}
