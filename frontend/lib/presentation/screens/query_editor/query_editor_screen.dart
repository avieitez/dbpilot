import 'dart:async';
import 'dart:convert';

import 'package:dbpilot/models/database_provider.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../models/connection_request.dart';
import '../../../services/connection_api_service.dart';
import '../../../core/strings/strings.dart';

import '../../../services/query_history_storage_service.dart';

class QueryEditorScreen extends StatefulWidget {
  const QueryEditorScreen({
    super.key,
    required this.connection,
    required this.providerLabel,
    required this.connectionSummary,
    this.initialSql,
    this.objectName,
    this.objectType,
    this.schemaName,
  });

  final ConnectionRequest connection;
  final String providerLabel;
  final String connectionSummary;
  final String? initialSql;
  final String? objectName;
  final String? objectType;
  final String? schemaName;

  @override
  State<QueryEditorScreen> createState() => _QueryEditorScreenState();
}

class _QueryEditorScreenState extends State<QueryEditorScreen> {
  static const double _editorLineHeight = 21;
  static final Map<String, _QueryEditorSessionSnapshot> _sessionSnapshots = {};

  final _historyService = QueryHistoryStorageService();
  late final _SqlTextEditingController _sqlController;
  late final FocusNode _editorFocusNode;
  late final ScrollController _editorScrollController;
  late final ConnectionApiService _apiService;

  int _selectedTab = 0;
  int _limit = 100;
  int _timeoutSeconds = 30;
  int _resultsPage = 0;
  int _rowsPerPage = 10;
  bool _safeMode = true;
  bool _executing = false;
  bool _savingExecutedQuery = false;
  bool _allowPopAfterPendingSaveAttempt = false;
  Future<void>? _savingExecutedQueryFuture;
  Duration? _lastDuration;
  String? _errorMessage;
  String? _lastSuccessfulSql;
  String? _lastSavedSql;
  QueryExecuteResult? _result;
  final List<_HistoryEntry> _history = [];
  final List<String> _messages = [];

  String get _sessionKey => [
        widget.connection.provider.apiValue,
        widget.connection.name,
        widget.connectionSummary,
      ].join('|');

  @override
  void initState() {
    super.initState();
    _apiService = ConnectionApiService();
    _editorFocusNode = FocusNode();
    _editorFocusNode.addListener(_refreshEditorChrome);
    _editorScrollController = ScrollController();
    final snapshot = _sessionSnapshots[_sessionKey];
    _sqlController = _SqlTextEditingController(
      provider: widget.connection.provider,
      text: widget.initialSql == null && snapshot?.sql.trim().isNotEmpty == true
          ? snapshot!.sql
          : _initialSql(),
    );
    _sqlController.addListener(_refreshEditorChrome);
    if (snapshot != null) {
      _selectedTab = snapshot.selectedTab;
      _limit = snapshot.limit;
      _timeoutSeconds = snapshot.timeoutSeconds;
      _resultsPage = snapshot.resultsPage;
      _rowsPerPage = snapshot.rowsPerPage;
      _safeMode = snapshot.safeMode;
      _lastDuration = snapshot.lastDuration;
      _errorMessage = snapshot.errorMessage;
      _lastSuccessfulSql = snapshot.lastSuccessfulSql;
      _lastSavedSql = snapshot.lastSavedSql;
      _result = snapshot.result;
      _history
        ..clear()
        ..addAll(snapshot.history);
      _messages
        ..clear()
        ..addAll(snapshot.messages);
    }
  }

  void _refreshEditorChrome() {
    if (mounted) setState(() {});
  }

  String _initialSql() {
    final sql = widget.initialSql?.trim();
    if (sql != null && sql.isNotEmpty) return sql;

    final provider = widget.connection.provider.apiValue;
    final objectName = widget.objectName?.trim();
    final schemaName = widget.schemaName?.trim();

    if (objectName == null || objectName.isEmpty) return '';

    final qualifiedName = (schemaName != null && schemaName.isNotEmpty)
        ? '$schemaName.$objectName'
        : objectName;

    if (provider == 'postgresql') {
      return 'SELECT *\nFROM $qualifiedName;';
    }

    if (provider == 'sqlserver' || provider == 'sql_server' || provider == 'mssql') {
      return 'SELECT *\nFROM $qualifiedName;';
    }

    if (provider == 'oracle') {
      return 'SELECT *\nFROM $qualifiedName;';
    }

    return 'SELECT *\nFROM $qualifiedName;';
  }

