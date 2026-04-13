import '../models/connection_profile.dart';
import '../models/database_provider.dart';

class MockConnectionsService {
  List<ConnectionProfile> loadConnections() {
    return const [
      ConnectionProfile(
        id: '1',
        name: 'Production SQL',
        provider: DatabaseProvider.sqlServer,
        host: '10.10.10.12',
        port: 1433,
        database: 'ERP_MAIN',
        username: 'admin_readonly',
        isFavorite: true,
      ),
      ConnectionProfile(
        id: '2',
        name: 'Finance Oracle',
        provider: DatabaseProvider.oracle,
        host: 'oracle.internal',
        port: 1521,
        database: 'FINPDB1',
        username: 'finance_user',
      ),
      ConnectionProfile(
        id: '3',
        name: 'Local Postgres',
        provider: DatabaseProvider.postgresql,
        host: '192.168.1.20',
        port: 5432,
        database: 'analytics',
        username: 'postgres',
      ),
    ];
  }
}
