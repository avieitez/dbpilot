enum DatabaseProvider {
  postgresql,
  sqlServer,
  oracle,
}

extension DatabaseProviderX on DatabaseProvider {
  String get label {
    switch (this) {
      case DatabaseProvider.postgresql:
        return 'PostgreSQL';
      case DatabaseProvider.sqlServer:
        return 'SQL Server';
      case DatabaseProvider.oracle:
        return 'Oracle';
    }
  }

  String get apiValue {
    switch (this) {
      case DatabaseProvider.postgresql:
        return 'postgresql';
      case DatabaseProvider.sqlServer:
        return 'sqlserver';
      case DatabaseProvider.oracle:
        return 'oracle';
    }
  }

  String get defaultPort {
    switch (this) {
      case DatabaseProvider.postgresql:
        return '5432';
      case DatabaseProvider.sqlServer:
        return '1433';
      case DatabaseProvider.oracle:
        return '1521';
    }
  }

  String get asset {
    switch (this) {
      case DatabaseProvider.postgresql:
        return 'assets/providers/postgre.png';
      case DatabaseProvider.sqlServer:
        return 'assets/providers/sql_server.png';
      case DatabaseProvider.oracle:
        return 'assets/providers/oracle.png';
    }
  }
}