  Future<void> _execute() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) {
      _addMessage(QeStrings.noSqlToRun);
      return;
    }

    if (_safeMode && _isDataModificationStatement(sql)) {
      setState(() => _selectedTab = 2);
      _addMessage(QeStrings.safeModeBlockedMessage);
      return;
    }

    if (!_safeMode && _isDangerousStatement(sql)) {
      final confirmed = await _confirmDataModification(sql);
      if (!confirmed) {
        _addMessage(QeStrings.executionCancelled);
        return;
      }
    }

    setState(() {
      _executing = true;
      _allowPopAfterPendingSaveAttempt = false;
      _errorMessage = null;
      _selectedTab = 1;
    });

    final watch = Stopwatch()..start();

    String sqlToExecute = sql.trim();

    if (widget.connection.provider == DatabaseProvider.oracle) {
      sqlToExecute = sqlToExecute.replaceFirst(
        RegExp(r';+\s*$'),
        '',
      );
    }
    try {
      final result = await _apiService.executeQuery(
        widget.connection,
        sqlToExecute,
        limit: _limit,
        allowDataModification: !_safeMode,
        timeoutSeconds: _timeoutSeconds,
      ).timeout(Duration(seconds: _timeoutSeconds));

      watch.stop();
      _lastSuccessfulSql = sqlToExecute;
      await _saveExecutedQuery(sqlToExecute);

      if (!mounted) return;
      setState(() {
        _result = result;
        _lastDuration = watch.elapsed;
        _executing = false;
        _resultsPage = 0;
        _history.insert(0, _HistoryEntry(sql: sql, dateTime: DateTime.now(), message: result.message));
        if (_history.length > 50) _history.removeLast();
      });
      _addMessage(
        QeStrings.queryExecuted(watch.elapsedMilliseconds, result.rowCount),
        includeExecutionSettings: true,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _executing = false;
        _selectedTab = 2;
        _errorMessage = 'Query timed out after $_timeoutSeconds seconds.';
      });
      _addMessage('ERROR: Query timed out after $_timeoutSeconds seconds.');
    } catch (error) {
      watch.stop();
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _executing = false;
        _errorMessage = message;
        _selectedTab = 2;
      });
      _addMessage('ERROR: $message');
    }
  }

  bool get _hasPendingSuccessfulQuerySave {
    final sql = _lastSuccessfulSql;
    return sql != null && sql != _lastSavedSql;
  }

  Future<void> _savePendingSuccessfulQuery() async {
    final sql = _lastSuccessfulSql;
    if (sql == null || sql == _lastSavedSql) return;

    await _saveExecutedQuery(sql);
  }

  Future<void> _saveExecutedQuery(String sql) async {
    if (sql == _lastSavedSql) return;
    if (_savingExecutedQuery) {
      await _savingExecutedQueryFuture;
      return;
    }

    _savingExecutedQuery = true;
    _savingExecutedQueryFuture = _saveExecutedQueryNow(sql);

    await _savingExecutedQueryFuture;
  }

  Future<void> _saveExecutedQueryNow(String sql) async {
    try {
      await _historyService.saveQuery(
        provider: widget.connection.provider.apiValue,
        connectionName: widget.connection.name,
        sql: sql,
      );
      _lastSavedSql = sql;
    } catch (error) {
      if (!mounted) return;
      _addMessage('Query executed, but it could not be saved: $error');
    } finally {
      _savingExecutedQuery = false;
      _savingExecutedQueryFuture = null;
    }
  }

  Future<void> _handlePendingSaveBeforePop(bool didPop) async {
    if (didPop) return;

    await _savePendingSuccessfulQuery();

    if (!mounted) return;
    _allowPopAfterPendingSaveAttempt = true;
    Navigator.of(context).pop();
  }

  void _addMessage(String message, {bool includeExecutionSettings = false}) {
    final details = includeExecutionSettings
        ? '$message\n${QeStrings.limit}: $_limit · ${QeStrings.timeout}: ${_timeoutSeconds}s'
        : message;

    setState(() {
      _messages.insert(0, '${_formatDateTime(DateTime.now())} · $details');
      if (_messages.length > 100) _messages.removeLast();
    });
  }

  String _csvEscape(dynamic value) {
    final text = value?.toString() ?? '';
    final escaped = text.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<Map<String, dynamic>> _resultRowsAsMaps(QueryExecuteResult result) {
    return result.rows.map((row) {
      final item = <String, dynamic>{};
      for (var i = 0; i < result.columns.length; i++) {
        item[result.columns[i]] = i < row.length ? row[i] : null;
      }
      return item;
    }).toList();
  }

  String _resultsAsDelimitedText(QueryExecuteResult result, String separator) {
    final buffer = StringBuffer();
    buffer.writeln(result.columns.map(_csvEscape).join(separator));

    for (final row in result.rows) {
      final values = <String>[];

      for (var i = 0; i < result.columns.length; i++) {
        final value = i < row.length ? row[i] : '';
        values.add(_csvEscape(value));
      }

      buffer.writeln(values.join(separator));
    }

    return buffer.toString();
  }

  Future<void> _shareTextFile({
    required String content,
    required String fileName,
    required String shareText,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(content, flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: shareText,
    );
  }

  String _exportTimestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll('T', '_');
  }

  Future<void> _copyResultsToClipboard() async {
    final result = _result;

    if (result == null || result.rows.isEmpty) {
      _addMessage('No rows to copy.');
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: _resultsAsDelimitedText(result, '\t')),
    );

    _addMessage('Results copied to clipboard.');
  }

  Future<void> _exportResultsToCsv() async {
    final result = _result;

    if (result == null || result.rows.isEmpty) {
      _addMessage('No rows to export.');
      return;
    }

    try {
      await _shareTextFile(
        content: _resultsAsDelimitedText(result, ','),
        fileName: 'results_${_exportTimestamp()}.csv',
        shareText: 'Query results CSV',
      );

      _addMessage('CSV exported successfully.');
    } catch (error) {
      _addMessage('CSV export failed: $error');
    }
  }

  Future<void> _exportResultsToJson() async {
    final result = _result;

    if (result == null || result.rows.isEmpty) {
      _addMessage('No rows to export.');
      return;
    }

    try {
      const encoder = JsonEncoder.withIndent('  ');
      await _shareTextFile(
        content: encoder.convert(_resultRowsAsMaps(result)),
        fileName: 'results_${_exportTimestamp()}.json',
        shareText: 'Query results JSON',
      );

      _addMessage('JSON exported successfully.');
    } catch (error) {
      _addMessage('JSON export failed: $error');
    }
  }

  Future<void> _exportResultsToExcel() async {
    final result = _result;

    if (result == null || result.rows.isEmpty) {
      _addMessage('No rows to export.');
      return;
    }

    try {
      await _shareTextFile(
        content: _resultsAsDelimitedText(result, '\t'),
        fileName: 'results_${_exportTimestamp()}.xls',
        shareText: 'Query results Excel',
      );

      _addMessage('Excel export generated successfully.');
    } catch (error) {
      _addMessage('Excel export failed: $error');
    }
  }

  Future<void> _showLoadQueryDialog() async {
  final queries = await _historyService.getQueries(
    provider: widget.connection.provider.apiValue,
  );

  if (!mounted) return;

  if (queries.isEmpty) {
    _addMessage('No saved queries found.');
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: queries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = queries[index];
              final preview = item.sql.replaceAll('\n', ' ');

              return ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(
                  item.connectionName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      item.executedAt.toString(),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    await _historyService.deleteQuery(item.id);

                    if (!context.mounted) return;

                    Navigator.pop(context);

                    _addMessage('Query deleted.');

                    await _showLoadQueryDialog();
                  },
                ),
                isThreeLine: true,
                onTap: () {
                  _sqlController.text = item.sql;

                  Navigator.pop(context);

                  setState(() {
                    _selectedTab = 0;
                  });

                  _addMessage('Query loaded.');
                },
              );
            },
          ),
        ),
      );
    },
  );
}

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(hour12)}:${two(value.minute)} $period';
  }

  void _formatSql() {
    var sql = _sqlController.text.trim();
    if (sql.isEmpty) return;

    final replacements = <String, String>{
      r'\bselect\b': 'SELECT',
      r'\bfrom\b': '\nFROM',
      r'\bwhere\b': '\nWHERE',
      r'\binner\s+join\b': '\nINNER JOIN',
      r'\bleft\s+join\b': '\nLEFT JOIN',
      r'\bright\s+join\b': '\nRIGHT JOIN',
      r'\bjoin\b': '\nJOIN',
      r'\bgroup\s+by\b': '\nGROUP BY',
      r'\border\s+by\b': '\nORDER BY',
      r'\bhaving\b': '\nHAVING',
      r'\bvalues\b': '\nVALUES',
      r'\bset\b': '\nSET',
    };

    replacements.forEach((pattern, replacement) {
      sql = sql.replaceAll(RegExp(pattern, caseSensitive: false), replacement);
    });

    _sqlController.text = sql.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    _addMessage(QeStrings.sqlFormatted);
    _editorFocusNode.requestFocus();
  }

  void _clearEditor() {
    _sqlController.clear();
    _addMessage(QeStrings.editorCleared);
    _editorFocusNode.requestFocus();
  }

  void _loadHistory(_HistoryEntry entry) {
    _sqlController.text = entry.sql;
    setState(() => _selectedTab = 0);
    _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _sessionSnapshots[_sessionKey] = _QueryEditorSessionSnapshot(
      sql: _sqlController.text,
      selectedTab: _selectedTab,
      limit: _limit,
      timeoutSeconds: _timeoutSeconds,
      resultsPage: _resultsPage,
      rowsPerPage: _rowsPerPage,
      safeMode: _safeMode,
      lastDuration: _lastDuration,
      errorMessage: _errorMessage,
      lastSuccessfulSql: _lastSuccessfulSql,
      lastSavedSql: _lastSavedSql,
      result: _result,
      history: List<_HistoryEntry>.of(_history),
      messages: List<String>.of(_messages),
    );
    _sqlController.removeListener(_refreshEditorChrome);
    _editorFocusNode.removeListener(_refreshEditorChrome);
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    _sqlController.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return PopScope(
      canPop: _allowPopAfterPendingSaveAttempt || !_hasPendingSuccessfulQuerySave,
      onPopInvoked: _handlePendingSaveBeforePop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.providerLabel} · Query Editor', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            Text(widget.connectionSummary.replaceAll('\n', ' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(onPressed: _clearEditor, icon: const Icon(Icons.delete_sweep_rounded), tooltip: AppStrings.clear),
        ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _QueryTabs(selectedIndex: _selectedTab, onChanged: (index) => setState(() => _selectedTab = index)),
              _buildToolbar(theme, colors),
              Expanded(
                child: IndexedStack(
                  index: _selectedTab,
                  children: [
                    _buildEditor(theme, colors),
                    _buildResults(theme, colors),
                    _buildMessages(theme, colors),
                    _buildHistory(theme, colors),
                  ],
                ),
              ),
              _buildBottomBar(theme, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, ColorScheme colors) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF07101B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _editorFocusNode.hasFocus
                      ? colors.primary.withOpacity(0.75)
                      : colors.outlineVariant.withOpacity(0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Column(
                  children: [
                    _EditorHeader(
                      providerLabel: widget.providerLabel,
                      objectName: widget.objectName,
                      schemaName: widget.schemaName,
                    ),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _LineNumbers(
                            controller: _sqlController,
                            scrollController: _editorScrollController,
                            lineHeight: _editorLineHeight,
                          ),
                          Expanded(
                            child: TextField(
                              focusNode: _editorFocusNode,
                              controller: _sqlController,
                              scrollController: _editorScrollController,
                              expands: true,
                              maxLines: null,
                              minLines: null,
                              textAlignVertical: TextAlignVertical.top,
                              keyboardType: TextInputType.multiline,
                              autocorrect: false,
                              enableSuggestions: false,
                              scrollPadding: const EdgeInsets.only(bottom: 180),
                              onTapOutside: (_) {},
                              cursorColor: colors.secondary,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFD6E2F0),
                                fontFamily: 'monospace',
                                height: 1.5,
                                letterSpacing: 0,
                              ),
                              decoration: InputDecoration(
                                hintText: QeStrings.sqlHint,
                                hintStyle: TextStyle(color: colors.onSurfaceVariant.withOpacity(0.55)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.fromLTRB(14, 16, 18, 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _EditorStatusBar(
                      position: _cursorPositionLabel(),
                      lineCount: _lineCount,
                      characterCount: _sqlController.text.length,
                      safeMode: _safeMode,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _buildQuickKeys(colors),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          Expanded(child: _ToolbarButton(icon: Icons.auto_fix_high_rounded, label: QeStrings.formatSql, onTap: _formatSql)),
          const SizedBox(width: 6),
          Expanded(child: _ToolbarButton(icon: Icons.folder_open_rounded, label: QeStrings.loadQuery, onTap: _showLoadQueryDialog,)),
          const SizedBox(width: 6),
          Expanded(
            child: _ToolbarButton(
              icon: Icons.play_arrow_rounded,
              label: QeStrings.runQuery,
              onTap: _executing ? null : _execute,
              busy: _executing,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickKeys(ColorScheme colors) {
    const keys = ['SELECT', 'FROM', 'WHERE', 'JOIN', 'AND', 'OR', 'GROUP BY', 'ORDER BY'];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = keys[index];
          return ActionChip(
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: colors.outlineVariant.withOpacity(0.55)),
            backgroundColor: colors.surfaceContainerHighest.withOpacity(0.35),
            labelStyle: TextStyle(
              color: colors.onSurface.withOpacity(0.88),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
            label: Text(value),
            onPressed: () {
              final text = _sqlController.text;
              final selection = _sqlController.selection;
              final insertAt = selection.start >= 0 ? selection.start : text.length;
              final next = text.replaceRange(insertAt, insertAt, '$value ');
              _sqlController.value = TextEditingValue(
                text: next,
                selection: TextSelection.collapsed(offset: insertAt + value.length + 1),
              );
              _editorFocusNode.requestFocus();
            },
          );
        },
      ),
    );
  }

  int get _lineCount => ('\n'.allMatches(_sqlController.text).length + 1).clamp(1, 9999).toInt();

  String _cursorPositionLabel() {
    final text = _sqlController.text;
    final selectionStart = _sqlController.selection.start;
    final offset = selectionStart < 0 ? text.length : selectionStart.clamp(0, text.length).toInt();
    final beforeCursor = text.substring(0, offset);
    final line = '\n'.allMatches(beforeCursor).length + 1;
    final lastBreak = beforeCursor.lastIndexOf('\n');
    final column = offset - lastBreak;

    return 'Ln $line, Col $column';
  }

  Widget _buildBottomBar(ThemeData theme, ColorScheme colors) {
    final compactResultsBar = _selectedTab == 1 &&
        _result != null &&
        MediaQuery.of(context).size.height < 760;

    if (compactResultsBar) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant.withOpacity(0.5))),
          ),
          child: Row(
            children: [
              const Spacer(),
              Tooltip(
                message: _safeMode ? QeStrings.safeModeOnDescription : QeStrings.safeModeOffDescription,
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => _safeMode = !_safeMode),
                  icon: Icon(_safeMode ? Icons.shield_outlined : Icons.warning_amber_rounded),
                  color: _safeMode ? colors.primary : colors.error,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.outlineVariant.withOpacity(0.5))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _safeMode ? colors.surfaceContainerHighest.withOpacity(0.45) : colors.errorContainer.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _safeMode ? colors.outlineVariant.withOpacity(0.5) : colors.error.withOpacity(0.6)),
              ),
              child: Row(
                children: [
                  Icon(_safeMode ? Icons.shield_outlined : Icons.warning_amber_rounded, color: _safeMode ? colors.primary : colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(QeStrings.safeMode, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(_safeMode ? QeStrings.safeModeOnDescription : QeStrings.safeModeOffDescription, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Switch(value: _safeMode, onChanged: (value) => setState(() => _safeMode = value)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _DropDownBox<int>(label: QeStrings.limit, value: _limit, values: const [50, 100, 250, 500], onChanged: (v) => setState(() => _limit = v))),
                const SizedBox(width: 8),
                Expanded(child: _DropDownBox<int>(label: QeStrings.timeout, value: _timeoutSeconds, values: const [10, 30, 60], suffix: 's', onChanged: (v) => setState(() => _timeoutSeconds = v))),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, ColorScheme colors) {
    if (_errorMessage != null) return _ErrorPanel(message: _errorMessage!);
    final result = _result;
    if (result == null) return const _EmptyPanel(icon: Icons.table_chart_outlined, title: QeStrings.noResultsTitle, message: QeStrings.noResultsMessage);
    if (result.columns.isEmpty) return _EmptyPanel(icon: Icons.check_circle_outline_rounded, title: QeStrings.queryExecutedTitle, message: result.message.isEmpty ? QeStrings.commandExecuted : result.message);

    final totalRows = result.rows.length;
    final pageCount = (totalRows / _rowsPerPage).ceil().clamp(1, 999999).toInt();
    final page = _resultsPage.clamp(0, pageCount - 1).toInt();
    final start = page * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, totalRows).toInt();
    final pageRows = result.rows.sublist(start, end);
    final successMessage = _lastDuration == null
        ? 'Query executed successfully'
        : 'Query executed successfully in ${_lastDuration!.inMilliseconds} ms';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final horizontalPadding = compact ? 8.0 : 12.0;

        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                compact ? 8 : 12,
                horizontalPadding,
                compact ? 6 : 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0B111D),
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant.withOpacity(0.45)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Results (${result.rowCount})',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: const Color(0xFFE6EBF4),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (compact && result.rows.isNotEmpty)
                    _ResultsExportMenu(
                      onCopy: _copyResultsToClipboard,
                      onCsv: _exportResultsToCsv,
                      onJson: _exportResultsToJson,
                      onExcel: _exportResultsToExcel,
                    ),
                  IconButton(
                    onPressed: _executing ? null : _execute,
                    icon: const Icon(Icons.refresh_rounded),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 12, horizontalPadding, 8),
                child: _ResultSuccessBanner(message: successMessage),
              ),
            if (!compact)
              Padding(
                padding: EdgeInsets.fromLTRB(horizontalPadding, 0, horizontalPadding, 10),
                child: _ExportToolbar(
                  hasRows: result.rows.isNotEmpty,
                  onCopy: _copyResultsToClipboard,
                  onCsv: _exportResultsToCsv,
                  onJson: _exportResultsToJson,
                  onExcel: _exportResultsToExcel,
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _ResultsGrid(
                  columns: result.columns,
                  rows: pageRows,
                  firstRowNumber: start + 1,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(horizontalPadding, compact ? 6 : 10, horizontalPadding, compact ? 8 : 12),
              child: _ResultsPager(
                compact: compact,
                start: totalRows == 0 ? 0 : start + 1,
                end: end,
                total: totalRows,
                rowsPerPage: _rowsPerPage,
                canGoPrevious: page > 0,
                canGoNext: page < pageCount - 1,
                onRowsPerPageChanged: (value) {
                  setState(() {
                    _rowsPerPage = value;
                    _resultsPage = 0;
                  });
                },
                onPrevious: () {
                  if (page == 0) return;
                  setState(() => _resultsPage = page - 1);
                },
                onNext: () {
                  if (page >= pageCount - 1) return;
                  setState(() => _resultsPage = page + 1);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMessages(ThemeData theme, ColorScheme colors) {
    if (_messages.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.message_outlined,
        title: QeStrings.noMessagesTitle,
        message: QeStrings.noMessagesMessage,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final parsed = _ParsedMessage.fromRaw(_messages[index]);
        final isError = parsed.kind == _MessageKind.error;
        final isWarning = parsed.kind == _MessageKind.warning;
        final accentColor = isError
            ? colors.error
            : isWarning
                ? Colors.orangeAccent
                : Colors.greenAccent.shade200;
        final borderColor = isError
            ? colors.error.withOpacity(0.45)
            : isWarning
                ? Colors.orangeAccent.withOpacity(0.42)
                : Colors.green.withOpacity(0.40);
        final backgroundColor = isError
            ? colors.errorContainer.withOpacity(0.30)
            : isWarning
                ? const Color(0xFF2A210F)
                : const Color(0xFF0D2318);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(parsed.icon, size: 21, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      parsed.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(
                parsed.dateTime,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF9AA6B8),
                  fontFamily: 'monospace',
                  height: 1.45,
                  letterSpacing: 0.2,
                ),
              ),
              if (parsed.body.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  parsed.body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF9AA6B8),
                    fontFamily: 'monospace',
                    height: 1.45,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistory(ThemeData theme, ColorScheme colors) {
    if (_history.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.history_rounded,
        title: QeStrings.noHistoryTitle,
        message: QeStrings.noHistoryMessage,
      );
    }
 
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _history[index];
 
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            // Match screenshot: dark blue-grey card
            color: colors.primaryContainer.withOpacity(0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.primary.withOpacity(0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: "Query #N"  +  full date/time ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Query #${_history.length - index}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: colors.onSurface,   // white / bright — matches screenshot
                    ),
                  ),
                  const Spacer(),
                  // Full date + time: "YYYY-MM-DD HH:MM AM/PM"
                  Text(
                    _formatDateTime(entry.dateTime),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
 
              const SizedBox(height: 12),
 
              // ── SQL body — monospace, no line limit (full query visible) ──
              SelectableText(
                entry.sql,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.45,
                  color: colors.onSurface,
                ),
              ),
 
              const SizedBox(height: 14),
 
              // ── "← LOAD QUERY" — uppercase, matches screenshot ──
              GestureDetector(
                onTap: () => _loadHistory(entry),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.keyboard_return_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      QeStrings.loadQuery.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isDataModificationStatement(String sql) {
    final firstWord = _firstSqlWord(sql);
    return const {'insert', 'update', 'delete', 'merge', 'create', 'alter', 'drop', 'truncate', 'exec', 'execute'}.contains(firstWord);
  }

  bool _isDangerousStatement(String sql) {
    final firstWord = _firstSqlWord(sql);
    return const {'insert', 'update', 'delete', 'merge', 'drop', 'truncate', 'alter', 'create', 'exec', 'execute'}.contains(firstWord);
  }

  String _firstSqlWord(String sql) {
    var cleaned = sql.trimLeft();
    while (cleaned.startsWith('--')) {
      final end = cleaned.indexOf('\n');
      if (end < 0) return '';
      cleaned = cleaned.substring(end + 1).trimLeft();
    }
    final match = RegExp(r'^[a-zA-Z]+').firstMatch(cleaned);
    return match?.group(0)?.toLowerCase() ?? '';
  }

  Future<bool> _confirmDataModification(String sql) async {
    final firstWord = _firstSqlWord(sql).toUpperCase();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(QeStrings.confirmExecutionTitle),
        content: Text(QeStrings.confirmExecutionMessage(firstWord)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text(QeStrings.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(QeStrings.runQuery)),
        ],
      ),
    );
    return result == true;
  }
}

class _ResultSuccessBanner extends StatelessWidget {
  const _ResultSuccessBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF15312D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF295046)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFF5BA84F),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFF3F7FB),
                    fontWeight: FontWeight.w800,
                    height: 1.22,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExportToolbar extends StatelessWidget {
  const _ExportToolbar({
    required this.hasRows,
    required this.onCopy,
    required this.onCsv,
    required this.onJson,
    required this.onExcel,
  });

  final bool hasRows;
  final VoidCallback onCopy;
  final VoidCallback onCsv;
  final VoidCallback onJson;
  final VoidCallback onExcel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ExportButton(
            icon: Icons.copy_all_rounded,
            label: 'Copy',
            enabled: hasRows,
            onPressed: onCopy,
          ),
          const SizedBox(width: 8),
          _ExportButton(
            icon: Icons.description_rounded,
            label: 'CSV',
            enabled: hasRows,
            onPressed: onCsv,
          ),
          const SizedBox(width: 8),
          _ExportButton(
            icon: Icons.data_object_rounded,
            label: 'JSON',
            enabled: hasRows,
            onPressed: onJson,
          ),
          const SizedBox(width: 8),
          _ExportButton(
            icon: Icons.table_chart_rounded,
            label: 'Excel',
            enabled: hasRows,
            onPressed: onExcel,
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFE7EDF7),
        disabledForegroundColor: Colors.white30,
        side: BorderSide(color: Colors.white.withOpacity(0.24)),
        backgroundColor: const Color(0xFF121925),
        minimumSize: const Size(82, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _ResultsExportMenu extends StatelessWidget {
  const _ResultsExportMenu({
    required this.onCopy,
    required this.onCsv,
    required this.onJson,
    required this.onExcel,
  });

  final VoidCallback onCopy;
  final VoidCallback onCsv;
  final VoidCallback onJson;
  final VoidCallback onExcel;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Export',
      icon: const Icon(Icons.file_download_outlined),
      onSelected: (value) {
        switch (value) {
          case 'copy':
            onCopy();
            break;
          case 'csv':
            onCsv();
            break;
          case 'json':
            onJson();
            break;
          case 'excel':
            onExcel();
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'csv', child: Text('CSV')),
        PopupMenuItem(value: 'json', child: Text('JSON')),
        PopupMenuItem(value: 'excel', child: Text('Excel')),
      ],
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.columns,
    required this.rows,
    required this.firstRowNumber,
  });

  static const double _indexWidth = 52;
  static const double _columnWidth = 128;

  final List<String> columns;
  final List<List<dynamic>> rows;
  final int firstRowNumber;

  @override
  Widget build(BuildContext context) {
    final tableWidth = _indexWidth + (columns.length * _columnWidth);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0B111D),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _ResultRow(
                cells: ['#', ...columns],
                columnNames: columns,
                indexWidth: _indexWidth,
                columnWidth: _columnWidth,
                header: true,
              ),
              Expanded(
                child: rows.isEmpty
                    ? const Center(child: Text('No rows to show.'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, index) {
                          final row = rows[index];
                          return _ResultRow(
                            cells: [
                              '${firstRowNumber + index}',
                              ...List.generate(
                                columns.length,
                                (columnIndex) => columnIndex < row.length
                                    ? row[columnIndex]
                                    : null,
                              ),
                            ],
                            columnNames: columns,
                            indexWidth: _indexWidth,
                            columnWidth: _columnWidth,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.cells,
    required this.columnNames,
    required this.indexWidth,
    required this.columnWidth,
    this.header = false,
  });

  final List<dynamic> cells;
  final List<String> columnNames;
  final double indexWidth;
  final double columnWidth;
  final bool header;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: header ? 44 : 46,
      decoration: BoxDecoration(
        color: header ? const Color(0xFF18243A) : const Color(0xFF0B111D),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.13)),
        ),
      ),
      child: Row(
        children: List.generate(cells.length, (index) {
          return _ResultCell(
            value: cells[index],
            columnName: index == 0 ? null : columnNames[index - 1],
            width: index == 0 ? indexWidth : columnWidth,
            header: header,
            centered: index == 0,
          );
        }),
      ),
    );
  }
}

class _ResultCell extends StatelessWidget {
  const _ResultCell({
    required this.value,
    required this.columnName,
    required this.width,
    required this.header,
    required this.centered,
  });

  final dynamic value;
  final String? columnName;
  final double width;
  final bool header;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final boolValue = _BooleanDisplay.from(value, columnName: columnName);

    return Container(
      width: width,
      height: double.infinity,
      alignment: centered ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: centered ? 6 : 10),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.16)),
        ),
      ),
      child: header
          ? Text(
              value.toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF93E8A7),
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            )
          : boolValue == null
              ? SelectableText(
                  value?.toString() ?? 'NULL',
                  maxLines: 1,
                  style: TextStyle(
                    color: value == null
                        ? Colors.white.withOpacity(0.44)
                        : const Color(0xFFE8EDF5),
                    fontSize: 13,
                    fontWeight: centered ? FontWeight.w800 : FontWeight.w600,
                  ),
                )
              : _BooleanStatusChip(value: boolValue),
    );
  }
}

