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
  late final TextEditingController _sqlController;
  late final FocusNode _editorFocusNode;
  late final ConnectionApiService _apiService;

  int _selectedTab = 0;
  int _limit = 100;
  int _timeoutSeconds = 30;
  bool _transactionEnabled = false;
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
    _sqlController = TextEditingController(text: _initialSql());
  }

  String _initialSql() {
    final sql = widget.initialSql?.trim();
    if (sql != null && sql.isNotEmpty) return sql;

    final provider = widget.connection.provider.apiValue;
    final objectName = widget.objectName?.trim();
    final schemaName = widget.schemaName?.trim();

    if (objectName == null || objectName.isEmpty) {
      return '';
    }

    final qualifiedName = (schemaName != null && schemaName.isNotEmpty)
        ? '$schemaName.$objectName'
        : objectName;

    if (provider == 'postgresql') {
      return 'SELECT *\nFROM $qualifiedName\nLIMIT 50;';
    }

    if (provider == 'sqlserver' || provider == 'sql_server' || provider == 'mssql') {
      return 'SELECT TOP 50 *\nFROM $qualifiedName;';
    }

    if (provider == 'oracle') {
      return 'SELECT *\nFROM $qualifiedName\nWHERE ROWNUM <= 50;';
    }

    return 'SELECT *\nFROM $qualifiedName;';
  }

  Future<void> _execute() async {
    final sql = _cleanSql(_sqlController.text);
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
      _addMessage(QeStrings.queryExecuted(watch.elapsedMilliseconds, result.rowCount));
    } catch (error) {
      watch.stop();
      if (!mounted) return;
      setState(() {
        _executing = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
        _selectedTab = 2;
      });
      _addMessage('ERROR: ${error.toString().replaceFirst('Exception: ', '')}');
    }
  }

  void _addMessage(String message) {
    setState(() {
      _messages.insert(0, '${TimeOfDay.now().format(context)} · $message');
      if (_messages.length > 100) _messages.removeLast();
    });
  }

  void _formatSql() {
    var sql = _cleanSql(_sqlController.text);
    final replacements = <String, String>{
      ' select ': '\nSELECT ',
      ' from ': '\nFROM ',
      ' where ': '\nWHERE ',
      ' join ': '\nJOIN ',
      ' inner join ': '\nINNER JOIN ',
      ' left join ': '\nLEFT JOIN ',
      ' right join ': '\nRIGHT JOIN ',
      ' group by ': '\nGROUP BY ',
      ' order by ': '\nORDER BY ',
      ' having ': '\nHAVING ',
      ' values ': '\nVALUES ',
      ' set ': '\nSET ',
    };
    sql = ' $sql ';
    replacements.forEach((key, value) {
      sql = sql.replaceAll(RegExp(key, caseSensitive: false), value);
    });
    _sqlController.text = sql.trim();
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
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
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
          IconButton(onPressed: _formatSql, icon: const Icon(Icons.auto_fix_high_rounded), tooltip: 'Format SQL'),
          IconButton(onPressed: _clearEditor, icon: const Icon(Icons.delete_sweep_rounded), tooltip: 'Clear'),
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
                  _buildEditor(theme, colors, keyboardOpen),
                  _buildResults(theme, colors),
                  _buildMessages(theme, colors),
                  _buildHistory(theme, colors),
                ],
              ),
            ),
            Visibility(
              visible: !keyboardOpen,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: false,
              child: _buildBottomBar(theme, colors),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, ColorScheme colors, bool keyboardOpen) {
    return Column(
      children: [
        Visibility(
          visible: !keyboardOpen,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: _buildToolbar(theme, colors),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withOpacity(0.35),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _editorFocusNode.requestFocus(),
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
                      onTapOutside: (_) {},
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', height: 1.45),
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
        ),
        Visibility(
          visible: !keyboardOpen,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: false,
          child: _buildQuickKeys(colors),
        ),
      ],
    );
  }

  Widget _buildToolbar(ThemeData theme, ColorScheme colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          _ToolbarButton(icon: Icons.auto_fix_high_rounded, label: QeStrings.formatSql, onTap: _formatSql),
          const SizedBox(width: 8),
          _ToolbarButton(icon: Icons.save_outlined, label: QeStrings.saveQuery, onTap: () => _addMessage(QeStrings.localSavePending)), 
          const SizedBox(width: 8),
          _ToolbarButton(icon: Icons.folder_open_rounded, label: QeStrings.loadQuery, onTap: () => setState(() => _selectedTab = 3)),

        ],
      ),
    );
  }

  Widget _buildQuickKeys(ColorScheme colors) {
    const keys = ['SELECT', 'FROM', 'WHERE', 'JOIN', 'AND', 'OR', 'GROUP BY', 'ORDER BY', 'LIMIT', 'TOP'];
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
                color: _safeMode
                    ? colors.surfaceContainerHighest.withOpacity(0.45)
                    : colors.errorContainer.withOpacity(0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _safeMode
                      ? colors.outlineVariant.withOpacity(0.5)
                      : colors.error.withOpacity(0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _safeMode ? Icons.shield_outlined : Icons.warning_amber_rounded,
                    color: _safeMode ? colors.primary : colors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(QeStrings.safeMode, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          _safeMode ? QeStrings.safeModeOnDescription : QeStrings.safeModeOffDescription,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _safeMode,
                    onChanged: (value) => setState(() => _safeMode = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DropDownBox<int>(
                    label: QeStrings.limit,
                    value: _limit,
                    values: const [50, 100, 250, 500],
                    onChanged: (v) { setState(() => _limit = v); _editorFocusNode.requestFocus(); },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DropDownBox<int>(
                    label: QeStrings.timeout,
                    value: _timeoutSeconds,
                    values: const [10, 30, 60],
                    suffix: 's',
                    onChanged: (v) { setState(() => _timeoutSeconds = v); _editorFocusNode.requestFocus(); },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _executing ? null : _execute,
                icon: _executing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text(QeStrings.executeQuery),
              ),
            ),
          ],
        ),
      ),
    );
  }


  String _cleanSql(String sql) {
    return sql
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200B', '')
        .replaceAll('\u200C', '')
        .replaceAll('\u200D', '')
        .replaceAll('\u00A0', ' ')
        .trim();
  }

  bool _isDataModificationStatement(String sql) {
    final firstWord = _firstSqlWord(sql);
    return const {
      'insert',
      'update',
      'delete',
      'merge',
      'create',
      'alter',
      'drop',
      'truncate',
      'exec',
      'execute',
    }.contains(firstWord);
  }

  bool _isDangerousStatement(String sql) {
    final firstWord = _firstSqlWord(sql);
    return const {'insert', 'update', 'delete', 'merge', 'drop', 'truncate', 'alter', 'create', 'exec', 'execute'}
        .contains(firstWord);
  }

  String _firstSqlWord(String sql) {
    var cleaned = _cleanSql(sql).trimLeft();
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
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(QeStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(QeStrings.executeQuery),
          ),
        ],
      ),
    );
    return result == true;
  }

