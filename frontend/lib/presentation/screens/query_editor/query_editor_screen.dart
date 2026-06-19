import 'dart:async';
import 'dart:convert';

import 'package:dbpilot/models/database_provider.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
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

  static void clearSessionCache() {
    _QueryEditorScreenState._sessionSnapshots.clear();
  }

  @override
  State<QueryEditorScreen> createState() => _QueryEditorScreenState();
}

class _QueryEditorScreenState extends State<QueryEditorScreen> {
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
  double _editorFontSize = 14;
  bool _safeMode = true;
  bool _confirmDangerousQueries = true;
  bool _showLineNumbers = true;
  bool _autoFormatOnLoad = false;
  bool _exportHeaders = true;
  bool _executing = false;
  bool _savingExecutedQuery = false;
  bool _allowPopAfterPendingSaveAttempt = false;
  Future<void>? _savingExecutedQueryFuture;
  Duration? _lastDuration;
  String? _errorMessage;
  String? _lastSuccessfulSql;
  String? _lastSavedSql;
  String _csvSeparator = ',';
  String _editorTheme = 'Dark';
  String _defaultExportFormat = 'CSV';
  QueryExecuteResult? _result;
  final List<_HistoryEntry> _history = [];
  final List<String> _messages = [];

  String get _sessionKey => [
        widget.connection.provider.apiValue,
        widget.connection.name,
        widget.connectionSummary,
      ].join('|');

  double get _effectiveEditorLineHeight => _editorFontSize * 1.5;

  bool get _isHighContrastEditor => _editorTheme.toLowerCase().contains('contrast');

  Color get _editorBackgroundColor => _isHighContrastEditor ? const Color(0xFF000000) : const Color(0xFF07101B);

  Color get _editorTextColor => _isHighContrastEditor ? Colors.white : const Color(0xFFD6E2F0);

  Color _editorBorderColor(ColorScheme colors) {
    if (_editorFocusNode.hasFocus) {
      return _isHighContrastEditor ? const Color(0xFFFFD866) : colors.primary.withOpacity(0.75);
    }
    return _isHighContrastEditor ? Colors.white.withOpacity(0.42) : colors.outlineVariant.withOpacity(0.55);
  }

  @override
  void initState() {
    super.initState();
    _apiService = ConnectionApiService();
    _editorFocusNode = FocusNode();
    _editorFocusNode.addListener(_refreshEditorChrome);
    _editorScrollController = ScrollController();
    final snapshot = _sessionSnapshots[_sessionKey];
    final hasInitialSql = widget.initialSql?.trim().isNotEmpty == true;
    _sqlController = _SqlTextEditingController(
      provider: widget.connection.provider,
      text: !hasInitialSql && snapshot?.sql.trim().isNotEmpty == true
          ? snapshot!.sql
          : _initialSql(),
    );
    if (snapshot != null) {
      _selectedTab = hasInitialSql ? 0 : snapshot.selectedTab;
      _limit = snapshot.limit;
      _timeoutSeconds = snapshot.timeoutSeconds;
      _resultsPage = snapshot.resultsPage;
      _rowsPerPage = snapshot.rowsPerPage;
      _editorFontSize = snapshot.editorFontSize;
      _safeMode = snapshot.safeMode;
      _showLineNumbers = snapshot.showLineNumbers;
      _exportHeaders = snapshot.exportHeaders;
      _csvSeparator = snapshot.csvSeparator;
      _lastSuccessfulSql = snapshot.lastSuccessfulSql;
      _lastSavedSql = snapshot.lastSavedSql;
      _history
        ..clear()
        ..addAll(snapshot.history);
      _messages
        ..clear()
        ..addAll(snapshot.messages);
    }
    _loadEditorSettings();
  }