class _BooleanStatusChip extends StatelessWidget {
  const _BooleanStatusChip({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    final color = value ? const Color(0xFF91D765) : const Color(0xFFFF6B4A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Text(
        value ? 'Active' : 'Inactive',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BooleanDisplay {
  const _BooleanDisplay._();

  static bool? from(dynamic value, {String? columnName}) {
    if (value is bool) return value;
    if (value is num) {
      if (!_isBooleanLikeColumn(columnName)) return null;
      if (value == 1) return true;
      if (value == 0) return false;
    }

    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return null;

    if (const {'true', 't', 'yes', 'y'}.contains(text)) return true;
    if (const {'false', 'f', 'no', 'n'}.contains(text)) return false;
    if (_isBooleanLikeColumn(columnName)) {
      if (text == '1') return true;
      if (text == '0') return false;
    }

    return null;
  }

  static bool _isBooleanLikeColumn(String? columnName) {
    final normalized = columnName?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return false;

    return normalized == 'status' ||
        normalized == 'active' ||
        normalized == 'enabled' ||
        normalized == 'is_active' ||
        normalized == 'isactive' ||
        normalized == 'is_enabled' ||
        normalized == 'isenabled' ||
        normalized.startsWith('is_') ||
        normalized.startsWith('has_');
  }
}

class _ResultsPager extends StatelessWidget {
  const _ResultsPager({
    required this.compact,
    required this.start,
    required this.end,
    required this.total,
    required this.rowsPerPage,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onRowsPerPageChanged,
    required this.onPrevious,
    required this.onNext,
  });

  final bool compact;
  final int start;
  final int end;
  final int total;
  final int rowsPerPage;
  final bool canGoPrevious;
  final bool canGoNext;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(color: Colors.white.withOpacity(0.24), height: 1),
        SizedBox(height: compact ? 4 : 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '$start-$end/$total',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE6EBF4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(
              width: compact ? 74 : 82,
              child: DropdownButton<int>(
                value: rowsPerPage,
                isExpanded: true,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: const TextStyle(
                  color: Color(0xFFE6EBF4),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                items: const [5, 10, 25, 50]
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(compact ? '$value' : '$value rows'),
                    ),
                  )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onRowsPerPageChanged(value);
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left_rounded),
              visualDensity: VisualDensity.compact,
              iconSize: 24,
              tooltip: 'Previous',
            ),
            IconButton(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right_rounded),
              visualDensity: VisualDensity.compact,
              iconSize: 24,
              tooltip: 'Next',
            ),
          ],
        ),
      ],
    );
  }
}