Widget _buildResults(ThemeData theme, ColorScheme colors) {
  if (_executing) {
    return const Center(child: CircularProgressIndicator());
  }
  if (_errorMessage != null) {
    return _ErrorPanel(message: _errorMessage!);
  }
  final result = _result;
  if (result == null) {
    return const _EmptyPanel(
      icon: Icons.table_chart_outlined,
      title: QeStrings.noResultsTitle,
      message: QeStrings.noResultsMessage,
    );
  }
  if (result.columns.isEmpty) {
    return _EmptyPanel(
      icon: Icons.check_circle_outline_rounded,
      title: QeStrings.queryExecutedTitle,
      message: result.message.isEmpty ? QeStrings.commandExecuted : result.message,
    );
  }
 // Palette — matches dark screenshot
  const Color colHeader  = Color(0xFF53D39A); // green column names
  const Color rowNumCol  = Color(0xFF53D39A); // green # column
  const Color bgEven     = Color(0xFF111E2C);
  const Color bgOdd      = Color(0xFF0E1824);
  const Color borderCol  = Color(0x18FFFFFF);
  const Color txtCol     = Color(0xFFCDD6E0);
  const Color headerBg   = Color(0xFF0C1520);
 
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // ── Result summary bar ──
      Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: const BoxDecoration(
          color: headerBg,
          border: Border(bottom: BorderSide(color: borderCol)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Results — ${result.rowCount} rows${_lastDuration == null ? '' : ' in ${(_lastDuration!.inMilliseconds / 1000).toStringAsFixed(2)} sec'}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colHeader,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // navigation arrows
            _SmallIconBtn(icon: Icons.chevron_left_rounded, onTap: () {}),
            const SizedBox(width: 4),
            _SmallIconBtn(icon: Icons.chevron_right_rounded, onTap: () {}),
            const SizedBox(width: 8),
            _SmallIconBtn(
              icon: Icons.download_rounded,
              onTap: () => _addMessage(QeStrings.exportCsvPending),
            ),
          ],
        ),
      ),
 
      // ── Scrollable table ──
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.symmetric(
                inside: const BorderSide(color: borderCol, width: 0.5),
              ),
              children: [
                // Header row
                TableRow(
                  decoration: const BoxDecoration(color: headerBg),
                  children: [
                    // row-number header
                    _tableCell(
                      child: const Text('#',
                          style: TextStyle(
                              color: rowNumCol,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                      isHeader: true,
                    ),
                    ...result.columns.map(
                      (c) => _tableCell(
                        child: Text(
                          c,
                          style: const TextStyle(
                            color: colHeader,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        isHeader: true,
                      ),
                    ),
                  ],
                ),
                // Data rows
                ...result.rows.asMap().entries.map((entry) {
                  final idx  = entry.key;
                  final row  = entry.value;
                  final bg   = idx.isEven ? bgEven : bgOdd;
                  return TableRow(
                    decoration: BoxDecoration(color: bg),
                    children: [
                      // row number
                      _tableCell(
                        child: Text(
                          '${idx + 1}',
                          style: const TextStyle(
                              color: Color(0xFF3C4E60), fontSize: 11),
                        ),
                      ),
                      ...row.map(
                        (v) => _tableCell(
                          child: SelectableText(
                            v?.toString() ?? 'NULL',
                            style: const TextStyle(
                                color: txtCol, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
 
/// Shared table cell helper
Widget _tableCell({required Widget child, bool isHeader = false}) {
  return Padding(
    padding: EdgeInsets.symmetric(
      horizontal: 12,
      vertical: isHeader ? 10 : 8,
    ),
    child: child,
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
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final raw     = _messages[index];
      final isError = raw.contains('ERROR');
 
      // Parse: "HH:MM · message body"
      final dotIdx  = raw.indexOf(' · ');
      final time    = dotIdx > 0 ? raw.substring(0, dotIdx) : '';
      final body    = dotIdx > 0 ? raw.substring(dotIdx + 3) : raw;
 
      final cardBg     = isError
          ? const Color(0xFF2A0E0E)
          : const Color(0xFF0D2318);
      final borderCol  = isError
          ? const Color(0x44FF5F57)
          : const Color(0x4453D39A);
      final titleColor = isError
          ? const Color(0xFFFF6B6B)
          : const Color(0xFF53D39A);
      final titleIcon  = isError ? '✗' : '✓';
      final titleText  = isError
          ? QeStrings.sqlErrorTitle
          : QeStrings.queryExecutedTitle;
 
      // Build detail lines shown inside the card
      final List<String> details = [];
      if (time.isNotEmpty) details.add(time);
      details.add(body);
 
      // If it's a success message we also show Limit / Timeout
      if (!isError && body.startsWith('Query executed')) {
        details.add('Limit: $_limit · Timeout: ${_timeoutSeconds}s');
      }
 
      return Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderCol),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title line
            Text(
              '$titleIcon $titleText',
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            // Detail lines in monospace
            ...details.map(
              (line) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  line,
                  style: const TextStyle(
                    color: Color(0xFF8A9BB0),
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
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
 
  const Color cardBg    = Color(0xFF131F2E);
  const Color borderCol = Color(0x14FFFFFF);
  const Color labelCol  = Color(0xFF3C4E60);
  const Color sqlCol    = Color(0xFFCDD6E0);
  const Color loadCol   = Color(0xFF53D39A);
 
  return ListView.separated(
    padding: const EdgeInsets.all(12),
    itemCount: _history.length,
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (context, index) {
      final entry      = _history[index];
      final queryNum   = _history.length - index; // newest = highest number
      final timeLabel  =
          '${entry.dateTime.hour.toString().padLeft(2, '0')}:'
          '${entry.dateTime.minute.toString().padLeft(2, '0')}';
 
      return GestureDetector(
        onTap: () => _loadHistory(entry),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderCol),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Query #N  ·  HH:MM"
              Row(
                children: [
                  Text(
                    'Query #$queryNum',
                    style: const TextStyle(
                      color: labelCol,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                      color: labelCol,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // SQL — monospace, up to 4 lines
              Text(
                entry.sql,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: sqlCol,
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              // "↩ Load query"
              GestureDetector(
                onTap: () => _loadHistory(entry),
                child: const Text(
                  '↩  Load query',
                  style: TextStyle(
                    color: loadCol,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
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
  const _ToolbarButton({required this.icon, required this.label, required this.onTap, this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) return FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label));
    return OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label));
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
          DropdownButton<T>(
            value: value,
            underline: const SizedBox.shrink(),
            items: values.map((v) => DropdownMenuItem<T>(value: v, child: Text('$v$suffix'))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
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
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          height: 1.45,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return Container(
      width: 42,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4)),
        ),
      ),
      child: ClipRect(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 14, right: 8),
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(
              count,
              (index) => SizedBox(
                height: 20,
                child: Text('${index + 1}', style: style),
              ),
            ),
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

class _HistoryEntry {
  const _HistoryEntry({required this.sql, required this.dateTime, required this.message});
  final String sql;
  final DateTime dateTime;
  final String message;
}

class _SmallIconBtn extends StatelessWidget {
  const _SmallIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
 
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF1A2638),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x18FFFFFF)),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF8A9BB0)),
      ),
    );
  }
}