  Future<void> _loadEditorSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _safeMode = prefs.getBool('settings.defaultSafeMode') ?? true;
      _timeoutSeconds = prefs.getInt('settings.defaultTimeout') ?? 30;
      _limit = prefs.getInt('settings.defaultLimit') ?? 100;
      _editorFontSize = prefs.getDouble('settings.editorFontSize') ?? 14;
      _confirmDangerousQueries = prefs.getBool('settings.confirmDangerousQueries') ?? true;
      _showLineNumbers = prefs.getBool('settings.showLineNumbers') ?? true;
      _autoFormatOnLoad = prefs.getBool('settings.autoFormatOnLoad') ?? false;
      _exportHeaders = prefs.getBool('settings.exportHeaders') ?? true;
      _csvSeparator = prefs.getString('settings.csvSeparator') ?? ',';
      _editorTheme = prefs.getString('settings.editorTheme') ?? 'Dark';
      _defaultExportFormat = prefs.getString('settings.defaultExportFormat') ?? 'CSV';
      _sqlController.highContrast = _isHighContrastEditor;
    });

    if (_autoFormatOnLoad && _sqlController.text.trim().isNotEmpty) {
      _formatSql(showMessage: false, requestFocus: false);
    }
  }

  void _setSafeMode(bool value) {
    setState(() => _safeMode = value);
  }

  void _setLimit(int value) {
    setState(() => _limit = value);
  }

  void _setTimeoutSeconds(int value) {
    setState(() => _timeoutSeconds = value);
  }

  void _refreshEditorChrome() {
    if (mounted) setState(() {});
  }

  String _initialSql() {
    final sql = widget.initialSql?.trim();
    if (sql != null && sql.isNotEmpty) return sql;

    final objectName = widget.objectName?.trim();
    final schemaName = widget.schemaName?.trim();
    final objectType = widget.objectType?.trim();

    if (objectName == null || objectName.isEmpty) return '';

    return _defaultObjectQuery(
      provider: widget.connection.provider,
      objectName: objectName,
      objectType: objectType,
      schemaName: schemaName,
    );
  }

  String _defaultObjectQuery({
    required DatabaseProvider provider,
    required String objectName,
    required String? objectType,
    required String? schemaName,
  }) {
    final type = (objectType ?? '').toLowerCase().replaceAll(' ', '_');

    switch (provider) {
      case DatabaseProvider.sqlServer:
        final qualified = _sqlServerQualifiedName(objectName, schemaName);
        if (type == 'procedure' || type == 'stored_procedure') return 'EXEC $qualified;';
        if (type == 'function') return 'SELECT *\nFROM $qualified();';
        if (type == 'trigger') return '-- Trigger $qualified. Open definition to inspect trigger source.';
        return 'SELECT *\nFROM $qualified;';
      case DatabaseProvider.postgresql:
        final qualified = _quotedQualifiedName(objectName, schemaName ?? 'public', '"');
        if (type == 'function') return 'SELECT *\nFROM $qualified();';
        if (type == 'procedure' || type == 'stored_procedure') return 'CALL $qualified();';
        if (type == 'extension') return '-- Extension $objectName. No preview query available.';
        return 'SELECT *\nFROM $qualified;';
      case DatabaseProvider.oracle:
        final qualified = _oracleQualifiedName(objectName, schemaName);
        if (type == 'procedure' || type == 'stored_procedure') return 'BEGIN\n  $qualified;\nEND;';
        if (type == 'function') return 'SELECT $qualified() AS VALUE\nFROM dual;';
        if (type == 'package') return '-- Package $qualified. Open definition to inspect package source.';
        if (type == 'trigger') return '-- Trigger $qualified. Open definition to inspect trigger source.';
        if (type == 'sequence') return 'SELECT $qualified.NEXTVAL AS NEXT_VALUE\nFROM dual;';
        return 'SELECT *\nFROM $qualified;';
    }
  }

  String _sqlServerQualifiedName(String objectName, String? schemaName) {
    String clean(String value) => value.replaceAll('[', '').replaceAll(']', '').trim();
    final schema = clean((schemaName == null || schemaName.trim().isEmpty) ? 'dbo' : schemaName);
    return '[${clean(schema)}].[${clean(objectName)}]';
  }

  String _quotedQualifiedName(String objectName, String schemaName, String quote) {
    String clean(String value) => value.replaceAll(quote, quote + quote).trim();
    final schema = clean(schemaName);
    final name = clean(objectName);
    return schema.isEmpty ? '$quote$name$quote' : '$quote$schema$quote.$quote$name$quote';
  }

  String _oracleQualifiedName(String objectName, String? schemaName) {
    final schema = schemaName?.trim().toUpperCase() ?? '';
    final name = objectName.trim().toUpperCase();
    return _quotedQualifiedName(name, schema, '"');
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

    if (!_safeMode && _confirmDangerousQueries && _isDangerousStatement(sql)) {
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
      _result = null;
      _lastDuration = null;
      _resultsPage = 0;
      _selectedTab = 1;
    });

    final watch = Stopwatch()..start();

    String sqlToExecute = sql.trim();

    if (widget.connection.provider == DatabaseProvider.oracle) {
      sqlToExecute = _prepareOracleSql(sqlToExecute);
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

  String _prepareOracleSql(String sql) {
    final clean = sql.trim();
    final lower = clean.toLowerCase();
    final refCursorBindPattern = RegExp(r':RC\b', caseSensitive: false);
    if (lower.startsWith('begin') || lower.startsWith('declare')) {
      final block = clean.endsWith(';') ? clean : '$clean;';
      if (lower.startsWith('begin') && refCursorBindPattern.hasMatch(block)) {
        final localCursorBlock = block.replaceAll(refCursorBindPattern, 'RC');
        final returnedCursorBlock = localCursorBlock.replaceFirst(
          RegExp(r'\bEND\s*;\s*$', caseSensitive: false),
          '  DBMS_SQL.RETURN_RESULT(RC);\nEND;',
        );
        return 'DECLARE\n  RC SYS_REFCURSOR;\n$returnedCursorBlock';
      }
      return block;
    }
    return clean.replaceFirst(RegExp(r';+\s*$'), '');
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

  String _resultsAsDelimitedText(
    QueryExecuteResult result,
    String separator, {
    bool includeHeaders = true,
  }) {
    final buffer = StringBuffer();
    if (includeHeaders) {
      buffer.writeln(result.columns.map(_csvEscape).join(separator));
    }

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
      ClipboardData(text: _resultsAsDelimitedText(result, '\t', includeHeaders: _exportHeaders)),
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
        content: _resultsAsDelimitedText(result, _csvSeparator, includeHeaders: _exportHeaders),
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
        content: _resultsAsDelimitedText(result, '\t', includeHeaders: _exportHeaders),
        fileName: 'results_${_exportTimestamp()}.xls',
        shareText: 'Query results Excel',
      );

      _addMessage('Excel export generated successfully.');
    } catch (error) {
      _addMessage('Excel export failed: $error');
    }
  }

  Future<void> _exportResultsDefault() async {
    switch (_defaultExportFormat.toUpperCase()) {
      case 'JSON':
        await _exportResultsToJson();
        break;
      case 'EXCEL':
        await _exportResultsToExcel();
        break;
      case 'CSV':
      default:
        await _exportResultsToCsv();
        break;
    }
  }

  Future<void> _showLoadQueryDialog() async {
    final providerQueries = await _historyService.getQueries(
      provider: widget.connection.provider.apiValue,
    );
    final currentConnectionName = widget.connection.name.trim().toLowerCase();
    final queries = providerQueries
        .where((query) => query.connectionName.trim().toLowerCase() == currentConnectionName)
        .toList();

    if (!mounted) return;

    if (queries.isEmpty) {
      _addMessage('No saved queries found for ${widget.connection.name}.');
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

  Future<void> _showSqlBuilderSheet() async {
    final promptController = TextEditingController();
    final speech = stt.SpeechToText();
    var promptText = '';
    var listening = false;
    var speechAvailable = false;
    String? error;
    _LocalSqlBuildResult? generated;

    final sqlToInsert = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colors = theme.colorScheme;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> toggleDictation() async {
              if (listening) {
                await speech.stop();
                setSheetState(() => listening = false);
                return;
              }

              speechAvailable = await speech.initialize(
                onStatus: (status) {
                  if (!context.mounted) return;
                  setSheetState(() => listening = status == 'listening');
                },
                onError: (speechError) {
                  if (!context.mounted) return;
                  setSheetState(() {
                    listening = false;
                    error = speechError.errorMsg;
                  });
                },
              );

              if (!speechAvailable) {
                setSheetState(() {
                  error = 'Speech recognition is not available on this device.';
                });
                return;
              }

              setSheetState(() {
                error = null;
                listening = true;
              });

              await speech.listen(
                localeId: 'en_US',
                listenMode: stt.ListenMode.dictation,
                onResult: (result) {
                  promptText = result.recognizedWords;
                  promptController.value = TextEditingValue(
                    text: promptText,
                    selection: TextSelection.collapsed(offset: promptText.length),
                  );
                },
              );
            }

            void buildSql() {
              final prompt = promptText.trim();
              if (prompt.isEmpty) return;

              final result = _LocalSqlGenerator.generate(
                prompt: prompt,
                provider: widget.connection.provider,
                fallbackTable: widget.objectName,
                fallbackSchema: widget.schemaName,
              );

              setSheetState(() {
                generated = result.sql == null ? null : result;
                error = result.sql == null ? result.message : null;
              });
            }

            void insertSql() {
              final sql = generated?.sql?.trim();
              if (sql == null || sql.isEmpty) return;

              Navigator.of(sheetContext).pop(sql);
            }

            final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
            final resultMaxHeight = keyboardInset > 0 ? 130.0 : 220.0;

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: keyboardInset + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.construction_rounded, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Build SQL',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'English only. SELECT, INSERT, UPDATE, DELETE, WHERE, ORDER BY and LIMIT requests are supported.',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: promptController,
                      onChanged: (value) => promptText = value,
                      minLines: 3,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Example: update table customers set status active where id equals 10',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: toggleDictation,
                        icon: Icon(listening ? Icons.mic_rounded : Icons.mic_none_rounded),
                        label: Text(listening ? 'Listening...' : 'Dictate'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: buildSql,
                        icon: const Icon(Icons.build_rounded),
                        label: const Text('Build SQL'),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(error!, style: TextStyle(color: colors.error)),
                    ],
                    if (generated != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        constraints: BoxConstraints(maxHeight: resultMaxHeight),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF07101B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.outlineVariant.withOpacity(0.5)),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            generated!.sql!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                      if (generated!.message.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          generated!.message,
                          style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: insertSql,
                              child: const Text('Insert SQL'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    await speech.stop();
    Future<void>.delayed(const Duration(milliseconds: 250), promptController.dispose);

    if (!mounted || sqlToInsert == null || sqlToInsert.trim().isEmpty) return;

    _sqlController.text = sqlToInsert.trim();
    setState(() => _selectedTab = 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocusNode.requestFocus();
      _addMessage('SQL generated locally. Review it before running.');
    });
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(hour12)}:${two(value.minute)} $period';
  }

  void _formatSql({bool showMessage = true, bool requestFocus = true}) {
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

    final formatted = sql.replaceAll(RegExp(r'\n{2,}'), '\n').trim();
    if (formatted == _sqlController.text.trim()) return;

    _sqlController.text = formatted;
    if (showMessage) _addMessage(QeStrings.sqlFormatted);
    if (requestFocus) _editorFocusNode.requestFocus();
  }

  void _clearEditor() {
    _sqlController.clear();
    _addMessage(QeStrings.editorCleared);
    _editorFocusNode.requestFocus();
  }

  void _loadHistory(_HistoryEntry entry) {
    _sqlController.text = entry.sql;
    if (_autoFormatOnLoad) {
      _formatSql(showMessage: false, requestFocus: false);
    }
    setState(() => _selectedTab = 0);
    _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _sessionSnapshots[_sessionKey] = _QueryEditorSessionSnapshot(
      sql: _sqlController.text,
      selectedTab: _selectedTab == 1 ? 0 : _selectedTab,
      limit: _limit,
      timeoutSeconds: _timeoutSeconds,
      resultsPage: 0,
      rowsPerPage: _rowsPerPage,
      editorFontSize: _editorFontSize,
      safeMode: _safeMode,
      showLineNumbers: _showLineNumbers,
      exportHeaders: _exportHeaders,
      csvSeparator: _csvSeparator,
      lastSuccessfulSql: _lastSuccessfulSql,
      lastSavedSql: _lastSavedSql,
      history: List<_HistoryEntry>.of(_history),
      messages: List<String>.of(_messages),
    );
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
                color: _editorBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _editorBorderColor(colors)),
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
                          if (_showLineNumbers)
                            _LineNumbers(
                              controller: _sqlController,
                              scrollController: _editorScrollController,
                              lineHeight: _effectiveEditorLineHeight,
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
                              cursorColor: _isHighContrastEditor ? const Color(0xFFFFFF00) : colors.secondary,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _editorTextColor,
                                fontFamily: 'monospace',
                                fontSize: _editorFontSize,
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
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _sqlController,
                      builder: (context, value, _) {
                        return _EditorStatusBar(
                          position: _cursorPositionLabel(value),
                          lineCount: _lineCount(value.text),
                          characterCount: value.text.length,
                          safeMode: _safeMode,
                        );
                      },
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
          Expanded(child: _ToolbarButton(icon: Icons.construction_rounded, label: QeStrings.buildSql, onTap: _showSqlBuilderSheet)),
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

  int _lineCount(String text) => ('\n'.allMatches(text).length + 1).clamp(1, 9999).toInt();

  String _cursorPositionLabel(TextEditingValue value) {
    final text = value.text;
    final selectionStart = value.selection.start;
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
                  onPressed: () => _setSafeMode(!_safeMode),
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
                  Switch(value: _safeMode, onChanged: (value) => _setSafeMode(value)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _DropDownBox<int>(label: QeStrings.limit, value: _limit, values: const [50, 100, 250, 500], onChanged: (value) => _setLimit(value))),
                const SizedBox(width: 8),
                Expanded(child: _DropDownBox<int>(label: QeStrings.timeout, value: _timeoutSeconds, values: const [10, 30, 60], suffix: 's', onChanged: (value) => _setTimeoutSeconds(value))),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme, ColorScheme colors) {
    if (_executing) {
      return const _EmptyPanel(
        icon: Icons.hourglass_top_rounded,
        title: 'Running query',
        message: 'Waiting for the database response...',
      );
    }
    if (_errorMessage != null) return _ErrorPanel(message: _errorMessage!);
    final result = _result;
    if (result == null) return const _EmptyPanel(icon: Icons.table_chart_outlined, title: QeStrings.noResultsTitle, message: QeStrings.noResultsMessage);
    if (result.columns.isEmpty) return _EmptyPanel(icon: Icons.check_circle_outline_rounded, title: QeStrings.queryExecutedTitle, message: result.message.isEmpty ? QeStrings.commandExecuted : result.message);
    if (_isCommandMessageResult(result)) {
      final message = result.rows.isNotEmpty && result.rows.first.isNotEmpty
          ? (result.rows.first.first?.toString() ?? QeStrings.commandExecuted)
          : QeStrings.commandExecuted;
      return _CommandResultPanel(message: message);
    }

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
                      onDefaultExport: _exportResultsDefault,
                      defaultExportFormat: _defaultExportFormat,
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
                  onDefaultExport: _exportResultsDefault,
                  defaultExportFormat: _defaultExportFormat,
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

  bool _isCommandMessageResult(QueryExecuteResult result) {
    return result.columns.length == 1 &&
        result.columns.first.toLowerCase() == 'message' &&
        result.rows.length <= 1;
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
    required this.onDefaultExport,
    required this.defaultExportFormat,
    required this.onCsv,
    required this.onJson,
    required this.onExcel,
  });

  final bool hasRows;
  final VoidCallback onCopy;
  final VoidCallback onDefaultExport;
  final String defaultExportFormat;
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
            icon: Icons.file_download_outlined,
            label: 'Export $defaultExportFormat',
            enabled: hasRows,
            onPressed: onDefaultExport,
          ),
          const SizedBox(width: 8),
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
    required this.onDefaultExport,
    required this.defaultExportFormat,
    required this.onCsv,
    required this.onJson,
    required this.onExcel,
  });

  final VoidCallback onCopy;
  final VoidCallback onDefaultExport;
  final String defaultExportFormat;
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
          case 'default':
            onDefaultExport();
            break;
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
      itemBuilder: (context) => [
        PopupMenuItem(value: 'default', child: Text('Export $defaultExportFormat')),
        const PopupMenuItem(value: 'copy', child: Text('Copy')),
        const PopupMenuItem(value: 'csv', child: Text('CSV')),
        const PopupMenuItem(value: 'json', child: Text('JSON')),
        const PopupMenuItem(value: 'excel', child: Text('Excel')),
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

class _CommandResultPanel extends StatelessWidget {
  const _CommandResultPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF123329),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.35)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded, color: colors.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: SelectableText(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurface,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
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
  static final Set<String> _keywordNames = _keywords.map((value) => value.toLowerCase()).toSet();

  final DatabaseProvider provider;
  final Set<String> _functionNames;
  final Set<String> _dataTypeNames;
  late final RegExp _tokenPattern;
  bool highContrast = false;

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
    if (token.startsWith('--')) {
      return TextStyle(
        color: highContrast ? const Color(0xFFB7C0CC) : const Color(0xFF7A8797),
        fontStyle: FontStyle.italic,
      );
    }
    if (token.startsWith("'")) {
      return TextStyle(color: highContrast ? const Color(0xFFFFB000) : const Color(0xFFFFB86C));
    }
    if (RegExp(r'^\d').hasMatch(token)) {
      return TextStyle(color: highContrast ? const Color(0xFFFFFF00) : const Color(0xFFFFD866));
    }
    final normalized = token.toLowerCase();
    if (_functionNames.contains(normalized) && _isFunctionUsage(normalized, tokenEnd)) {
      return TextStyle(
        color: highContrast ? const Color(0xFFFF3BFF) : const Color(0xFFFF4FD8),
        fontWeight: FontWeight.w900,
      );
    }
    if (_dataTypeNames.contains(normalized)) {
      return TextStyle(
        color: highContrast ? const Color(0xFF00FF66) : const Color(0xFF93E8A7),
        fontWeight: FontWeight.w900,
      );
    }
    return TextStyle(
      color: highContrast ? const Color(0xFF00D5FF) : const Color(0xFF65B8FF),
      fontWeight: highContrast ? FontWeight.w900 : FontWeight.w700,
    );
  }

  bool _isFunctionUsage(String normalizedToken, int tokenEnd) {
    if (!_keywordNames.contains(normalizedToken)) {
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

class _LocalSqlBuildResult {
  const _LocalSqlBuildResult({required this.sql, required this.message});

  final String? sql;
  final String message;
}

class _LocalSqlGenerator {
  const _LocalSqlGenerator._();

  static _LocalSqlBuildResult generate({
    required String prompt,
    required DatabaseProvider provider,
    String? fallbackTable,
    String? fallbackSchema,
  }) {
    final normalized = _normalize(prompt);
    if (!_isEnglishRequest(normalized)) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'Only English requests are supported.',
      );
    }

    final table = _extractTable(normalized) ?? fallbackTable;
    if (!_isSafeIdentifierPath(table)) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'I could not identify a safe table name. Try: "select all from table customers".',
      );
    }

    final safeTable = table!;
    final qualifiedTable = _qualifiedTable(provider, safeTable, fallbackSchema);
    final command = _detectCommand(normalized);

    switch (command) {
      case 'insert':
        return _generateInsert(normalized, provider, qualifiedTable);
      case 'update':
        return _generateUpdate(normalized, provider, qualifiedTable);
      case 'delete':
        return _generateDelete(normalized, qualifiedTable);
      case 'select':
      default:
        return _generateSelect(
          normalized: normalized,
          provider: provider,
          qualifiedTable: qualifiedTable,
          table: safeTable,
        );
    }
  }

  static _LocalSqlBuildResult _generateSelect({
    required String normalized,
    required DatabaseProvider provider,
    required String qualifiedTable,
    required String table,
  }) {
    final columns = _extractColumns(normalized, table);
    final count = _hasAny(normalized, const ['count']);
    final where = _extractWhere(normalized);
    final orderBy = _extractOrderBy(normalized);
    final limit = _extractLimit(normalized);
    final selectList = count ? 'COUNT(*)' : (columns.isEmpty ? '*' : columns.join(', '));
    final buffer = StringBuffer();

    if (provider == DatabaseProvider.sqlServer && limit != null) {
      buffer.writeln('SELECT TOP $limit $selectList');
    } else {
      buffer.writeln('SELECT $selectList');
    }

    buffer.writeln('FROM $qualifiedTable');

    if (where != null) {
      buffer.writeln('WHERE ${where.toSql()}');
    }

    if (orderBy != null) {
      buffer.writeln('ORDER BY ${orderBy.column} ${orderBy.descending ? 'DESC' : 'ASC'}');
    }

    if (provider == DatabaseProvider.postgresql && limit != null) {
      buffer.writeln('LIMIT $limit');
    }

    if (provider == DatabaseProvider.oracle && limit != null) {
      buffer.writeln('FETCH FIRST $limit ROWS ONLY');
    }

    return _LocalSqlBuildResult(
      sql: '${buffer.toString().trim()};',
      message: 'Generated with the local rule-based SQL builder.',
    );
  }

  static _LocalSqlBuildResult _generateInsert(String normalized, DatabaseProvider provider, String qualifiedTable) {
    final values = _extractAssignments(normalized);
    if (values.isEmpty) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'I need column values for INSERT. Try: "insert into table customers name John and age 30".',
      );
    }

    final columns = values.keys.join(', ');
    final sqlValues = values.values.map((value) => _sqlLiteral(value, provider)).join(', ');

    return _LocalSqlBuildResult(
      sql: 'INSERT INTO $qualifiedTable ($columns)\nVALUES ($sqlValues);',
      message: 'Generated INSERT with the local rule-based SQL builder.',
    );
  }

  static _LocalSqlBuildResult _generateUpdate(String normalized, DatabaseProvider provider, String qualifiedTable) {
    final values = _extractAssignments(normalized);
    if (values.isEmpty) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'I need values to update. Try: "update table customers set name John where id equals 1".',
      );
    }

    final where = _extractWhere(normalized);
    if (where == null && !_hasAny(normalized, const ['all', 'every'])) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'UPDATE needs a WHERE condition, or say "update all" if you really want every row.',
      );
    }

    final setClause = values.entries
        .map((entry) => '${entry.key} = ${_sqlLiteral(entry.value, provider)}')
        .join(', ');
    final buffer = StringBuffer()
      ..writeln('UPDATE $qualifiedTable')
      ..write('SET $setClause');

    if (where != null) {
      buffer
        ..writeln()
        ..write('WHERE ${where.toSql()}');
    }

    return _LocalSqlBuildResult(
      sql: '${buffer.toString()};',
      message: 'Generated UPDATE with the local rule-based SQL builder.',
    );
  }

  static _LocalSqlBuildResult _generateDelete(String normalized, String qualifiedTable) {
    final where = _extractWhere(normalized);
    if (where == null && !_hasAny(normalized, const ['all', 'every'])) {
      return const _LocalSqlBuildResult(
        sql: null,
        message: 'DELETE needs a WHERE condition, or say "delete all" if you really want every row.',
      );
    }

    final buffer = StringBuffer()..write('DELETE FROM $qualifiedTable');
    if (where != null) {
      buffer
        ..writeln()
        ..write('WHERE ${where.toSql()}');
    }

    return _LocalSqlBuildResult(
      sql: '${buffer.toString()};',
      message: 'Generated DELETE with the local rule-based SQL builder.',
    );
  }

  static String _detectCommand(String value) {
    if (_hasAny(value, const ['insert', 'add', 'create row', 'new row'])) return 'insert';
    if (_hasAny(value, const ['update', 'change', 'modify', 'set'])) return 'update';
    if (_hasAny(value, const ['delete', 'remove'])) return 'delete';
    return 'select';
  }

  static String _normalize(String value) {
    return _stripDiacritics(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[¿?¡!,;]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isEnglishRequest(String value) {
    final englishHits = _countHits(value, const [
      'select',
      'show',
      'get',
      'need',
      'want',
      'rows',
      'records',
      'table',
      'from',
      'where',
      'order',
      'limit',
      'count',
      'insert',
      'add',
      'update',
      'change',
      'modify',
      'delete',
      'remove',
      'set',
      'values',
      'into',
    ]);

    return englishHits > 0;
  }

  static int _countHits(String value, List<String> words) {
    return words.where((word) => RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(value)).length;
  }

  static bool _hasAny(String value, List<String> words) {
    return words.any((word) => RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(value));
  }

  static String? _extractTable(String value) {
    final patterns = [
      RegExp(r'\btable\s+([a-zA-Z_][a-zA-Z0-9_.$]*)\b'),
      RegExp(r'\bfrom\s+(?:table\s+)?([a-zA-Z_][a-zA-Z0-9_.$]*)\b'),
      RegExp(r'\binto\s+(?:table\s+)?([a-zA-Z_][a-zA-Z0-9_.$]*)\b'),
      RegExp(r'\bupdate\s+(?:table\s+)?([a-zA-Z_][a-zA-Z0-9_.$]*)\b'),
      RegExp(r'\bdelete\s+from\s+(?:table\s+)?([a-zA-Z_][a-zA-Z0-9_.$]*)\b'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final table = match?.group(1);
      if (_isSafeIdentifierPath(table) && !_reservedTableWords.contains(table)) {
        return table;
      }
    }

    return null;
  }

  static List<String> _extractColumns(String value, String table) {
    if (_hasAny(value, const ['all', 'records', 'rows'])) {
      return const [];
    }

    final match = RegExp(
      r'\b(?:fields|columns)\s+([a-zA-Z0-9_,\s]+?)(?:\s+(?:from|where|order|limit)\b|$)',
    ).firstMatch(value);

    final raw = match?.group(1);
    if (raw == null) return const [];

    final columns = raw
        .split(RegExp(r'\s*,\s*|\s+and\s+'))
        .map((item) => item.trim())
        .where(_isSafeIdentifier)
        .where((item) => item != table)
        .toList();

    return columns;
  }

  static Map<String, String> _extractAssignments(String value) {
    var segment = '';
    final patterns = [
      RegExp(r'\bset\s+(.+?)(?:\s+where\b|$)'),
      RegExp(r'\bvalues?\s+(.+?)(?:\s+where\b|$)'),
      RegExp(r'\bwith\s+(.+?)(?:\s+where\b|$)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final raw = match?.group(1)?.trim() ?? '';
      if (raw.isNotEmpty) {
        segment = raw.replaceFirst(RegExp(r'^where\s+'), '').trim();
        break;
      }
    }

    if (segment.isEmpty) {
      final tableMatch = RegExp(r'\b(?:into|table|update)\s+(?:table\s+)?[a-zA-Z_][a-zA-Z0-9_.$]*\s+(.+?)(?:\s+where\b|$)').firstMatch(value);
      segment = tableMatch?.group(1)?.trim() ?? '';
    }

    if (segment.isEmpty) return const {};

    final result = <String, String>{};
    final parts = segment
        .split(RegExp(r'\s*,\s*|\s+and\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);

    for (final part in parts) {
      final match = RegExp(
        r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*(?:=|:|to|as|equals|equal(?:\s+to)?|is)?\s+(.+)$',
      ).firstMatch(part);

      final column = match?.group(1)?.trim();
      var rawValue = match?.group(2)?.trim();
      if (!_isSafeIdentifier(column) || rawValue == null || rawValue.isEmpty) continue;

      rawValue = rawValue.replaceAll(RegExp(r'^(to|as|equals|equal(?:\s+to)?|is|where)\s+'), '').trim();
      if (rawValue.isEmpty || _reservedAssignmentWords.contains(rawValue)) continue;

      result[column!] = rawValue;
    }

    return result;
  }

  static _LocalSqlCondition? _extractWhere(String value) {
    final whereIndex = value.lastIndexOf(RegExp(r'\bwhere\b'));
    if (whereIndex < 0) return null;
    final afterWhere = value.substring(whereIndex).replaceFirst(RegExp(r'^where\s+'), '');
    final segment = afterWhere.split(RegExp(r'\s+(?:order|limit)\b')).first.trim();
    if (segment.isEmpty) return null;
    final normalizedSegment = segment
        .replaceAll(RegExp(r'\bi\s+d\b'), 'id')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final conditionPatterns = <({RegExp regex, String comparison})>[
      (regex: RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+(?:greater\s+than|more\s+than)\s+(.+)$'), comparison: '>'),
      (regex: RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+less\s+than\s+(.+)$'), comparison: '<'),
      (regex: RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+(?:like|contains|containing)\s+(.+)$'), comparison: 'LIKE'),
      (regex: RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+(?:equals|equal(?:\s+to)?|is)\s+(.+)$'), comparison: '='),
      (regex: RegExp(r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s*(>=|<=|=|>|<)\s*(.+)$'), comparison: ''),
    ];

    for (final item in conditionPatterns) {
      final match = item.regex.firstMatch(normalizedSegment);
      if (match == null) continue;

      final column = match.group(1)?.trim();
      final comparison = item.comparison.isEmpty ? match.group(2)?.trim() : item.comparison;
      final conditionValue = match.group(item.comparison.isEmpty ? 3 : 2)?.trim();

      if (!_isSafeIdentifier(column) || comparison == null || conditionValue == null || conditionValue.isEmpty) {
        continue;
      }

      return _LocalSqlCondition(column: column!, comparison: comparison, value: conditionValue);
    }

    final spokenMatch = RegExp(
      r'\b([a-zA-Z_][a-zA-Z0-9_]*)\s+(.+)$',
    ).firstMatch(normalizedSegment);
    final spokenColumn = spokenMatch?.group(1)?.trim();
    final spokenValue = spokenMatch?.group(2)?.trim();
    if (_isSafeIdentifier(spokenColumn) && spokenValue != null && spokenValue.isNotEmpty) {
      return _LocalSqlCondition(column: spokenColumn!, comparison: '=', value: spokenValue);
    }

    return null;
  }

  static _LocalSqlOrder? _extractOrderBy(String value) {
    final match = RegExp(r'\border\s+by\s+([a-zA-Z_][a-zA-Z0-9_]*)(?:\s+(asc|desc|ascending|descending))?').firstMatch(value);
    final column = match?.group(1);
    if (!_isSafeIdentifier(column)) return null;

    final direction = match?.group(2) ?? '';
    return _LocalSqlOrder(
      column: column!,
      descending: direction == 'desc' || direction == 'descending',
    );
  }

  static int? _extractLimit(String value) {
    final match = RegExp(r'\b(?:limit|top|first)\s+(\d{1,4})\b').firstMatch(value);
    final parsed = int.tryParse(match?.group(1) ?? '');
    if (parsed == null) return null;
    return parsed.clamp(1, 5000).toInt();
  }

  static String _sqlLiteral(String value, DatabaseProvider provider) {
    final cleanValue = value.trim().replaceAll(RegExp(r"""^['"]|['"]$"""), '');
    if (cleanValue == 'null') return 'NULL';
    if (cleanValue == 'true') {
      return provider == DatabaseProvider.postgresql ? 'TRUE' : '1';
    }
    if (cleanValue == 'false') {
      return provider == DatabaseProvider.postgresql ? 'FALSE' : '0';
    }

    final numeric = num.tryParse(cleanValue.replaceAll(',', '.'));
    if (numeric != null) return numeric.toString();
    final wordNumber = _englishNumberWords[cleanValue];
    if (wordNumber != null) return wordNumber.toString();

    final escaped = cleanValue.replaceAll("'", "''");
    return "'$escaped'";
  }

  static String _qualifiedTable(DatabaseProvider provider, String table, String? schema) {
    final parts = table.split('.');
    final effectiveSchema = parts.length > 1 ? parts.first : schema;
    final name = parts.length > 1 ? parts.last : table;

    switch (provider) {
      case DatabaseProvider.sqlServer:
        final cleanSchema = _cleanSqlServerIdentifier(effectiveSchema ?? 'dbo');
        final cleanName = _cleanSqlServerIdentifier(name);
        return '[$cleanSchema].[$cleanName]';
      case DatabaseProvider.postgresql:
        final cleanSchema = _cleanQuotedIdentifier(effectiveSchema ?? 'public');
        final cleanName = _cleanQuotedIdentifier(name);
        return '"$cleanSchema"."$cleanName"';
      case DatabaseProvider.oracle:
        final cleanSchema = _cleanQuotedIdentifier(effectiveSchema ?? '').toUpperCase();
        final cleanName = _cleanQuotedIdentifier(name).toUpperCase();
        return cleanSchema.isEmpty ? '"$cleanName"' : '"$cleanSchema"."$cleanName"';
    }
  }

  static bool _isSafeIdentifier(String? value) {
    return value != null && RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(value);
  }

  static bool _isSafeIdentifierPath(String? value) {
    return value != null && RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*(?:\.[a-zA-Z_][a-zA-Z0-9_]*)?$').hasMatch(value);
  }

  static String _cleanSqlServerIdentifier(String value) {
    return value.replaceAll('[', '').replaceAll(']', '').trim();
  }

  static String _cleanQuotedIdentifier(String value) {
    return value.replaceAll('"', '""').trim();
  }

  static String _stripDiacritics(String value) {
    const replacements = {
      'á': 'a',
      'à': 'a',
      'ä': 'a',
      'â': 'a',
      'é': 'e',
      'è': 'e',
      'ë': 'e',
      'ê': 'e',
      'í': 'i',
      'ì': 'i',
      'ï': 'i',
      'î': 'i',
      'ó': 'o',
      'ò': 'o',
      'ö': 'o',
      'ô': 'o',
      'ú': 'u',
      'ù': 'u',
      'ü': 'u',
      'û': 'u',
      'ñ': 'n',
      'ç': 'c',
    };

    var normalized = value;
    replacements.forEach((from, to) {
      normalized = normalized
          .replaceAll(from, to)
          .replaceAll(from.toUpperCase(), to.toUpperCase());
    });
    return normalized;
  }

  static const Set<String> _reservedTableWords = {
    'table',
    'records',
    'rows',
  };

  static const Set<String> _reservedAssignmentWords = {
    'where',
    'order',
    'limit',
    'from',
    'table',
  };

  static const Map<String, int> _englishNumberWords = {
    'zero': 0,
    'one': 1,
    'two': 2,
    'three': 3,
    'four': 4,
    'five': 5,
    'six': 6,
    'seven': 7,
    'eight': 8,
    'nine': 9,
    'ten': 10,
    'eleven': 11,
    'twelve': 12,
    'thirteen': 13,
    'fourteen': 14,
    'fifteen': 15,
    'sixteen': 16,
    'seventeen': 17,
    'eighteen': 18,
    'nineteen': 19,
    'twenty': 20,
  };
}

class _LocalSqlCondition {
  const _LocalSqlCondition({
    required this.column,
    required this.comparison,
    required this.value,
  });

  final String column;
  final String comparison;
  final String value;

  String toSql() {
    final cleanValue = value.trim();
    if (comparison == 'LIKE') {
      final normalized = cleanValue.replaceAll(RegExp(r'^(like|contains|containing)\s+'), '').trim();
      final escaped = normalized.replaceAll("'", "''");
      return "$column LIKE '%$escaped%'";
    }

    final numeric = num.tryParse(cleanValue.replaceAll(',', '.'));
    if (numeric != null) return '$column $comparison ${numeric.toString()}';
    final wordNumber = _LocalSqlGenerator._englishNumberWords[cleanValue];
    if (wordNumber != null) return '$column $comparison $wordNumber';

    final normalized = cleanValue.replaceAll(RegExp(r'^(es|is)\s+'), '').trim();
    final escaped = normalized.replaceAll("'", "''");
    return "$column $comparison '$escaped'";
  }
}

class _LocalSqlOrder {
  const _LocalSqlOrder({required this.column, required this.descending});

  final String column;
  final bool descending;
}

class _QueryEditorSessionSnapshot {
  const _QueryEditorSessionSnapshot({
    required this.sql,
    required this.selectedTab,
    required this.limit,
    required this.timeoutSeconds,
    required this.resultsPage,
    required this.rowsPerPage,
    required this.editorFontSize,
    required this.safeMode,
    required this.showLineNumbers,
    required this.exportHeaders,
    required this.csvSeparator,
    required this.lastSuccessfulSql,
    required this.lastSavedSql,
    required this.history,
    required this.messages,
  });

  final String sql;
  final int selectedTab;
  final int limit;
  final int timeoutSeconds;
  final int resultsPage;
  final int rowsPerPage;
  final double editorFontSize;
  final bool safeMode;
  final bool showLineNumbers;
  final bool exportHeaders;
  final String csvSeparator;
  final String? lastSuccessfulSql;
  final String? lastSavedSql;
  final List<_HistoryEntry> history;
  final List<String> messages;
}