class _QueryTabs extends StatelessWidget {
  const _QueryTabs({required this.selectedIndex, required this.onChanged});
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = QeStrings.tabs;
    return Container(
      height: 48,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)))),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () => onChanged(index),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(labels[index], style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: selected ? Theme.of(context).colorScheme.primary : null)),
                  const SizedBox(height: 8),
                  AnimatedContainer(duration: const Duration(milliseconds: 160), height: 2, width: selected ? 52 : 0, color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(0, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.2),
      ),
      onPressed: onTap,
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(icon, size: 16),
      label: FittedBox(child: Text(label)),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({
    required this.providerLabel,
    required this.objectName,
    required this.schemaName,
  });

  final String providerLabel;
  final String? objectName;
  final String? schemaName;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final objectLabel = _objectLabel;

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1726),
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant.withOpacity(0.36)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 17, color: colors.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              objectLabel == null
                  ? '$providerLabel SQL console'
                  : '$providerLabel · $objectLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: const Color(0xFFD9E6F2),
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.primary.withOpacity(0.28)),
            ),
            child: Text(
              'SQL',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? get _objectLabel {
    final object = objectName?.trim();
    if (object == null || object.isEmpty) return null;

    final schema = schemaName?.trim();
    if (schema == null || schema.isEmpty) return object;

    return '$schema.$object';
  }
}

