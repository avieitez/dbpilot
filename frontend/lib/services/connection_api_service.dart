import 'dart:async';

import '../models/connection_request.dart';

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.success,
    required this.message,
    this.durationMs,
  });

  final bool success;
  final String message;
  final int? durationMs;
}

class ConnectionApiService {
  Future<ConnectionTestResult> testConnection(ConnectionRequest request) async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (request.host.trim().isEmpty) {
      throw Exception('Host is required');
    }

    if (request.username.trim().isEmpty) {
      throw Exception('Username is required');
    }

    return ConnectionTestResult(
      success: true,
      message: 'Connection parameters look valid',
      durationMs: 800,
    );
  }

  void dispose() {}
}
