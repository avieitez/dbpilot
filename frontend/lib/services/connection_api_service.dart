import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/connection_request.dart';

class ConnectionTestResult {
  final bool success;
  final String message;
  final int? durationMs;

  ConnectionTestResult({
    required this.success,
    required this.message,
    this.durationMs,
  });

  factory ConnectionTestResult.fromJson(Map<String, dynamic> json) {
    return ConnectionTestResult(
      success: json['success'] == true,
      message: (json['message'] ?? json['detail'] ?? 'No message').toString(),
      durationMs: json['durationMs'] ?? json['duration_ms'],
    );
  }
}

class DbExplorerObjectItem {
  final String name;
  final String subtitle;
  final String objectType;

  DbExplorerObjectItem({
    required this.name,
    required this.subtitle,
    required this.objectType,
  });

  factory DbExplorerObjectItem.fromJson(Map<String, dynamic> json) {
    return DbExplorerObjectItem(
      name: (json['name'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
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
  final List<DbColumnInfo> columns;

  DbObjectStructureResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    required this.columns,
  });

  factory DbObjectStructureResult.fromJson(Map<String, dynamic> json) {
    return DbObjectStructureResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
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
  final List<String> columns;
  final List<List<dynamic>> rows;
  final int rowCount;

  DbObjectPreviewResult({
    required this.provider,
    required this.objectName,
    required this.objectType,
    required this.columns,
    required this.rows,
    required this.rowCount,
  });

  factory DbObjectPreviewResult.fromJson(Map<String, dynamic> json) {
    return DbObjectPreviewResult(
      provider: (json['provider'] ?? '').toString(),
      objectName: (json['objectName'] ?? '').toString(),
      objectType: (json['objectType'] ?? '').toString(),
      columns: ((json['columns'] ?? []) as List).map((e) => e.toString()).toList(),
      rows: ((json['rows'] ?? []) as List)
          .map((row) => List<dynamic>.from(row as List))
          .toList(),
      rowCount: (json['rowCount'] ?? 0) as int,
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
    final uri = Uri.parse('$_baseUrl/api/v1/test-connection');
    final response = await _post(uri, request.toJson());

    if (response.statusCode == 200) {
      return ConnectionTestResult.fromJson(_decode(response));
    }

    throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
  }

  Future<List<DbExplorerGroup>> getDbObjects(ConnectionRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/v1/objects');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    final Map<String, dynamic> data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }

    _decode(response);
    return ((data['groups'] ?? []) as List)
        .map((e) => DbExplorerGroup.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<DbObjectStructureResult> getObjectStructure(
    ConnectionRequest request,
    String objectName,
    String objectType,
  ) async {
    final uri = Uri.parse('$_baseUrl/api/v1/object-structure');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'connection': request.toJson(),
        'objectName': objectName,
        'objectType': objectType,
      }),
    );

    final Map<String, dynamic> data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      throw Exception('Error ${response.statusCode}: ${_errorMessage(response)}');
    }

    return DbObjectStructureResult.fromJson(_decode(response));
  }

  Future<QueryExecuteResult> getObjectPreview(
    ConnectionRequest request,
    String objectName,
    String objectType, {
    int limit = 50,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/object-preview');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'connection': request.toJson(),
        'objectName': objectName,
        'objectType': objectType,
        'limit': limit,
      }),
    );

    final Map<String, dynamic> data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

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

  Future<QueryExecuteResult> executeQuery(
    ConnectionRequest request,
    String sql, {
    int limit = 100,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/v1/execute-query');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'connection': request.toJson(),
        'sql': sql,
        'limit': limit,
      }),
    );

    final Map<String, dynamic> data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode != 200) {
      final message = data['detail'] ?? data['message'] ?? response.body;
      throw Exception('Error ${response.statusCode}: $message');
    }

    return QueryExecuteResult.fromJson(data);
  }

  void dispose() {
    _client.close();
  }
}