class _EditorStatusBar extends StatelessWidget {
  const _EditorStatusBar({
    required this.position,
    required this.lineCount,
    required this.characterCount,
    required this.safeMode,
  });

  final String position;
  final int lineCount;
  final int characterCount;
  final bool safeMode;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1726),
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withOpacity(0.36)),
        ),
      ),
      child: Row(
        children: [
          _StatusItem(icon: Icons.my_location_rounded, label: position),
          const SizedBox(width: 12),
          _StatusItem(icon: Icons.notes_rounded, label: '$lineCount lines'),
          const SizedBox(width: 12),
          _StatusItem(
            icon: Icons.data_object_rounded,
            label: '$characterCount chars',
          ),
          const Spacer(),
          Icon(
            safeMode ? Icons.shield_outlined : Icons.warning_amber_rounded,
            size: 15,
            color: safeMode ? colors.secondary : colors.error,
          ),
          const SizedBox(width: 5),
          Text(
            safeMode ? 'Safe' : 'Unsafe',
            style: theme.textTheme.labelSmall?.copyWith(
              color: safeMode ? colors.secondary : colors.error,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: colors.onSurfaceVariant.withOpacity(0.85),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant.withOpacity(0.95),
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
        ),
      ],
    );
  }
}

class _DropDownBox<T> extends StatelessWidget {
  const _DropDownBox({required this.label, required this.value, required this.values, required this.onChanged, this.suffix = ''});
  final String label;
  final T value;
  final List<T> values;
  final ValueChanged<T> onChanged;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
          Expanded(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: values.map((v) => DropdownMenuItem<T>(value: v, child: Text('$v$suffix'))).toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LineNumbers extends StatefulWidget {
  const _LineNumbers({
    required this.controller,
    required this.scrollController,
    required this.lineHeight,
  });

  final TextEditingController controller;
  final ScrollController scrollController;
  final double lineHeight;

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    widget.scrollController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    widget.scrollController.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ('\n'.allMatches(widget.controller.text).length + 1)
        .clamp(1, 999)
        .toInt();
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.5,
          color: colors.onSurfaceVariant.withOpacity(0.78),
          letterSpacing: 0,
        );

    return Container(
      width: 48,
      color: const Color(0xFF091322),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: colors.outlineVariant.withOpacity(0.36)),
          ),
        ),
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(0, -_scrollOffset),
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(
                  count,
                  (index) => SizedBox(
                    height: widget.lineHeight,
                    child: Text('${index + 1}', style: style),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get _scrollOffset {
    if (!widget.scrollController.hasClients) return 0;
    return widget.scrollController.offset;
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 46),
            const SizedBox(height: 12),
            Text(QeStrings.sqlErrorTitle, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            SelectableText(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SqlTextEditingController extends TextEditingController {
  _SqlTextEditingController({
    required this.provider,
    super.text,
  })  : _functionNames = _SqlFunctionCatalog.functionsFor(provider),
        _dataTypeNames = _SqlDataTypeCatalog.dataTypesFor(provider) {
    final keywords = _keywords.map(RegExp.escape).join('|');
    final functions = _functionNames.map(RegExp.escape).join('|');
    final dataTypes = _dataTypeNames.map(RegExp.escape).join('|');
    final wordTokens = [
      functions,
      dataTypes,
      keywords,
    ].where((value) => value.isNotEmpty).join('|');

    _tokenPattern = RegExp(
      "(--[^\\n]*|'(?:''|[^'])*'|\\b(?:$wordTokens)\\b|\\b\\d+(?:\\.\\d+)?\\b)",
      caseSensitive: false,
    );
  }

  static const List<String> _keywords = [
    'SELECT',
    'FROM',
    'WHERE',
    'JOIN',
    'INNER',
    'LEFT',
    'RIGHT',
    'FULL',
    'OUTER',
    'ON',
    'AND',
    'OR',
    'ORDER',
    'BY',
    'GROUP',
    'HAVING',
    'INSERT',
    'INTO',
    'VALUES',
    'UPDATE',
    'SET',
    'DELETE',
    'CREATE',
    'ALTER',
    'DROP',
    'TABLE',
    'VIEW',
    'PROCEDURE',
    'FUNCTION',
    'EXEC',
    'EXECUTE',
    'TOP',
    'LIMIT',
    'OFFSET',
    'AS',
    'DISTINCT',
    'NULL',
    'IS',
    'NOT',
    'BETWEEN',
    'LIKE',
    'IN',
    'DESC',
    'ASC',
  ];

  final DatabaseProvider provider;
  final Set<String> _functionNames;
  final Set<String> _dataTypeNames;
  late final RegExp _tokenPattern;

  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final baseStyle = style ?? const TextStyle();
    final spans = <TextSpan>[];
    var index = 0;

    for (final match in _tokenPattern.allMatches(text)) {
      if (match.start > index) {
        spans.add(TextSpan(text: text.substring(index, match.start), style: baseStyle));
      }
      final token = match.group(0)!;
      spans.add(TextSpan(text: token.toUpperCase(), style: baseStyle.merge(_styleForToken(token, match.end))));
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextStyle _styleForToken(String token, int tokenEnd) {
    if (token.startsWith('--')) return const TextStyle(color: Color(0xFF7A8797), fontStyle: FontStyle.italic);
    if (token.startsWith("'")) return const TextStyle(color: Color(0xFFFFB86C));
    if (RegExp(r'^\d').hasMatch(token)) return const TextStyle(color: Color(0xFFFFD866));
    final normalized = token.toLowerCase();
    if (_functionNames.contains(normalized) && _isFunctionUsage(normalized, tokenEnd)) {
      return const TextStyle(color: Color(0xFFFF4FD8), fontWeight: FontWeight.w800);
    }
    if (_dataTypeNames.contains(normalized)) {
      return const TextStyle(color: Color(0xFF93E8A7), fontWeight: FontWeight.w800);
    }
    return const TextStyle(color: Color(0xFF65B8FF), fontWeight: FontWeight.w700);
  }

  bool _isFunctionUsage(String normalizedToken, int tokenEnd) {
    if (!_keywords.map((value) => value.toLowerCase()).contains(normalizedToken)) {
      return true;
    }

    if (_SqlFunctionCatalog.bareFunctionNames.contains(normalizedToken)) {
      return true;
    }

    var index = tokenEnd;
    while (index < text.length && text[index].trim().isEmpty) {
      index++;
    }

    return index < text.length && text[index] == '(';
  }
}

class _SqlFunctionCatalog {
  const _SqlFunctionCatalog._();

  static const Set<String> bareFunctionNames = {
    'current_date',
    'current_time',
    'current_timestamp',
    'getdate',
    'getutcdate',
    'localtime',
    'localtimestamp',
    'now',
    'sysdate',
    'sysdatetime',
    'sysdatetimeoffset',
    'systimestamp',
    'sysutcdatetime',
  };

  static Set<String> functionsFor(DatabaseProvider provider) {
    switch (provider) {
      case DatabaseProvider.postgresql:
        return _postgresql;
      case DatabaseProvider.sqlServer:
        return _sqlServer;
      case DatabaseProvider.oracle:
        return _oracle;
    }
  }

  static const Set<String> _postgresql = {
    'age',
    'array_append',
    'array_cat',
    'array_length',
    'array_remove',
    'clock_timestamp',
    'current_date',
    'current_time',
    'date_trunc',
    'extract',
    'initcap',
    'jsonb_array_elements',
    'jsonb_build_object',
    'jsonb_each',
    'jsonb_extract_path',
    'jsonb_object_keys',
    'localtime',
    'localtimestamp',
    'lpad',
    'md5',
    'now',
    'position',
    'rpad',
    'to_ascii',
    'to_json',
    'to_jsonb',
    'unnest',
  };

  static const Set<String> _sqlServer = {
    'abs',
    'acos',
    'ascii',
    'app_name',
    'asin',
    'atan',
    'atn2',
    'avg',
    'cast',
    'ceiling',
    'char',
    'charindex',
    'choose',
    'coalesce',
    'col_length',
    'col_name',
    'concat',
    'concat_ws',
    'convert',
    'cos',
    'cot',
    'count',
    'count_big',
    'cume_dist',
    'current_timestamp',
    'dateadd',
    'datediff',
    'datediff_big',
    'datefromparts',
    'datename',
    'datepart',
    'datetime2fromparts',
    'db_id',
    'db_name',
    'degrees',
    'dense_rank',
    'difference',
    'day',
    'eomonth',
    'exp',
    'first_value',
    'floor',
    'format',
    'getdate',
    'getutcdate',
    'host_name',
    'ident_current',
    'ident_incr',
    'ident_seed',
    'iif',
    'isdate',
    'isjson',
    'isnull',
    'json_modify',
    'json_query',
    'json_value',
    'lag',
    'last_value',
    'lead',
    'left',
    'len',
    'log',
    'log10',
    'lower',
    'ltrim',
    'max',
    'min',
    'month',
    'nchar',
    'ntile',
    'nullif',
    'object_id',
    'object_name',
    'openjson',
    'parse',
    'patindex',
    'percent_rank',
    'pi',
    'power',
    'quotename',
    'radians',
    'rand',
    'rank',
    'replace',
    'replicate',
    'reverse',
    'right',
    'row_number',
    'round',
    'rtrim',
    'scope_identity',
    'serverproperty',
    'sign',
    'sin',
    'smalldatetimefromparts',
    'soundex',
    'space',
    'sqrt',
    'square',
    'str',
    'string_agg',
    'string_escape',
    'string_split',
    'stuff',
    'substring',
    'sum',
    'switchoffset',
    'sysdatetime',
    'sysdatetimeoffset',
    'sysutcdatetime',
    'tan',
    'timefromparts',
    'todatetimeoffset',
    'translate',
    'trim',
    'try_cast',
    'try_convert',
    'try_parse',
    'unicode',
    'upper',
    'user_name',
    'year',
  };

  static const Set<String> _oracle = {
    'add_months',
    'instr',
    'last_day',
    'months_between',
    'next_day',
    'nvl',
    'nvl2',
    'regexp_replace',
    'regexp_substr',
    'sysdate',
    'systimestamp',
    'timestamp_to_scn',
    'to_char',
    'to_date',
    'to_number',
  };
}

class _SqlDataTypeCatalog {
  const _SqlDataTypeCatalog._();

  static Set<String> dataTypesFor(DatabaseProvider provider) {
    switch (provider) {
      case DatabaseProvider.postgresql:
        return _postgresql;
      case DatabaseProvider.sqlServer:
        return _sqlServer;
      case DatabaseProvider.oracle:
        return _oracle;
    }
  }

  static const Set<String> _postgresql = {
    'bigint',
    'bigserial',
    'bit',
    'boolean',
    'bytea',
    'char',
    'character',
    'date',
    'decimal',
    'double',
    'inet',
    'int',
    'integer',
    'interval',
    'json',
    'jsonb',
    'money',
    'numeric',
    'real',
    'serial',
    'smallint',
    'smallserial',
    'text',
    'time',
    'timestamp',
    'timestamptz',
    'uuid',
    'varchar',
    'xml',
  };

  static const Set<String> _sqlServer = {
    'bigint',
    'binary',
    'bit',
    'char',
    'date',
    'datetime',
    'datetime2',
    'datetimeoffset',
    'decimal',
    'float',
    'geography',
    'geometry',
    'hierarchyid',
    'image',
    'int',
    'money',
    'nchar',
    'ntext',
    'numeric',
    'nvarchar',
    'real',
    'smalldatetime',
    'smallint',
    'smallmoney',
    'sql_variant',
    'text',
    'time',
    'timestamp',
    'tinyint',
    'uniqueidentifier',
    'varbinary',
    'varchar',
    'xml',
  };

  static const Set<String> _oracle = {
    'bfile',
    'binary_double',
    'binary_float',
    'blob',
    'char',
    'clob',
    'date',
    'float',
    'interval',
    'long',
    'nchar',
    'nclob',
    'number',
    'nvarchar2',
    'raw',
    'rowid',
    'timestamp',
    'urowid',
    'varchar2',
    'xmltype',
  };
}

enum _MessageKind { success, warning, error, info }

class _ParsedMessage {
  const _ParsedMessage({
    required this.dateTime,
    required this.title,
    required this.body,
    required this.kind,
    required this.icon,
  });

  final String dateTime;
  final String title;
  final String body;
  final _MessageKind kind;
  final IconData icon;

  factory _ParsedMessage.fromRaw(String raw) {
    final parts = raw.split(' · ');
    final dateTime = parts.isNotEmpty ? parts.first.trim() : '';
    final message = parts.length > 1 ? parts.sublist(1).join(' · ').trim() : raw.trim();
    final lower = message.toLowerCase();

    if (lower.startsWith('error:')) {
      return _ParsedMessage(
        dateTime: dateTime,
        title: 'Error',
        body: message.replaceFirst(RegExp(r'^ERROR:\s*', caseSensitive: false), ''),
        kind: _MessageKind.error,
        icon: Icons.error_outline_rounded,
      );
    }

    if (lower.contains('disabled') || lower.contains('cancelled') || lower.contains('blocked')) {
      return _ParsedMessage(
        dateTime: dateTime,
        title: 'Warning',
        body: message,
        kind: _MessageKind.warning,
        icon: Icons.warning_amber_rounded,
      );
    }

    if (lower.startsWith('query executed')) {
      return _ParsedMessage(
        dateTime: dateTime,
        title: 'Query executed',
        body: message,
        kind: _MessageKind.success,
        icon: Icons.check_rounded,
      );
    }

    return _ParsedMessage(
      dateTime: dateTime,
      title: 'Message',
      body: message,
      kind: _MessageKind.info,
      icon: Icons.info_outline_rounded,
    );
  }
}

class _HistoryEntry {
  const _HistoryEntry({required this.sql, required this.dateTime, required this.message});
  final String sql;
  final DateTime dateTime;
  final String message;
}

class _QueryEditorSessionSnapshot {
  const _QueryEditorSessionSnapshot({
    required this.sql,
    required this.selectedTab,
    required this.limit,
    required this.timeoutSeconds,
    required this.resultsPage,
    required this.rowsPerPage,
    required this.safeMode,
    required this.lastDuration,
    required this.errorMessage,
    required this.lastSuccessfulSql,
    required this.lastSavedSql,
    required this.result,
    required this.history,
    required this.messages,
  });

  final String sql;
  final int selectedTab;
  final int limit;
  final int timeoutSeconds;
  final int resultsPage;
  final int rowsPerPage;
  final bool safeMode;
  final Duration? lastDuration;
  final String? errorMessage;
  final String? lastSuccessfulSql;
  final String? lastSavedSql;
  final QueryExecuteResult? result;
  final List<_HistoryEntry> history;
  final List<String> messages;
}
