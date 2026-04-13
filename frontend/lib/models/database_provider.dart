enum DatabaseProvider {
  sqlServer(label: 'SQL Server', defaultPort: 1433),
  oracle(label: 'Oracle', defaultPort: 1521),
  postgresql(label: 'PostgreSQL', defaultPort: 5432);

  const DatabaseProvider({
    required this.label,
    required this.defaultPort,
  });

  final String label;
  final int defaultPort;
}
