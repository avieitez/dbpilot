import 'database_provider.dart';

class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.name,
    required this.provider,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    this.isFavorite = false,
  });

  final String id;
  final String name;
  final DatabaseProvider provider;
  final String host;
  final int port;
  final String database;
  final String username;
  final bool isFavorite;
}
