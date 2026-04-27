import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../widgets/db_object_explorer_shell.dart';

class PostgreSqlMain extends StatelessWidget {
  const PostgreSqlMain({
    super.key,
    required this.connection,
  });

  final ConnectionRequest connection;

  @override
  Widget build(BuildContext context) {
    final databaseName = connection.database.trim();

    return DbObjectExplorerShell(
      providerLabel: 'POSTGRESQL',
      connectionSummary: '${connection.name}\n${connection.host} / ${databaseName.isEmpty ? 'database required' : databaseName}',
      connection: connection,
    );
  }
}
