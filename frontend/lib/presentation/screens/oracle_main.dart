import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../widgets/db_object_explorer_shell.dart';

class OracleMain extends StatelessWidget {
  const OracleMain({
    super.key,
    required this.connection,
  });

  final ConnectionRequest connection;

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
      loadFromBackend: false,
      initialCategories: const [
        DbCategoryGroup(
          category: DbObjectCategory.tables,
          label: 'Tables',
          items: [
            DbExplorerObject(
              name: 'CUSTOMERS',
              subtitle: '5 cols',
              category: DbObjectCategory.tables,
              columns: [
                DbColumnInfo(name: 'CUSTOMER_ID', type: 'NUMBER', flag: 'PK',),
                DbColumnInfo(name: 'FIRST_NAME', type: 'VARCHAR2(100)'),
                DbColumnInfo(name: 'LAST_NAME', type: 'VARCHAR2(100)'),
                DbColumnInfo(name: 'EMAIL', type: 'VARCHAR2(255)'),
                DbColumnInfo(name: 'CREATED_AT', type: 'DATE'),
              ],
            ),
          ],
        ),
        DbCategoryGroup(
          category: DbObjectCategory.procedures,
          label: 'Procedures',
          items: [
            DbExplorerObject(
              name: 'SP_UPDATE_ORDER',
              subtitle: 'Procedure',
              category: DbObjectCategory.procedures,
              previewQuery: 'BEGIN\n  SP_UPDATE_ORDER(1001);\nEND;',
              objectType: 'procedure',
            ),
          ],
        ),
      ],
    );
  }
}
