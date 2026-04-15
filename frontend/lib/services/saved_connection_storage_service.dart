import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_request.dart';
import '../models/database_provider.dart';

class SavedConnectionStorageService {
  static const String _storageKey = 'saved_connections';

  Future<void> saveConnection(
    ConnectionRequest request, {
    String? existingId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_storageKey) ?? <String>[];

    final connectionId = (existingId != null && existingId.trim().isNotEmpty)
        ? existingId
        : _buildConnectionId(request);

    final newItem = jsonEncode({
      'id': connectionId,
      'name': request.name,
      'provider': request.provider.apiValue,
      'host': request.host,
      'port': request.port,
      'username': request.username,
      'database': request.database,
      'serviceName': request.serviceName,
      'sid': request.sid,
      'encrypt': request.encrypt,
      'trustServerCertificate': request.trustServerCertificate,
    });

    final filtered = items.where((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        return map['id'] != connectionId;
      } catch (_) {
        return true;
      }
    }).toList();

    filtered.add(newItem);
    await prefs.setStringList(_storageKey, filtered);
  }

  Future<List<Map<String, dynamic>>> getSavedConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_storageKey) ?? <String>[];

    bool changed = false;
    final migratedItems = <String>[];
    final result = <Map<String, dynamic>>[];

    for (final item in items) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        final normalized = Map<String, dynamic>.from(map);

        if ((normalized['id']?.toString().isEmpty ?? true)) {
          final provider = providerFromName(
            normalized['provider']?.toString() ?? 'postgresql',
          );

          normalized['id'] = _buildIdFromRaw(
            name: normalized['name']?.toString() ?? '',
            providerApiValue: provider.apiValue,
            host: normalized['host']?.toString() ?? '',
            port: normalized['port']?.toString() ?? '',
          );

          if ((normalized['provider']?.toString().isEmpty ?? true) ||
              normalized['provider'].toString() != provider.apiValue) {
            normalized['provider'] = provider.apiValue;
          }

          changed = true;
        }

        migratedItems.add(jsonEncode(normalized));
        result.add(normalized);
      } catch (_) {
        // Ignore malformed records instead of crashing the app.
      }
    }

    if (changed) {
      await prefs.setStringList(_storageKey, migratedItems);
    }

    return result;
  }

  Future<void> deleteConnectionById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_storageKey) ?? <String>[];

    final filtered = items.where((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        return map['id'] != id;
      } catch (_) {
        return true;
      }
    }).toList();

    await prefs.setStringList(_storageKey, filtered);
  }

  Future<void> clearAllConnections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  DatabaseProvider providerFromName(String name) {
    return DatabaseProviderX.fromString(name);
  }

  String ensureConnectionId(Map<String, dynamic> connection) {
    final existing = connection['id']?.toString();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final provider = providerFromName(
      connection['provider']?.toString() ?? 'postgresql',
    );

    return _buildIdFromRaw(
      name: connection['name']?.toString() ?? '',
      providerApiValue: provider.apiValue,
      host: connection['host']?.toString() ?? '',
      port: connection['port']?.toString() ?? '',
    );
  }

  String _buildConnectionId(ConnectionRequest request) {
    return _buildIdFromRaw(
      name: request.name,
      providerApiValue: request.provider.apiValue,
      host: request.host,
      port: request.port,
    );
  }

  String _buildIdFromRaw({
    required String name,
    required String providerApiValue,
    required String host,
    required String port,
  }) {
    return [
      providerApiValue.trim().toLowerCase(),
      host.trim().toLowerCase(),
      port.trim(),
      name.trim().toLowerCase(),
    ].join('|');
  }
}
