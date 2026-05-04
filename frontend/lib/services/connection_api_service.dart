import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/connection_request.dart';

class ConnectionTestResult {
  final bool success;
  final String message;
  final int? durationMs;
  final String? provider;
  final String? mode;

  ConnectionTestResult({
    required this.success,
    required this.message,
    this.durationMs,
    this.provider,
    this.mode,
  });

  factory ConnectionTestResult.fromJson(Map<String, dynamic> json) {
    return ConnectionTestResult(
      success: json['success'] == true,
      message: (json['message'] ?? json['detail'] ?? 'No message').toString(),
      durationMs: json['durationMs'] ?? json['duration_ms'],
      provider: json['provider']?.toString(),
      mode: json['mode']?.toString(),
    );
  }
}

class DbExplorerObjectItem {
  final String name;
  final String subtitle;
  final String objectType;
  final String? schemaName;
  final String? defaultQuery;
  final bool isDemo;

  DbExplorerObjectItem({
    required this.name,
    required this.subtitle,
    required this.objectType,
    this.schemaName,
    this.defaultQuery,
    this.isDemo = false,
  });

  factory DbExplorerObjectItem.fromJson(Map<String, dynamic> json) {
    return DbExplorerObjectItem(
      name: (json['name'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      schemaName: json['schemaName']?.toString(),
      defaultQuery: json['defaultQuery']?.toString(),
      isDemo: json['isDemo'] == true,
    );
  }
}

class DbExplorerGroup {
  final String key;
  final String label;
  final List<DbExplorerObjectItem> items;

  DbExplorerGroup({
    required this.key,
    required this.label,
    required this.items,
  });

  factory DbExplorerGroup.fromJson(Map<String, dynamic> json) {
    return DbExplorerGroup(
      key: (json['key'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      items: ((json['items'] ?? []) as List)
          .map((e) => DbExplorerObjectItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class DbColumnInfo {
  final String name;
  final String dataType;
  final bool isNullable;
  final String? flag;

  DbColumnInfo({
    required this.name,
    required this.dataType,
    required this.isNullable,
    this.flag,
  });

  factory DbColumnInfo.fromJson(Map<String, dynamic> json) {
    return DbColumnInfo(
      name: (json['name'] ?? '').toString(),
      dataType: (json['dataType'] ?? '').toString(),
      isNullable: json['isNullable'] == true,
      flag: json['flag']?.toString(),
    );
  }
}

class DbObjectStructureResult {
  final String provider;
  final String objectName;
  final String objectType;
  final String? schemaName;
  final List<DbColumnInfo> columns;

  DbObjectStructureResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    this.schemaName,
    required this.columns,
  });

  factory DbObjectStructureResult.fromJson(Map<String, dynamic> json) {
    return DbObjectStructureResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      schemaName: json['schemaName']?.toString(),
      columns: ((json['columns'] ?? []) as List)
          .map((e) => DbColumnInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class DbObjectPreviewResult {
  final String provider;
  final String objectName;
  final String objectType;
  final String? schemaName;
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int rowCount;

  DbObjectPreviewResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    this.schemaName,
    required this.columns,
    required this.rows,
    required this.rowCount,
  });

  factory DbObjectPreviewResult.fromJson(Map<String, dynamic> json) {
    return DbObjectPreviewResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      schemaName: json['schemaName']?.toString(),
      columns: ((json['columns'] ?? []) as List).map((e) => e.toString()).toList(),
      rows: ((json['rows'] ?? []) as List)
          .map((row) => List<dynamic>.from(row as List))
          .toList(),
      rowCount: (json['rowCount'] ?? 0) as int,
    );
  }
}

class DbObjectDefinitionResult {
  final String provider;
  final String objectName;
  final String objectType;
  final String? schemaName;
  final String definition;

  DbObjectDefinitionResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    this.schemaName,
    required this.definition,
  });

  factory DbObjectDefinitionResult.fromJson(Map<String, dynamic> json) {
    return DbObjectDefinitionResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      schemaName: json['schemaName']?.toString(),
      definition: (json['definition'] ?? '').toString(),
    );
  }
}

class DbObjectParameterInfo {
  final String name;
  final String dataType;
  final String? direction;
  final bool? hasDefault;

  DbObjectParameterInfo({
    required this.name,
    required this.dataType,
    this.direction,
    this.hasDefault,
  });

  factory DbObjectParameterInfo.fromJson(Map<String, dynamic> json) {
    return DbObjectParameterInfo(
      name: (json['name'] ?? '').toString(),
      dataType: (json['dataType'] ?? '').toString(),
      direction: json['direction']?.toString(),
      hasDefault: json['hasDefault'] is bool ? json['hasDefault'] as bool : null,
    );
  }
}

class DbObjectParametersResult {
  final String provider;
  final String objectName;
  final String objectType;
  final String? schemaName;
  final List<DbObjectParameterInfo> parameters;

  DbObjectParametersResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    this.schemaName,
    required this.parameters,
  });

  factory DbObjectParametersResult.fromJson(Map<String, dynamic> json) {
    return DbObjectParametersResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      schemaName: json['schemaName']?.toString(),
      parameters: ((json['parameters'] ?? []) as List)
          .map((e) => DbObjectParameterInfo.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class QueryExecuteResult {
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int rowCount;
  final String message;

  QueryExecuteResult({
    required this.columns,
    required this.rows,
    required this.rowCount,
    required this.message,
  });

  factory QueryExecuteResult.fromJson(Map<String, dynamic> json) {
    return QueryExecuteResult(
      columns: ((json['columns'] ?? []) as List).map((e) => e.toString()).toList(),
      rows: ((json['rows'] ?? []) as List)
          .map((row) => List<dynamic>.from(row as List))
          .toList(),
      rowCount: (json['rowCount'] ?? 0) as int,
      message: (json['message'] ?? '').toString(),
    );
  }
}

class ConnectionApiService {
  ConnectionApiService({
    String? baseUrl,
    http.Client? client,
  })  : _baseUrl = baseUrl ?? 'https://dbpilot-5g16.onrender.com',
        _client = client ?? http.Client();

  final http.Client _client;
  final String _baseUrl;

  Future<ConnectionTestResult> testConnection(ConnectionRequest request) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/test-connection'), request.toJson());
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return ConnectionTestResult.fromJson(_decode(response));
  }

  Future<List<DbExplorerGroup>> getDbObjects(ConnectionRequest request) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/objects'), request.toJson());
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    final data = _decode(response);
    return ((data['groups'] ?? []) as List)
        .map((e) => DbExplorerGroup.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DbObjectStructureResult> getObjectStructure(
    ConnectionRequest request,
    String objectName,
    String objectType, {
    String? schemaName,
  }) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/object-structure'), {
      'connection': request.toJson(),
      'objectName': objectName,
      'objectType': objectType,
      'schemaName': schemaName,
    });
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return DbObjectStructureResult.fromJson(_decode(response));
  }

  Future<DbObjectPreviewResult> getObjectPreview(
    ConnectionRequest request,
    String objectName,
    String objectType, {
    String? schemaName,
    int limit = 50,
  }) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/object-preview'), {
      'connection': request.toJson(),
      'objectName': objectName,
      'objectType': objectType,
      'schemaName': schemaName,
      'limit': limit,
    });
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return DbObjectPreviewResult.fromJson(_decode(response));
  }

  Future<DbObjectDefinitionResult> getObjectDefinition(
    ConnectionRequest request,
    String objectName,
    String objectType, {
    String? schemaName,
  }) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/object-definition'), {
      'connection': request.toJson(),
      'objectName': objectName,
      'objectType': objectType,
      'schemaName': schemaName,
    });
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return DbObjectDefinitionResult.fromJson(_decode(response));
  }

  Future<DbObjectParametersResult> getObjectParameters(
    ConnectionRequest request,
    String objectName,
    String objectType, {
    String? schemaName,
  }) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/object-parameters'), {
      'connection': request.toJson(),
      'objectName': objectName,
      'objectType': objectType,
      'schemaName': schemaName,
    });
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return DbObjectParametersResult.fromJson(_decode(response));
  }

  Future<QueryExecuteResult> executeQuery(
    ConnectionRequest request,
    String sql, {
    int limit = 100,
    bool allowDataModification = false,
    int timeoutSeconds = 30,
  }) async {
    final response = await _post(Uri.parse('$_baseUrl/api/v1/execute-query'), {
      'connection': request.toJson(),
      'sql': sql,
      'limit': limit,
      'allowDataModification': allowDataModification,
      'timeoutSeconds': timeoutSeconds,
    }).timeout(Duration(seconds: timeoutSeconds + 2));
    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }
    return QueryExecuteResult.fromJson(_decode(response));
  }

  Future<http.Response> _post(Uri uri, Map<String, dynamic> body) {
    return _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _errorMessage(http.Response response) {
    final data = _decode(response);
    return (data['detail'] ?? data['message'] ?? response.body).toString();
  }

  void dispose() => _client.close();
}
