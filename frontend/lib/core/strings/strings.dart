class AppStrings {
  static const sqlServer = "SQL Server";
  static const postgreSQL = "PostgreSQL";
  static const oracle = "Oracle";

  static const safe = "Safe";
  static const update = "Update";
  static const test = "Test";

  static const connectionName = "Connection Name";
  static const host = "Host";
  static const userName = "User Name";
  static const password = "Password";
  static const advancedSettings = "Advanced settings";
  static const port = "Port";
  static const database = "Database (Optional)";
  static const serviceName = "Service Name";
  static const sid = "SID";

  static const connect = "Connect";
  static const edit = "Edit";
  static const delete = "Delete";

  static const search = "Search tables, views, procedures...";
  static const tables = "Tables";
  static const views = "Views";
  static const procedures = "Procedures";
  static const functions = "Functions";
  
  static const table = "table";
  static const view = "view";
  static const procedure = "procedure";
  static const function = "function";
  static const trigger = "trigger";
  static const extension = "extension";

  static const structure = "Structure";
  static const columns = "Columns";
  static const notStructure = "There are no columns available yet";
  static const viewData = "View Data";
  static const runQuery = "Run Query";

  static const connections = "Connections";
  static const queries = "Queries";
  static const settings = "Settings";

  static const newConnection = "New Connection";
  static const editConnection = "Edit Connection";

  static const exampleQuery = "Example query"; 
  static const clear = "Clear"; 
  static const preview = "Preview";
  static const norows = "There are no rows to show.";
}

class QeStrings {
  const QeStrings._();

  static const String formatSql = 'FORMAT SQL';
  static const String saveQuery = 'SAVE QUERY';
  static const String loadQuery = 'LOAD QUERY';
  static const String sqlHint = 'Write SQL here...';
  static const String limit = 'Limit';
  static const String timeout = 'Timeout';
  static const String transaction = 'Transaction';
  static const String execute = 'Execute';
  static const String executeQuery = 'Execute Query';

  static const List<String> tabs = ['Editor', 'Results', 'Messages', 'History'];

  static const String noSqlToRun = 'There is no SQL to execute.';
  static const String sqlFormatted = 'SQL formatted.';
  static const String editorCleared = 'Editor cleared.';
  static const String localSavePending = 'Local save is pending integration.';
  static const String exportCsvPending = 'CSV export is pending implementation.';

  static String queryExecuted(int elapsedMilliseconds, int rowCount) =>
      'Query executed in $elapsedMilliseconds ms. Rows: $rowCount.';

  static const String noResultsTitle = 'No results';
  static const String noResultsMessage = 'Run a query to see data here.';
  static const String queryExecutedTitle = 'Query executed';
  static const String commandExecuted = 'Command executed successfully.';

  static const String noMessagesTitle = 'No messages';
  static const String noMessagesMessage = 'Errors and notices will appear here.';

  static const String noHistoryTitle = 'No history';
  static const String noHistoryMessage = 'Queries executed during this session will be stored here.';

  static const String sqlErrorTitle = 'SQL execution error';
  static const String safeMode = 'Safe Mode';
  static const String safeModeOnDescription = 'ON: only SELECT statements are allowed.';
  static const String safeModeOffDescription = 'OFF: INSERT, UPDATE, DELETE and DDL statements are allowed.';
  static const String safeModeBlockedMessage = 'Data modification is disabled. Turn Safe Mode OFF to run this statement.';
  static const String executionCancelled = 'Execution cancelled.';
  static const String cancel = 'Cancel';
  static const String confirmExecutionTitle = 'Confirm data modification';
  static String confirmExecutionMessage(String statement) =>
      'You are about to execute a $statement statement. This may modify real data. Continue?';
}
