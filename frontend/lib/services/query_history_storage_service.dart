import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'plan_access_service.dart';

class QueryHistoryItem {
  QueryHistoryItem({
    required this.id,
    required this.provider,
    required this.connectionName,
    required this.sql,
    required this.executedAt,
  });

  final String id;
  final String provider;
  final String connectionName;
  final String sql;
  final DateTime executedAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'provider': provider,
      'connectionName': connectionName,
      'sql': sql,
      'executedAt': executedAt.toIso8601String(),
    };
  }

  factory QueryHistoryItem.fromMap(Map<String, dynamic> map) {
    return QueryHistoryItem(
      id: map['id'] ?? '',
      provider: map['provider'] ?? '',
      connectionName: map['connectionName'] ?? '',
      sql: map['sql'] ?? '',
      executedAt: DateTime.tryParse(map['executedAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class QueryHistoryStorageService {
  static const _storageKey = 'query_history';

  Future<void> saveQuery({
    required String provider,
    required String connectionName,
    required String sql,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final items = prefs.getStringList(_storageKey) ?? [];

    final historyItem = QueryHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      provider: provider,
      connectionName: connectionName,
      sql: sql,
      executedAt: DateTime.now(),
    );

    items.insert(0, jsonEncode(historyItem.toMap()));

    final historyLimit = PlanAccessService.instance.isPro
        ? 200
        : PlanAccessService.freeHistoryLimit;
    if (items.length > historyLimit) {
      items.removeRange(historyLimit, items.length);
    }

    await prefs.setStringList(_storageKey, items);
  }

  Future<List<QueryHistoryItem>> getQueries({
    String? provider,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final items = prefs.getStringList(_storageKey) ?? [];

    final result = items.map((e) {
      return QueryHistoryItem.fromMap(
        jsonDecode(e),
      );
    }).toList();

    final filtered = provider == null || provider.trim().isEmpty
        ? result
        : result
            .where((x) => x.provider.toLowerCase() == provider.toLowerCase())
            .toList();

    if (PlanAccessService.instance.isPro ||
        filtered.length <= PlanAccessService.freeHistoryLimit) {
      return filtered;
    }
    return filtered.take(PlanAccessService.freeHistoryLimit).toList();
  }

  Future<void> deleteQuery(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_storageKey) ?? [];

    final filtered = items.where((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        return map['id']?.toString() != id;
      } catch (_) {
        return true;
      }
    }).toList();

    await prefs.setStringList(_storageKey, filtered);
  }

  Future<void> deleteQueriesForConnection({
    required String provider,
    required String connectionName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_storageKey) ?? [];
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedConnectionName = connectionName.trim().toLowerCase();

    final filtered = items.where((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final itemProvider =
            map['provider']?.toString().trim().toLowerCase() ?? '';
        final itemConnectionName =
            map['connectionName']?.toString().trim().toLowerCase() ?? '';
        return itemProvider != normalizedProvider ||
            itemConnectionName != normalizedConnectionName;
      } catch (_) {
        return true;
      }
    }).toList();

    await prefs.setStringList(_storageKey, filtered);
  }

  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
