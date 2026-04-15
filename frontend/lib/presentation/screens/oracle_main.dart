import 'package:flutter/material.dart';

import '../widgets/db_admin_shell.dart';

class OracleMain extends StatelessWidget {
  const OracleMain({
    super.key,
    required this.connectionName,
    required this.host,
    required this.targetName,
  });

  final String connectionName;
  final String host;
  final String targetName;

  @override
  Widget build(BuildContext context) {
    return DbAdminShell(
      title: 'Oracle Administrator',
      providerLabel: 'ORACLE',
      connectionSummary: '$connectionName\n$host / $targetName',
      headerColor: const Color(0xFFB51F1F),
      sections: const [
        DbAdminSection(
          title: 'Tables',
          count: 12,
          items: ['CUSTOMERS', 'ORDERS', 'EMPLOYEES'],
          icon: Icons.grid_view_rounded,
        ),
        DbAdminSection(
          title: 'Procedures',
          count: 5,
          items: ['SP_UPDATE_ORDER', 'SP_CLOSE_DAY'],
          icon: Icons.account_tree_rounded,
        ),
        DbAdminSection(
          title: 'Functions',
          count: 4,
          items: ['FN_TOTAL_SALES', 'FN_GET_DISCOUNT'],
          icon: Icons.functions_rounded,
        ),
        DbAdminSection(
          title: 'Triggers',
          count: 3,
          items: ['TRG_AUDIT_ORDER', 'TRG_SET_DATE'],
          icon: Icons.local_fire_department_rounded,
        ),
      ],
    );
  }
}
