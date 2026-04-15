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

class ConnectionApiService {
  final http.Client _client = http.Client();
  static const String _baseUrl = 'https://dbpilot-5g16.onrender.com';

  Future<ConnectionTestResult> testConnection(ConnectionRequest request) async {
    final uri = Uri.parse('$_baseUrl/api/v1/test-connection');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request.toJson()),
    );

    final Map<String, dynamic> data = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode == 200) {
      return ConnectionTestResult.fromJson(data);
    }

    final message = data['detail'] ?? data['message'] ?? response.body;
    throw Exception('Error ${response.statusCode}: $message');
  }

  void dispose() {
    _client.close();
  }
}
