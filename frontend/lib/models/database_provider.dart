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

  String get helperText {
    switch (this) {
      case DatabaseProvider.postgresql:
        return 'Fast, reliable and ideal for modern apps.';
      case DatabaseProvider.sqlServer:
        return 'Microsoft SQL Server for local, staging or enterprise environments.';
      case DatabaseProvider.oracle:
        return 'Oracle Database with service name or SID support.';
    }
  }

  String get asset {
    switch (this) {
      case DatabaseProvider.postgresql:
        return 'assets/providers/postgresql.png';
      case DatabaseProvider.sqlServer:
        return 'assets/providers/sqlserver.png';
      case DatabaseProvider.oracle:
        return 'assets/providers/oracle.png';
    }
  }

  static DatabaseProvider fromApiValue(String value) {
    switch (value.toLowerCase()) {
      case 'postgres':
      case 'postgresql':
        return DatabaseProvider.postgresql;
      case 'sqlserver':
      case 'sql_server':
      case 'mssql':
        return DatabaseProvider.sqlServer;
      case 'oracle':
        return DatabaseProvider.oracle;
      default:
        throw ArgumentError('Unsupported provider: $value');
    }
  }
}
