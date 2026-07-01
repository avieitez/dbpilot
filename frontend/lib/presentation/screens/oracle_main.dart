import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../widgets/db_object_explorer_shell.dart';

class OracleMain extends StatelessWidget {
  const OracleMain({
    super.key,
    required this.connection,
    required this.onUpgradeRequested,
  });

  final ConnectionRequest connection;
  final Future<void> Function() onUpgradeRequested;

  @override
  Widget build(BuildContext context) {
    final targetName = (connection.serviceName ?? '').trim().isNotEmpty
        ? connection.serviceName!.trim()
        : (connection.sid ?? '').trim().isNotEmpty
            ? connection.sid!.trim()
            : 'XE';

    return DbObjectExplorerShell(
      providerLabel: 'ORACLE',
      connectionSummary: '${connection.name}\n${connection.host} / $targetName',
      connection: connection,
      onUpgradeRequested: onUpgradeRequested,
      loadFromBackend: true,
      initialCategories: const [],
    );
  }
}
