import 'dart:async';

import 'package:dbpilot/models/database_provider.dart';
import 'package:flutter/material.dart';
import '../../../models/connection_request.dart';
import '../../../services/connection_api_service.dart';
import '../../../core/strings/strings.dart';

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
  late final _SqlTextEditingController _sqlController;
  late final FocusNode _editorFocusNode;
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
    _sqlController = _SqlTextEditingController(text: _initialSql());
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
    try {
      final result = await _apiService.executeQuery(
        widget.connection,
        sql,
        limit: _limit,
        allowDataModification: !_safeMode,
        timeoutSeconds: _timeoutSeconds,
      ).timeout(Duration(seconds: _timeoutSeconds));

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
          IconButton(onPressed: _formatSql, icon: const Icon(Icons.auto_fix_high_rounded), tooltip: QeStrings.formatSql),
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
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LineNumbers(controller: _sqlController),
                Expanded(
                  child: TextField(
                    focusNode: _editorFocusNode,
                    controller: _sqlController,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    autocorrect: false,
                    enableSuggestions: false,
                    scrollPadding: const EdgeInsets.only(bottom: 180),
                    onTapOutside: (_) {},
                    style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.45, letterSpacing: 0.2),
                    decoration: const InputDecoration(
                      hintText: QeStrings.sqlHint,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.fromLTRB(12, 14, 12, 14),
                    ),
                  ),
                ),
              ],
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
          Expanded(child: _ToolbarButton(icon: Icons.folder_open_rounded, label: QeStrings.loadQuery, onTap: () => setState(() => _selectedTab = 3))),
        ],
      ),
    );
  }

  Widget _buildQuickKeys(ColorScheme colors) {
    const keys = ['SELECT', 'FROM', 'WHERE', 'JOIN', 'AND', 'OR', 'GROUP BY', 'ORDER BY'];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: keys.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final value = keys[index];
          return ActionChip(
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
              IconButton(onPressed: () => _addMessage(QeStrings.exportCsvPending), icon: const Icon(Icons.download_rounded)),
              IconButton(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh_rounded)),
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
  const _LineNumbers({required this.controller});
  final TextEditingController controller;

  @override
  State<_LineNumbers> createState() => _LineNumbersState();
}

class _LineNumbersState extends State<_LineNumbers> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = ('\n'.allMatches(widget.controller.text).length + 1).clamp(1, 999).toInt();
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.45, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Container(
      width: 42,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4)))),
      child: ClipRect(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 14, right: 8),
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(count, (index) => SizedBox(height: 20, child: Text('${index + 1}', style: style))),
          ),
        ),
      ),
    );
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
      spans.add(TextSpan(text: token, style: baseStyle.merge(_styleForToken(token))));
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
