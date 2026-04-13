import 'connection_request.dart';
import 'database_provider.dart';

class ConnectionProfile {
  const ConnectionProfile({
    required this.name,
    required this.provider,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
  });

  final String name;
  final DatabaseProvider provider;
  final String host;
  final String port;
  final String database;
  final String username;

  factory ConnectionProfile.fromRequest(ConnectionRequest request) {
    return ConnectionProfile(
      name: request.name,
      provider: request.provider,
      host: request.host,
      port: request.port,
      database: request.database.isNotEmpty
          ? request.database
          : (request.serviceName ?? request.sid ?? ''),
      username: request.username,
    );
  }
}
