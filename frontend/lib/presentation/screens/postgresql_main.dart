import 'package:flutter/material.dart';

import '../widgets/db_admin_shell.dart';

class PostgreSqlMain extends StatelessWidget {
  const PostgreSqlMain({
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
      title: 'PostgreSQL Administrator',
      providerLabel: 'POSTGRES',
      connectionSummary: '$connectionName\n$host / $database',
      headerColor: const Color(0xFF1F4DA8),
      sections: const [
        DbAdminSection(
          title: 'Tables',
          count: 10,
          items: ['users', 'orders', 'products'],
          icon: Icons.table_chart_rounded,
        ),
        DbAdminSection(
          title: 'Views',
          count: 2,
          items: ['active_users_view', 'sales_by_day_view'],
          icon: Icons.view_quilt_rounded,
        ),
        DbAdminSection(
          title: 'Functions',
          count: 7,
          items: ['fn_get_user_age', 'fn_total_sales', 'fn_calc_tax'],
          icon: Icons.functions_rounded,
        ),
        DbAdminSection(
          title: 'Extensions',
          count: 4,
          items: ['uuid-ossp', 'pgcrypto'],
          icon: Icons.extension_rounded,
        ),
      ],
    );
  }
}
