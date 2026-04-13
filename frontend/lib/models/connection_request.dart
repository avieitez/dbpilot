import 'database_provider.dart';

class ConnectionRequest {
  const ConnectionRequest({
    required this.name,
    required this.provider,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.database,
    this.serviceName,
    this.sid,
    this.encrypt = false,
    this.trustServerCertificate = false,
  });

  final String name;
  final DatabaseProvider provider;
  final String host;
  final String port;
  final String username;
  final String password;
  final String database;
  final String? serviceName;
  final String? sid;
  final bool encrypt;
  final bool trustServerCertificate;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'provider': provider.apiValue,
      'host': host,
      'port': int.tryParse(port) ?? 0,
      'username': username,
      'password': password,
      'database': database,
      'service_name': serviceName,
      'sid': sid,
      'encrypt': encrypt,
      'trust_server_certificate': trustServerCertificate,
    };
  }

  ConnectionRequest copyWith({
    String? name,
    DatabaseProvider? provider,
    String? host,
    String? port,
    String? username,
    String? password,
    String? database,
    String? serviceName,
    String? sid,
    bool? encrypt,
    bool? trustServerCertificate,
  }) {
    return ConnectionRequest(
      name: name ?? this.name,
      provider: provider ?? this.provider,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      database: database ?? this.database,
      serviceName: serviceName ?? this.serviceName,
      sid: sid ?? this.sid,
      encrypt: encrypt ?? this.encrypt,
      trustServerCertificate:
          trustServerCertificate ?? this.trustServerCertificate,
    );
  }
}
