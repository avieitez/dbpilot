import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../widgets/db_object_explorer_shell.dart';

class PostgreSqlMain extends StatelessWidget {
  const PostgreSqlMain({
    super.key,
    required this.connection,
    required this.onUpgradeRequested,
  });

  final ConnectionRequest connection;
  final Future<void> Function() onUpgradeRequested;

  @override
  Widget build(BuildContext context) {
    final databaseName = connection.database.trim();

    return DbObjectExplorerShell(
      providerLabel: 'POSTGRESQL',
      connectionSummary:
          'Connection: ${connection.name}\nDatabase: ${databaseName.isEmpty ? 'database required' : databaseName}',
      connection: connection,
      onUpgradeRequested: onUpgradeRequested,
    );
  }
}
