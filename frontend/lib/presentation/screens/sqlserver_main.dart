import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../widgets/db_object_explorer_shell.dart';

class SqlServerMain extends StatelessWidget {
  const SqlServerMain({
    super.key,
    required this.connection,
    required this.onUpgradeRequested,
  });

  final ConnectionRequest connection;
  final Future<void> Function() onUpgradeRequested;

  @override
  Widget build(BuildContext context) {
    final databaseName =
        connection.database.trim().isNotEmpty ? connection.database : 'master';

    return DbObjectExplorerShell(
      providerLabel: 'SQL SERVER',
      connectionSummary:
          '${connection.name}\n${connection.host} / $databaseName',
      connection: connection.copyWith(database: databaseName),
      onUpgradeRequested: onUpgradeRequested,
    );
  }
}
