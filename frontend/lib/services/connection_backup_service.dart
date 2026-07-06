import 'dart:convert';

import '../models/connection_request.dart';
import '../models/database_provider.dart';
import 'saved_connection_storage_service.dart';

class ConnectionImportResult {
  const ConnectionImportResult({
    required this.imported,
    required this.renamed,
    required this.skipped,
  });

  final int imported;
  final int renamed;
  final int skipped;
}

class ConnectionBackupService {
  ConnectionBackupService({SavedConnectionStorageService? storageService})
      : _storageService = storageService ?? SavedConnectionStorageService();

  final SavedConnectionStorageService _storageService;

  Future<String> exportJson() async {
    final connections = await _storageService.getSavedConnections();
    final payload = {
      'format': 'dbpilot-connections',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'connections': connections.map(_exportableConnection).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<ConnectionImportResult> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'dbpilot-connections' ||
        decoded['version'] != 1 ||
        decoded['connections'] is! List) {
      throw const FormatException('Invalid DBPilot connections backup.');
    }

    final existing = await _storageService.getSavedConnections();
    final usedNames = existing
        .map((item) => item['name']?.toString().trim().toLowerCase() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();

    var imported = 0;
    var renamed = 0;
    var skipped = 0;

    for (final rawItem in decoded['connections'] as List) {
      try {
        if (rawItem is! Map) throw const FormatException();
        final item = Map<String, dynamic>.from(rawItem);
        final originalName = _requiredText(item, 'name');
        final importedName = _uniqueImportedName(originalName, usedNames);
        if (importedName != originalName) renamed++;

        final providerValue = _requiredText(item, 'provider').toLowerCase();
        final provider = DatabaseProvider.values.firstWhere(
          (candidate) => candidate.apiValue == providerValue,
        );
        final request = ConnectionRequest(
          name: importedName,
          provider: provider,
          host: _requiredText(item, 'host'),
          port: _requiredText(item, 'port'),
          username: item['username']?.toString() ?? '',
          password: '',
          database: item['database']?.toString() ?? '',
          serviceName: _optionalText(item['serviceName']),
          sid: _optionalText(item['sid']),
          encrypt: item['encrypt'] == true,
          trustServerCertificate: item['trustServerCertificate'] != false,
        );

        await _storageService.saveConnection(request);
        usedNames.add(importedName.toLowerCase());
        imported++;
      } catch (_) {
        skipped++;
      }
    }

    return ConnectionImportResult(
      imported: imported,
      renamed: renamed,
      skipped: skipped,
    );
  }

  Map<String, dynamic> _exportableConnection(Map<String, dynamic> source) {
    return {
      'name': source['name']?.toString() ?? '',
      'provider': source['provider']?.toString() ?? '',
      'host': source['host']?.toString() ?? '',
      'port': source['port']?.toString() ?? '',
      'username': source['username']?.toString() ?? '',
      'database': source['database']?.toString() ?? '',
      'serviceName': _optionalText(source['serviceName']),
      'sid': _optionalText(source['sid']),
      'encrypt': source['encrypt'] == true,
      'trustServerCertificate': source['trustServerCertificate'] != false,
    };
  }

  String _uniqueImportedName(String original, Set<String> usedNames) {
    if (!usedNames.contains(original.toLowerCase())) return original;

    var candidate = '$original (Imported)';
    var suffix = 2;
    while (usedNames.contains(candidate.toLowerCase())) {
      candidate = '$original (Imported $suffix)';
      suffix++;
    }
    return candidate;
  }

  String _requiredText(Map<String, dynamic> item, String key) {
    final value = item[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException('Missing $key.');
    return value;
  }

  String? _optionalText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
