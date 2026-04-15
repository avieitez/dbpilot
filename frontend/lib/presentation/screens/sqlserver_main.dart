import 'package:flutter/material.dart';

import '../widgets/db_admin_shell.dart';

class SqlServerMain extends StatelessWidget {
  const SqlServerMain({
    super.key,
    required this.connectionName,
    required this.host,
    required this.database,
  });

  final String connectionName;
  final String host;
  final String database;

  @override
  Widget build(BuildContext context) {
    return DbAdminShell(
      title: 'SQL Server Administrator',
      providerLabel: 'SQL SERVER',
      connectionSummary: '$connectionName\n$host / $database',
      headerColor: const Color(0xFF343A46),
      sections: const [
        DbAdminSection(
          title: 'Tables',
          count: 15,
          items: ['Customers', 'Orders', 'Products'],
          icon: Icons.grid_view_rounded,
        ),
        DbAdminSection(
          title: 'Views',
          count: 4,
          items: ['vw_ActiveUsers', 'vw_SalesSummary'],
          icon: Icons.view_module_rounded,
        ),
        DbAdminSection(
          title: 'Stored Procedures',
          count: 8,
          items: ['usp_UpdateOrder', 'usp_CloseDay', 'usp_RecalcStock'],
          icon: Icons.storage_rounded,
        ),
        DbAdminSection(
          title: 'Triggers',
          count: 3,
          items: ['trg_OrderAudit', 'trg_ProductSync'],
          icon: Icons.tune_rounded,
        ),
      ],
    );
  }
}
