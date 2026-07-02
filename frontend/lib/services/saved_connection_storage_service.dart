import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_request.dart';
import '../models/database_provider.dart';
import 'plan_access_service.dart';

class SavedConnectionStorageService {
  static const String _storageKey = 'saved_connections';
  static const String _activeConnectionIdKey = 'active_connection_id';
  static const String _passwordKeyPrefix = 'connection_password_';
  static const String _migrationOwnerKey =
      'saved_connections.user_scope_migration_owner';

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
    final uid = _requireUid();
    await _migrateLegacyDataIfNeeded(prefs, uid);
    final items = prefs.getStringList(_userStorageKey(uid)) ?? <String>[];

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
    await prefs.setStringList(_userStorageKey(uid), filtered);

    await _savePassword(uid, connectionId, request.password);
  }

  Future<List<Map<String, dynamic>>> getSavedConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _requireUid();
    await _migrateLegacyDataIfNeeded(prefs, uid);
    final storageKey = _userStorageKey(uid);
    final items = prefs.getStringList(storageKey) ?? <String>[];

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
      await prefs.setStringList(storageKey, migratedItems);
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
    final uid = _requireUid();
    await _migrateLegacyDataIfNeeded(prefs, uid);
    final storageKey = _userStorageKey(uid);
    final activeConnectionKey = _userActiveConnectionIdKey(uid);
    final items = prefs.getStringList(storageKey) ?? <String>[];

    final filtered = items.where((item) {
      try {
        final map = jsonDecode(item) as Map<String, dynamic>;
        return map['id'] != id;
      } catch (_) {
        return true;
      }
    }).toList();

    await prefs.setStringList(storageKey, filtered);
    await _deletePassword(uid, id);

    final activeId = prefs.getString(activeConnectionKey);
    if (activeId == id) {
      await prefs.remove(activeConnectionKey);
    }
  }

  Future<void> clearAllConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _requireUid();
    final connections = await getSavedConnections();

    for (final connection in connections) {
      final id = ensureConnectionId(connection);
      await _deletePassword(uid, id);
    }

    await prefs.remove(_userStorageKey(uid));
    await prefs.remove(_userActiveConnectionIdKey(uid));
  }

  Future<void> setActiveConnectionId(String connectionId) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _requireUid();
    await _migrateLegacyDataIfNeeded(prefs, uid);
    await prefs.setString(_userActiveConnectionIdKey(uid), connectionId);
  }

  Future<String?> getActiveConnectionId() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _requireUid();
    await _migrateLegacyDataIfNeeded(prefs, uid);
    return prefs.getString(_userActiveConnectionIdKey(uid));
  }

  Future<void> clearActiveConnectionId() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _requireUid();
    await prefs.remove(_userActiveConnectionIdKey(uid));
  }

  Future<Map<String, dynamic>?> getActiveConnection() async {
    final activeId = await getActiveConnectionId();
    if (activeId == null || activeId.isEmpty) return null;

    return getConnectionById(activeId);
  }

  Future<String?> getPasswordByConnectionId(String connectionId) async {
    final uid = _requireUid();
    return _secureStorage.read(key: _passwordStorageKey(uid, connectionId));
  }

  Future<void> updatePasswordByConnectionId(
    String connectionId,
    String password,
  ) async {
    await _savePassword(_requireUid(), connectionId, password);
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

  String _passwordStorageKey(String uid, String connectionId) {
    return '$_passwordKeyPrefix${uid}_$connectionId';
  }

  Future<void> _savePassword(
    String uid,
    String connectionId,
    String password,
  ) async {
    await _secureStorage.write(
      key: _passwordStorageKey(uid, connectionId),
      value: password,
    );
  }

  Future<void> _deletePassword(String uid, String connectionId) async {
    await _secureStorage.delete(
      key: _passwordStorageKey(uid, connectionId),
    );
  }

  String _requireUid() {
    final uid = PlanAccessService.instance.uid?.trim();
    if (uid == null || uid.isEmpty) {
      throw StateError('A signed-in user is required to access connections.');
    }
    return uid;
  }

  String _userStorageKey(String uid) => '$_storageKey.$uid';

  String _userActiveConnectionIdKey(String uid) =>
      '$_activeConnectionIdKey.$uid';

  Future<void> _migrateLegacyDataIfNeeded(
    SharedPreferences prefs,
    String uid,
  ) async {
    final migrationOwner = prefs.getString(_migrationOwnerKey);
    if (migrationOwner != null) return;

    final legacyItems = prefs.getStringList(_storageKey) ?? <String>[];
    if (legacyItems.isNotEmpty && !(prefs.containsKey(_userStorageKey(uid)))) {
      await prefs.setStringList(_userStorageKey(uid), legacyItems);

      for (final item in legacyItems) {
        try {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final connectionId = ensureConnectionId(map);
          final legacyPassword = await _secureStorage.read(
            key: '$_passwordKeyPrefix$connectionId',
          );
          if (legacyPassword != null) {
            await _savePassword(uid, connectionId, legacyPassword);
            await _secureStorage.delete(
              key: '$_passwordKeyPrefix$connectionId',
            );
          }
        } catch (_) {
          // Keep migrating valid entries when a legacy item is malformed.
        }
      }
    }

    final legacyActiveId = prefs.getString(_activeConnectionIdKey);
    if (legacyActiveId != null && legacyActiveId.isNotEmpty) {
      await prefs.setString(_userActiveConnectionIdKey(uid), legacyActiveId);
    }
    await prefs.remove(_storageKey);
    await prefs.remove(_activeConnectionIdKey);
    await prefs.setString(_migrationOwnerKey, uid);
  }
}
