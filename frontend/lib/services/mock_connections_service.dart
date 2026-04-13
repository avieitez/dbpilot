import '../models/connection_profile.dart';
import '../models/database_provider.dart';

class MockConnectionsService {
  List<ConnectionProfile> loadConnections() {
    return const [
      ConnectionProfile(
        name: 'Local PostgreSQL',
        provider: DatabaseProvider.postgresql,
        host: 'localhost',
        port: '5432',
        database: 'postgres',
        username: 'postgres',
      ),
      ConnectionProfile(
        name: 'Local SQL Server',
        provider: DatabaseProvider.sqlServer,
        host: 'localhost',
        port: '1433',
        database: 'master',
        username: 'sa',
      ),
      ConnectionProfile(
        name: 'Oracle XE',
        provider: DatabaseProvider.oracle,
        host: 'localhost',
        port: '1521',
        database: 'XE',
        username: 'system',
      ),
    ];
  }
}
