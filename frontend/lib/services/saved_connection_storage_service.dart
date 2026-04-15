import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_request.dart';
import '../models/database_provider.dart';

class SavedConnectionStorageService {
  static const String _storageKey = 'saved_connections';
  static const String _activeConnectionIdKey = 'active_connection_id';
  static const String _passwordKeyPrefix = 'connection_password_';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

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

    await _savePassword(connectionId, request.password);
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

  Future<Map<String, dynamic>?> getConnectionById(String id) async {
    final connections = await getSavedConnections();

    try {
      final item = Map<String, dynamic>.from(
        connections.firstWhere((c) => c['id']?.toString() == id),
      );

      item['password'] = await getPasswordByConnectionId(id);
      return item;
    } catch (_) {
      return null;
    }
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
    await _deletePassword(id);

    final activeId = prefs.getString(_activeConnectionIdKey);
    if (activeId == id) {
      await prefs.remove(_activeConnectionIdKey);
    }
  }

  Future<void> clearAllConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final connections = await getSavedConnections();

    for (final connection in connections) {
      final id = ensureConnectionId(connection);
      await _deletePassword(id);
    }

    await prefs.remove(_storageKey);
    await prefs.remove(_activeConnectionIdKey);
  }

  Future<void> setActiveConnectionId(String connectionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeConnectionIdKey, connectionId);
  }

  Future<String?> getActiveConnectionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeConnectionIdKey);
  }

  Future<void> clearActiveConnectionId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeConnectionIdKey);
  }

  Future<Map<String, dynamic>?> getActiveConnection() async {
    final activeId = await getActiveConnectionId();
    if (activeId == null || activeId.isEmpty) return null;

    return getConnectionById(activeId);
  }

  Future<String?> getPasswordByConnectionId(String connectionId) async {
    return _secureStorage.read(key: _passwordStorageKey(connectionId));
  }

  Future<void> updatePasswordByConnectionId(
    String connectionId,
    String password,
  ) async {
    await _savePassword(connectionId, password);
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

  String _passwordStorageKey(String connectionId) {
    return '$_passwordKeyPrefix$connectionId';
  }

  Future<void> _savePassword(String connectionId, String password) async {
    await _secureStorage.write(
      key: _passwordStorageKey(connectionId),
      value: password,
    );
  }

  Future<void> _deletePassword(String connectionId) async {
    await _secureStorage.delete(
      key: _passwordStorageKey(connectionId),
    );
  }
}