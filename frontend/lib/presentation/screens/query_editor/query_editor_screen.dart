import 'dart:async';

import 'package:dbpilot/models/database_provider.dart';
import 'dart:io';

import 'package:flutter/material.dart';
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

  final _historyService = QueryHistoryStorageService();
  late final _SqlTextEditingController _sqlController;
  late final FocusNode _editorFocusNode;
  late final ScrollController _editorScrollController;
  late final ConnectionApiService _apiService;

  int _selectedTab = 0;
  int _limit = 100;
  int _timeoutSeconds = 30;
  bool _safeMode = true;
  bool _executing = false;
  Duration? _lastDuration;
  String? _errorMessage;
  QueryExecuteResult? _result;
  final List<_HistoryEntry> _history = [];
  final List<String> _messages = [];

  @override
  void initState() {
    super.initState();
    _apiService = ConnectionApiService();
    _editorFocusNode = FocusNode();
    _editorFocusNode.addListener(_refreshEditorChrome);
    _editorScrollController = ScrollController();
    _sqlController = _SqlTextEditingController(text: _initialSql());
    _sqlController.addListener(_refreshEditorChrome);
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

      await _historyService.saveQuery(
        provider: widget.connection.provider.apiValue,
        connectionName: widget.connection.name,
        sql: sqlToExecute,
      );
      
      watch.stop();
      if (!mounted) return;
      setState(() {
        _result = result;
        _lastDuration = watch.elapsed;
        _executing = false;
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

  Future<void> _exportResultsToCsv() async {
    final result = _result;

    if (result == null || result.rows.isEmpty) {
      _addMessage('No rows to export.');
      return;
    }

    try {
      final buffer = StringBuffer();

      buffer.writeln(
        result.columns.map(_csvEscape).join(','),
      );

      for (final row in result.rows) {
        final values = <String>[];

        for (var i = 0; i < result.columns.length; i++) {
          final value = i < row.length ? row[i] : '';
          values.add(_csvEscape(value));
        }

        buffer.writeln(values.join(','));
      }

      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .replaceAll('-', '')
          .replaceAll('T', '_');

      final file = File('${directory.path}/results_$timestamp.csv');
      await file.writeAsString(buffer.toString(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Query results CSV',
      );

      _addMessage('CSV exported successfully.');
    } catch (error) {
      _addMessage('CSV export failed: $error');
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

    return Scaffold(
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
    );
  }

  Widget _buildEditor(ThemeData theme, ColorScheme colors) {
    return Column(
      children: [
        _buildToolbar(theme, colors),
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
          Expanded(child: _ToolbarButton(icon: Icons.save_outlined, label: QeStrings.saveQuery, onTap: () => _addMessage(QeStrings.localSavePending))),
          const SizedBox(width: 6),
          Expanded(child: _ToolbarButton(icon: Icons.folder_open_rounded, label: QeStrings.loadQuery, onTap: _showLoadQueryDialog,)),
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _executing ? null : _execute,
                icon: _executing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded),
                label: const Text(QeStrings.executeQuery),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, ColorScheme colors) {
    if (_executing) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return _ErrorPanel(message: _errorMessage!);
    final result = _result;
    if (result == null) return const _EmptyPanel(icon: Icons.table_chart_outlined, title: QeStrings.noResultsTitle, message: QeStrings.noResultsMessage);
    if (result.columns.isEmpty) return _EmptyPanel(icon: Icons.check_circle_outline_rounded, title: QeStrings.queryExecutedTitle, message: result.message.isEmpty ? QeStrings.commandExecuted : result.message);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(color: colors.primaryContainer.withOpacity(0.18), border: Border(bottom: BorderSide(color: colors.outlineVariant.withOpacity(0.45)))),
          child: Row(
            children: [
              Expanded(child: Text('Results — ${result.rowCount} rows${_lastDuration == null ? '' : ' in ${(_lastDuration!.inMilliseconds / 1000).toStringAsFixed(2)} sec'}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: Colors.greenAccent.shade200))),
              IconButton(onPressed: (_result == null || _result!.rows.isEmpty)
                      ? null
                      : _exportResultsToCsv, icon: const Icon(Icons.download_rounded)),
              IconButton(onPressed: _executing ? null : _execute, icon: const Icon(Icons.refresh_rounded)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(colors.surfaceContainerHighest.withOpacity(0.65)),
                dataRowColor: MaterialStateProperty.all(colors.primaryContainer.withOpacity(0.10)),
                border: TableBorder.all(color: colors.outlineVariant.withOpacity(0.35), width: 0.8),
                headingRowHeight: 44,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 58,
                columns: [
                  DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.greenAccent.shade200))),
                  ...result.columns.map((c) => DataColumn(label: Text(c, style: TextStyle(fontWeight: FontWeight.w900, color: Colors.greenAccent.shade200)))),
                ],
                rows: List.generate(result.rows.length, (index) {
                  final row = result.rows[index];
                  return DataRow(cells: [
                    DataCell(Text('${index + 1}', style: TextStyle(color: colors.onSurfaceVariant))),
                    ...row.map((v) => DataCell(SelectableText(v?.toString() ?? 'NULL'))),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ],
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
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text(QeStrings.executeQuery)),
        ],
      ),
    );
    return result == true;
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
  const _ToolbarButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
      icon: Icon(icon, size: 16),
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
  _SqlTextEditingController({super.text});

  static final RegExp _tokenPattern = RegExp(
    r"(--[^\n]*|'(?:''|[^'])*'|\b(?:SELECT|FROM|WHERE|JOIN|INNER|LEFT|RIGHT|FULL|OUTER|ON|AND|OR|ORDER|BY|GROUP|HAVING|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|ALTER|DROP|TABLE|VIEW|PROCEDURE|FUNCTION|EXEC|EXECUTE|TOP|LIMIT|OFFSET|AS|DISTINCT|NULL|IS|NOT|BETWEEN|LIKE|IN|DESC|ASC)\b|\b\d+(?:\.\d+)?\b)",
    caseSensitive: false,
  );

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
      spans.add(TextSpan(text: token.toUpperCase(), style: baseStyle.merge(_styleForToken(token))));
      index = match.end;
    }

    if (index < text.length) {
      spans.add(TextSpan(text: text.substring(index), style: baseStyle));
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  TextStyle _styleForToken(String token) {
    if (token.startsWith('--')) return const TextStyle(color: Color(0xFF7A8797), fontStyle: FontStyle.italic);
    if (token.startsWith("'")) return const TextStyle(color: Color(0xFFFFB86C));
    if (RegExp(r'^\d').hasMatch(token)) return const TextStyle(color: Color(0xFFFFD866));
    return const TextStyle(color: Color(0xFF65B8FF), fontWeight: FontWeight.w700);
  }
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
