import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_assets.dart';
import '../../core/strings/strings.dart';
import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/query_history_storage_service.dart';
import '../../services/saved_connection_storage_service.dart';
import 'connection_screen.dart';
import 'oracle_main.dart';
import 'postgresql_main.dart';
import 'query_editor/query_editor_screen.dart';
import 'sqlserver_main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _appName = 'DBPilot';
  static const String _appVersion = '0.1.0';
  static const String _appBuildNumber = '1';
  static const String _supportEmail = 'support@dbpilot.app';
  static const List<String> _settingsBackupKeys = [
    'settings.defaultSafeMode',
    'settings.confirmDangerousQueries',
    'settings.showLineNumbers',
    'settings.autoFormatOnLoad',
    'settings.exportHeaders',
    'settings.defaultTimeout',
    'settings.defaultLimit',
    'settings.editorFontSize',
    'settings.editorTheme',
    'settings.defaultExportFormat',
    'settings.csvSeparator',
  ];

  final _storageService = SavedConnectionStorageService();
  final _queryHistoryService = QueryHistoryStorageService();
  final _apiService = ConnectionApiService();

  bool _loading = true;
  bool _connecting = false;
  int _selectedIndex = 0;
  DatabaseProvider? _expandedConnectionProvider;
  DatabaseProvider? _expandedQueryProvider;

  bool _defaultSafeMode = true;
  bool _confirmDangerousQueries = true;
  bool _showLineNumbers = true;
  bool _autoFormatOnLoad = false;
  bool _exportHeaders = true;
  int _defaultTimeout = 30;
  int _defaultLimit = 100;
  double _editorFontSize = 14;
  String _editorTheme = 'Dark';
  String _defaultExportFormat = 'CSV';
  String _csvSeparator = ',';

  List<Map<String, dynamic>> _connections = [];
  List<QueryHistoryItem> _queries = [];
  String? _activeConnectionId;
  Map<String, dynamic>? _activeConnection;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final connections = await _storageService.getSavedConnections();
    final queries = await _queryHistoryService.getQueries();
    final activeId = await _storageService.getActiveConnectionId();
    final prefs = await SharedPreferences.getInstance();

    Map<String, dynamic>? active;
    for (final item in connections) {
      if (item['id']?.toString() == activeId) {
        active = item;
        break;
      }
    }

    if (!mounted) return;

    setState(() {
      _connections = connections.reversed.toList();
      _queries = queries;
      _activeConnectionId = activeId;
      _activeConnection = active;
      _defaultSafeMode = prefs.getBool('settings.defaultSafeMode') ?? true;
      _confirmDangerousQueries = prefs.getBool('settings.confirmDangerousQueries') ?? true;
      _showLineNumbers = prefs.getBool('settings.showLineNumbers') ?? true;
      _autoFormatOnLoad = prefs.getBool('settings.autoFormatOnLoad') ?? false;
      _exportHeaders = prefs.getBool('settings.exportHeaders') ?? true;
      _defaultTimeout = prefs.getInt('settings.defaultTimeout') ?? 30;
      _defaultLimit = prefs.getInt('settings.defaultLimit') ?? 100;
      _editorFontSize = prefs.getDouble('settings.editorFontSize') ?? 14;
      _editorTheme = prefs.getString('settings.editorTheme') ?? 'Dark';
      _defaultExportFormat = prefs.getString('settings.defaultExportFormat') ?? 'CSV';
      _csvSeparator = prefs.getString('settings.csvSeparator') ?? ',';
      _loading = false;
    });
  }

  String _providerLabel(String value) {
    return DatabaseProviderX.fromString(value).label;
  }

  DatabaseProvider _providerFromMap(Map<String, dynamic> connection) {
    return DatabaseProviderX.fromString(connection['provider']?.toString() ?? '');
  }

  String _connectionId(Map<String, dynamic> connection) {
    return _storageService.ensureConnectionId(connection);
  }

  Future<ConnectionRequest> _buildRequest(Map<String, dynamic> connection) async {
    final id = _connectionId(connection);
    final fullConnection = await _storageService.getConnectionById(id);

    if (fullConnection == null) {
      throw Exception('Connection not found.');
    }

    return ConnectionRequest(
      name: fullConnection['name']?.toString() ?? '',
      provider: DatabaseProviderX.fromString(
        fullConnection['provider']?.toString() ?? 'postgresql',
      ),
      host: fullConnection['host']?.toString() ?? '',
      port: fullConnection['port']?.toString() ?? '',
      username: fullConnection['username']?.toString() ?? '',
      password: fullConnection['password']?.toString() ?? '',
      database: fullConnection['database']?.toString() ?? '',
      serviceName: fullConnection['serviceName']?.toString(),
      sid: fullConnection['sid']?.toString(),
      encrypt: fullConnection['encrypt'] == true,
      trustServerCertificate: fullConnection['trustServerCertificate'] != false,
    );
  }

  Widget _providerMain(ConnectionRequest request) {
    switch (request.provider) {
      case DatabaseProvider.sqlServer:
        return SqlServerMain(connection: request);
      case DatabaseProvider.postgresql:
        return PostgreSqlMain(connection: request);
      case DatabaseProvider.oracle:
        return OracleMain(connection: request);
    }
  }

  String _connectionTarget(ConnectionRequest request) {
    if (request.provider == DatabaseProvider.oracle) {
      final serviceName = request.serviceName?.trim();
      final sid = request.sid?.trim();

      if (serviceName != null && serviceName.isNotEmpty) return serviceName;
      if (sid != null && sid.isNotEmpty) return sid;
    }

    return request.database;
  }

  String _connectionDatabaseName(Map<String, dynamic> connection) {
    final provider = _providerFromMap(connection);

    if (provider == DatabaseProvider.oracle) {
      final serviceName = connection['serviceName']?.toString().trim() ?? '';
      final sid = connection['sid']?.toString().trim() ?? '';
      final database = connection['database']?.toString().trim() ?? '';

      if (serviceName.isNotEmpty) return serviceName;
      if (sid.isNotEmpty) return sid;
      if (database.isNotEmpty) return database;
      return 'Oracle database';
    }

    final database = connection['database']?.toString().trim() ?? '';
    if (database.isNotEmpty) return database;

    return '${provider.label} database';
  }

  Future<void> _openConnectionScreen({Map<String, dynamic>? initialData}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(initialData: initialData),
      ),
    );

    if (!mounted) return;
    await _loadData();
  }

  Future<void> _connectToExplorer(Map<String, dynamic> connection) async {
    if (_connecting) return;

    setState(() => _connecting = true);

    try {
      final request = await _buildRequest(connection);
      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      await _storageService.setActiveConnectionId(_connectionId(connection));
      await _loadData();

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _providerMain(request),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _runQueryFromConnection(Map<String, dynamic> connection) async {
    if (_connecting) return;

    setState(() => _connecting = true);

    try {
      final request = await _buildRequest(connection);
      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      await _storageService.setActiveConnectionId(_connectionId(connection));
      await _loadData();

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QueryEditorScreen(
            connection: request,
            providerLabel: request.provider.label.toUpperCase(),
            connectionSummary:
                '${request.name}\n${request.host} / ${_connectionTarget(request)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Future<void> _openQuery(QueryHistoryItem query) async {
    if (_connecting) return;

    final connection = _findConnectionForQuery(query);

    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No compatible connection found.')),
      );
      return;
    }

    setState(() => _connecting = true);

    try {
      final request = await _buildRequest(connection);
      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      await _storageService.setActiveConnectionId(_connectionId(connection));
      await _loadData();

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QueryEditorScreen(
            connection: request,
            providerLabel: request.provider.label.toUpperCase(),
            connectionSummary:
                '${request.name}\n${request.host} / ${_connectionTarget(request)}',
            initialSql: query.sql,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
      }
    }
  }

  Map<String, dynamic>? _findConnectionForQuery(QueryHistoryItem query) {
    final queryProvider = DatabaseProviderX.fromString(query.provider);
    final queryConnectionName = query.connectionName.trim().toLowerCase();

    for (final connection in _connections) {
      final provider = _providerFromMap(connection);
      final name = connection['name']?.toString().trim().toLowerCase() ?? '';

      if (provider == queryProvider && name == queryConnectionName) {
        return connection;
      }
    }

    for (final connection in _connections) {
      if (_providerFromMap(connection) == queryProvider) {
        return connection;
      }
    }

    return null;
  }

  Future<void> _deleteConnection(Map<String, dynamic> connection) async {
    final name = connection['name']?.toString() ?? 'this connection';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.deleteConnectionTitle),
        content: Text(AppStrings.deleteConnectionMessage(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(AppStrings.delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _storageService.deleteConnectionById(_connectionId(connection));
    await _loadData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.connectionDeleted)),
    );
  }

  Future<void> _deleteQuery(QueryHistoryItem query) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete query'),
        content: const Text('Do you want to delete this query?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _queryHistoryService.deleteQuery(query.id);
    await _loadData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Query deleted.')),
    );
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(hour12)}:${two(value.minute)} $period';
  }

  Widget _providerIcon(DatabaseProvider provider, {bool active = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: active
            ? const Color(0xFF0F3B61)
            : const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? const Color(0xFF2D8CFF).withOpacity(0.55)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Center(
        child: Image.asset(
          provider.asset,
          width: 28,
          height: 28,
          errorBuilder: (_, __, ___) => Icon(
            Icons.storage_rounded,
            color: active ? const Color(0xFF9EC5FF) : Colors.white70,
          ),
        ),
      ),
    );
  }

  Widget _buildActiveConnectionCard() {
    final active = _activeConnection;
    final hasActive = active != null;
    final provider = hasActive ? _providerFromMap(active) : DatabaseProvider.sqlServer;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: hasActive ? const Color(0xFF0B223A) : const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: hasActive
              ? const Color(0xFF2D8CFF).withOpacity(0.55)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: hasActive
            ? [
                BoxShadow(
                  color: const Color(0xFF2D8CFF).withOpacity(0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: hasActive
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: Color(0xFF5CF2A4)),
                    SizedBox(width: 8),
                    Text(
                      'ACTIVE CONNECTION',
                      style: TextStyle(
                        color: Color(0xFF5CF2A4),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _providerIcon(provider, active: true),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            active['name']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provider.label} · ${active['host'] ?? ''}:${active['port'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _connecting
                            ? null
                            : () => _connectToExplorer(active),
                        icon: const Icon(Icons.dataset_outlined, size: 17),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Open Explorer',
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _connecting
                            ? null
                            : () => _runQueryFromConnection(active),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Run Query',
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE CONNECTION',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'No active connection selected.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
    );
  }

  Widget _connectionCard(Map<String, dynamic> connection) {
    final id = _connectionId(connection);
    final isActive = id == _activeConnectionId;
    final databaseName = _connectionDatabaseName(connection);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF0B223A) : const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? const Color(0xFF00C2FF).withOpacity(0.60)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: _connecting ? null : () => _connectToExplorer(connection),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection['name']?.toString() ?? 'Unnamed connection',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      databaseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive
                            ? const Color(0xFF5CF2A4)
                            : const Color(0xFF2D8CFF),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF104A3A),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF5CF2A4).withOpacity(0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: Color(0xFF5CF2A4)),
                      SizedBox(width: 8),
                      Text(
                        'Active',
                        style: TextStyle(
                          color: Color(0xFF5CF2A4),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              PopupMenuButton<String>(
                enabled: !_connecting,
                onSelected: (value) async {
                  if (value == 'connect') {
                    await _connectToExplorer(connection);
                  } else if (value == 'query') {
                    await _runQueryFromConnection(connection);
                  } else if (value == 'edit') {
                    await _openConnectionScreen(initialData: connection);
                  } else if (value == 'delete') {
                    await _deleteConnection(connection);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'connect',
                    child: Text('Open Explorer'),
                  ),
                  PopupMenuItem(
                    value: 'query',
                    child: Text('Run Query'),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(AppStrings.edit),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(AppStrings.delete),
                  ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queryCard(QueryHistoryItem query) {
    final provider = DatabaseProviderX.fromString(query.provider);
    final preview = query.sql.replaceAll('\n', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF15181E),
      child: ListTile(
        leading: _providerIcon(provider),
        title: Text(
          query.connectionName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(_formatDateTime(query.executedAt)),
            const SizedBox(height: 4),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          enabled: !_connecting,
          onSelected: (value) async {
            if (value == 'connect') {
              await _openQuery(query);
            } else if (value == 'delete') {
              await _deleteQuery(query);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: 'connect',
              child: Text('Connect'),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text('Delete'),
            ),
          ],
          icon: const Icon(Icons.more_vert_rounded),
        ),
        onTap: _connecting ? null : () => _openQuery(query),
      ),
    );
  }


  Map<DatabaseProvider, List<Map<String, dynamic>>> _groupConnectionsByProvider() {
    final grouped = <DatabaseProvider, List<Map<String, dynamic>>>{
      DatabaseProvider.sqlServer: [],
      DatabaseProvider.postgresql: [],
      DatabaseProvider.oracle: [],
    };

    for (final connection in _connections) {
      final provider = _providerFromMap(connection);
      grouped[provider]!.add(connection);
    }

    return grouped;
  }

  Widget _buildConnectionsList() {
    final grouped = _groupConnectionsByProvider();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const Text(
          'Connections',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        _buildActiveConnectionCard(),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Connections',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _openConnectionScreen(),
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_connections.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: Text('No saved connections.')),
          )
        else
          for (final provider in DatabaseProvider.values) ...[
            if ((grouped[provider] ?? []).isNotEmpty)
              _buildConnectionProviderSection(provider, grouped[provider]!),
          ],
      ],
    );
  }

  Widget _buildConnectionProviderSection(
    DatabaseProvider provider,
    List<Map<String, dynamic>> connections,
  ) {
    final expanded = _expandedConnectionProvider == provider;

    return _buildProviderAccordion(
      provider: provider,
      count: connections.length,
      expanded: expanded,
      onToggle: () {
        setState(() {
          _expandedConnectionProvider = expanded ? null : provider;
        });
      },
      children: connections.map(_connectionCard).toList(),
    );
  }

  Widget _buildQueriesList() {
    final grouped = <DatabaseProvider, List<QueryHistoryItem>>{
      DatabaseProvider.sqlServer: [],
      DatabaseProvider.postgresql: [],
      DatabaseProvider.oracle: [],
    };

    for (final query in _queries) {
      final provider = DatabaseProviderX.fromString(query.provider);
      grouped[provider]!.add(query);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const Text(
          'Queries',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        if (_queries.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: Text('No saved queries.')),
          )
        else
          for (final provider in DatabaseProvider.values) ...[
            if ((grouped[provider] ?? []).isNotEmpty)
              _buildQueryProviderSection(provider, grouped[provider]!),
          ],
      ],
    );
  }

  Widget _buildQueryProviderSection(
    DatabaseProvider provider,
    List<QueryHistoryItem> queries,
  ) {
    final expanded = _expandedQueryProvider == provider;

    return _buildProviderAccordion(
      provider: provider,
      count: queries.length,
      expanded: expanded,
      onToggle: () {
        setState(() {
          _expandedQueryProvider = expanded ? null : provider;
        });
      },
      children: queries.map(_queryCard).toList(),
    );
  }

  Widget _buildProviderAccordion({
    required DatabaseProvider provider,
    required int count,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF15181E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: expanded
                ? const Color(0xFF2D8CFF).withOpacity(0.45)
                : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _providerIcon(provider),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.label,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(Icons.keyboard_arrow_down_rounded),
                    ),
                  ],
                ),
              ),
            ),
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(children: children),
                      )
                    : const SizedBox(width: double.infinity, height: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        _settingsSection(
          icon: Icons.workspace_premium_rounded,
          title: 'Subscription / Plan',
          children: [
            _planTile(),
          ],
        ),
        _settingsSection(
          icon: Icons.shield_outlined,
          title: 'Security',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _defaultSafeMode,
              onChanged: (value) => _updateBoolSetting('settings.defaultSafeMode', value, (v) => _defaultSafeMode = v),
              title: const Text('Safe Mode by default'),
              subtitle: const Text('Block non-SELECT queries by default.'),
            ),
            Opacity(
              opacity: _defaultSafeMode ? 0.55 : 1,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmDangerousQueries,
                onChanged: _defaultSafeMode
                    ? null
                    : (value) => _updateBoolSetting(
                          'settings.confirmDangerousQueries',
                          value,
                          (v) => _confirmDangerousQueries = v,
                        ),
                title: const Text('Confirm dangerous queries'),
                subtitle: Text(
                  _defaultSafeMode
                      ? 'Safe Mode blocks these queries before confirmation is needed.'
                      : 'Ask before running data-changing or schema-changing SQL.',
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _settingsDropdown<int>(
                    label: 'Default timeout',
                    value: _defaultTimeout,
                    values: const [10, 30, 60],
                    labelFor: (value) => '${value}s',
                    onChanged: (value) => _updateIntSetting('settings.defaultTimeout', value, (v) => _defaultTimeout = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _settingsDropdown<int>(
                    label: 'Default row limit',
                    value: _defaultLimit,
                    values: const [50, 100, 250, 500],
                    labelFor: (value) => '$value',
                    onChanged: (value) => _updateIntSetting('settings.defaultLimit', value, (v) => _defaultLimit = v),
                  ),
                ),
              ],
            ),
          ],
        ),
        _settingsSection(
          icon: Icons.terminal_rounded,
          title: 'Query Editor',
          children: [
            _settingsDropdown<String>(
              label: 'Editor theme',
              value: _editorTheme,
              values: const ['Dark', 'High contrast'],
              labelFor: (value) => value,
              onChanged: (value) => _updateStringSetting('settings.editorTheme', value, (v) => _editorTheme = v),
            ),
            const SizedBox(height: 10),
            _settingsDropdown<double>(
              label: 'Font size',
              value: _editorFontSize,
              values: const [12, 14, 16, 18],
              labelFor: (value) => value.toStringAsFixed(0),
              onChanged: (value) => _updateDoubleSetting('settings.editorFontSize', value, (v) => _editorFontSize = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showLineNumbers,
              onChanged: (value) => _updateBoolSetting('settings.showLineNumbers', value, (v) => _showLineNumbers = v),
              title: const Text('Show line numbers'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoFormatOnLoad,
              onChanged: (value) => _updateBoolSetting('settings.autoFormatOnLoad', value, (v) => _autoFormatOnLoad = v),
              title: const Text('Auto-format SQL on load'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Local SQL builder language'),
              subtitle: Text('English only'),
            ),
          ],
        ),
        _settingsSection(
          icon: Icons.file_download_outlined,
          title: 'Exports',
          children: [
            _settingsDropdown<String>(
              label: 'Default export format',
              value: _defaultExportFormat,
              values: const ['CSV', 'JSON', 'Excel'],
              labelFor: (value) => value,
              onChanged: (value) => _updateStringSetting('settings.defaultExportFormat', value, (v) => _defaultExportFormat = v),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _exportHeaders,
              onChanged: (value) => _updateBoolSetting('settings.exportHeaders', value, (v) => _exportHeaders = v),
              title: const Text('Include headers'),
            ),
            _settingsDropdown<String>(
              label: 'CSV separator',
              value: _csvSeparator,
              values: const [',', ';', '\t'],
              labelFor: (value) => value == '\t' ? 'Tab' : value,
              onChanged: (value) => _updateStringSetting('settings.csvSeparator', value, (v) => _csvSeparator = v),
            ),
          ],
        ),
        _settingsSection(
          icon: Icons.storage_rounded,
          title: 'Data / Storage',
          children: [
            _actionTile(
              icon: Icons.history_toggle_off_rounded,
              title: 'Clear query history',
              subtitle: '${_queries.length} saved queries',
              onTap: _clearQueryHistory,
            ),
            _actionTile(
              icon: Icons.delete_sweep_rounded,
              title: 'Clear saved connections',
              subtitle: '${_connections.length} saved connections',
              onTap: _clearSavedConnections,
            ),
            _actionTile(
              icon: Icons.ios_share_rounded,
              title: 'Export settings',
              subtitle: 'Share a JSON backup of app preferences',
              onTap: _exportSettings,
            ),
            _actionTile(
              icon: Icons.input_rounded,
              title: 'Import settings',
              subtitle: 'Paste a DBPilot settings JSON backup',
              onTap: _showImportSettingsDialog,
            ),
            _actionTile(
              icon: Icons.cleaning_services_rounded,
              title: 'Clear local cache',
              subtitle: 'Clear active session and temporary editor state',
              onTap: _clearLocalCache,
            ),
          ],
        ),
        _settingsSection(
          icon: Icons.info_outline_rounded,
          title: 'About',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _aboutAppIcon(size: 42),
              title: const Text(_appName, style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: Text('Version $_appVersion ($_appBuildNumber)'),
              trailing: TextButton(
                onPressed: _showAppAboutDialog,
                child: const Text('Details'),
              ),
            ),
            _actionTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'How DBPilot stores and uses local data',
              onTap: _showPrivacyPolicy,
            ),
            _actionTile(
              icon: Icons.description_outlined,
              title: 'Terms',
              subtitle: 'Usage conditions and responsibilities',
              onTap: _showTerms,
            ),
            _actionTile(
              icon: Icons.support_agent_rounded,
              title: 'Contact / support',
              subtitle: _supportEmail,
              onTap: _showSupport,
            ),
            _actionTile(
              icon: Icons.copy_all_rounded,
              title: 'Copy app info',
              subtitle: 'Useful when reporting an issue',
              onTap: _copyAppInfo,
            ),
            _actionTile(
              icon: Icons.article_outlined,
              title: 'Open source licenses',
              subtitle: 'Flutter and package licenses',
              onTap: _showLicenses,
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingsSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF2D8CFF)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _planTile() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2A4A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2D8CFF).withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current plan: Free',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Up to 3 connections, limited history, CSV export and SELECT-only workflow.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openPaywall,
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Upgrade to Pro'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaywall() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const _PaywallScreen(),
      ),
    );
  }

  Widget _settingsDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelFor(item)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF2D8CFF)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Future<void> _updateBoolSetting(String key, bool value, ValueChanged<bool> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateIntSetting(String key, int value, ValueChanged<int> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateDoubleSetting(String key, double value, ValueChanged<double> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateStringSetting(String key, String value, ValueChanged<String> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _clearQueryHistory() async {
    final confirmed = await _confirmSettingsAction(
      title: 'Clear query history?',
      message: 'This will delete all saved query history.',
    );
    if (!confirmed) return;

    await _queryHistoryService.clearHistory();
    await _loadData();
    _showInfo('Query history cleared.');
  }

  Future<void> _clearSavedConnections() async {
    final confirmed = await _confirmSettingsAction(
      title: 'Clear saved connections?',
      message: 'This will delete all saved connections and stored passwords.',
    );
    if (!confirmed) return;

    await _storageService.clearAllConnections();
    await _loadData();
    _showInfo('Saved connections cleared.');
  }

  Future<void> _exportSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};

    for (final key in _settingsBackupKeys) {
      final value = prefs.get(key);
      if (value != null) settings[key] = value;
    }

    final payload = {
      'app': _appName,
      'version': _appVersion,
      'build': _appBuildNumber,
      'exportedAt': DateTime.now().toIso8601String(),
      'settings': settings,
    };

    final encoder = const JsonEncoder.withIndent('  ');
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/dbpilot_settings_${_exportTimestamp()}.json');
    await file.writeAsString(encoder.convert(payload), flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'DBPilot settings backup',
    );

    _showInfo('Settings exported.');
  }

  Future<void> _showImportSettingsDialog() async {
    final controller = TextEditingController();

    final imported = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Paste a DBPilot settings JSON backup. This will update app preferences only.'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 6,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  hintText: '{ "settings": { ... } }',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final data = await Clipboard.getData(Clipboard.kTextPlain);
              controller.text = data?.text ?? '';
            },
            child: const Text('Paste'),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Import')),
        ],
      ),
    );

    if (imported != true) {
      controller.dispose();
      return;
    }

    final jsonText = controller.text.trim();
    controller.dispose();

    if (jsonText.isEmpty) {
      _showInfo('No settings JSON provided.');
      return;
    }

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        _showInfo('Invalid settings backup.');
        return;
      }

      final settingsPayload = decoded['settings'];
      final settings = settingsPayload is Map<String, dynamic> ? settingsPayload : decoded;
      final applied = await _applyImportedSettings(settings);

      if (applied == 0) {
        _showInfo('No supported settings found.');
        return;
      }

      await _loadData();
      _showInfo('$applied settings imported.');
    } catch (error) {
      _showInfo('Settings import failed: $error');
    }
  }

  Future<int> _applyImportedSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    var applied = 0;

    Future<void> setBool(String key) async {
      final value = settings[key];
      if (value is! bool) return;
      await prefs.setBool(key, value);
      applied++;
    }

    Future<void> setInt(String key, List<int> allowedValues) async {
      final value = settings[key];
      if (value is! num) return;
      final intValue = value.toInt();
      if (!allowedValues.contains(intValue)) return;
      await prefs.setInt(key, intValue);
      applied++;
    }

    Future<void> setDouble(String key, List<double> allowedValues) async {
      final value = settings[key];
      if (value is! num) return;
      final doubleValue = value.toDouble();
      if (!allowedValues.contains(doubleValue)) return;
      await prefs.setDouble(key, doubleValue);
      applied++;
    }

    Future<void> setString(String key, List<String> allowedValues) async {
      final value = settings[key];
      if (value is! String) return;
      if (!allowedValues.contains(value)) return;
      await prefs.setString(key, value);
      applied++;
    }

    await setBool('settings.defaultSafeMode');
    await setBool('settings.confirmDangerousQueries');
    await setBool('settings.showLineNumbers');
    await setBool('settings.autoFormatOnLoad');
    await setBool('settings.exportHeaders');
    await setInt('settings.defaultTimeout', const [10, 30, 60]);
    await setInt('settings.defaultLimit', const [50, 100, 250, 500]);
    await setDouble('settings.editorFontSize', const [12.0, 14.0, 16.0, 18.0]);
    await setString('settings.editorTheme', const ['Dark', 'High contrast']);
    await setString('settings.defaultExportFormat', const ['CSV', 'JSON', 'Excel']);
    await setString('settings.csvSeparator', const [',', ';', '\t']);

    return applied;
  }

  Future<void> _clearLocalCache() async {
    final confirmed = await _confirmSettingsAction(
      title: 'Clear local cache?',
      message: 'This clears the active connection and temporary query editor sessions. Saved connections, query history and settings will not be deleted.',
    );
    if (!confirmed) return;

    await _storageService.clearActiveConnectionId();
    QueryEditorScreen.clearSessionCache();

    if (!mounted) return;
    setState(() {
      _expandedConnectionProvider = null;
      _expandedQueryProvider = null;
    });
    await _loadData();
    _showInfo('Local cache cleared.');
  }

  String _exportTimestamp() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '')
        .replaceAll('T', '_');
  }

  Future<bool> _confirmSettingsAction({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    return result == true;
  }

  void _showAppAboutDialog() {
    _showAboutTextDialog(
      title: _appName,
      icon: Icons.info_outline_rounded,
      body:
          'Version $_appVersion ($_appBuildNumber)\n\n'
          'Mobile database utility for SQL Server, Oracle and PostgreSQL.\n\n'
          'Use Settings to configure security defaults, query editor behavior, export preferences and local storage options.',
    );
  }

  void _showPrivacyPolicy() {
    _showAboutTextDialog(
      title: 'Privacy policy',
      icon: Icons.privacy_tip_outlined,
      body:
          'DBPilot stores saved connections, query history and app settings locally on this device.\n\n'
          'Passwords and sensitive connection data are stored using the secure storage available on the platform.\n\n'
          'DBPilot does not send your queries, credentials or database results to external AI services. The local SQL builder runs on the device.\n\n'
          'When you connect to a database, connection data is sent only to the configured DBPilot backend required to execute that operation.',
    );
  }

  void _showTerms() {
    _showAboutTextDialog(
      title: 'Terms',
      icon: Icons.description_outlined,
      body:
          'Use DBPilot only with databases and credentials you are authorized to access.\n\n'
          'Review generated or loaded SQL before running it, especially when Safe Mode is disabled.\n\n'
          'You are responsible for the effects of executed SQL statements, including INSERT, UPDATE, DELETE, CREATE, ALTER and DROP commands.\n\n'
          'DBPilot is provided as a database utility and should not replace database backups, access controls or operational review processes.',
    );
  }

  void _showSupport() {
    _showAboutTextDialog(
      title: 'Contact / support',
      icon: Icons.support_agent_rounded,
      body:
          'For support, send an email to:\n\n'
          '$_supportEmail\n\n'
          'Include the app version, provider, device type and a short description of the issue. You can use "Copy app info" from this screen to prepare the basic details.',
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: _supportEmail));
            if (!mounted) return;
            Navigator.of(context).pop();
            _showInfo('Support email copied.');
          },
          child: const Text('Copy email'),
        ),
      ],
    );
  }

  Future<void> _copyAppInfo() async {
    final info = [
      'App: $_appName',
      'Version: $_appVersion ($_appBuildNumber)',
      'Connections: ${_connections.length}',
      'Saved queries: ${_queries.length}',
      'Default Safe Mode: ${_defaultSafeMode ? 'ON' : 'OFF'}',
      'Default timeout: ${_defaultTimeout}s',
      'Default row limit: $_defaultLimit',
      'Editor theme: $_editorTheme',
    ].join('\n');

    await Clipboard.setData(ClipboardData(text: info));
    _showInfo('App info copied.');
  }

  void _showLicenses() {
    showLicensePage(
      context: context,
      applicationName: _appName,
      applicationVersion: 'Version $_appVersion ($_appBuildNumber)',
      applicationIcon: _aboutAppIcon(size: 48),
    );
  }

  Widget _aboutAppIcon({required double size}) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2A4A),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: const Color(0xFF2D8CFF).withOpacity(0.45)),
      ),
      child: Image.asset(AppAssets.appIcon, fit: BoxFit.contain),
    );
  }

  void _showAboutTextDialog({
    required String title,
    required IconData icon,
    required String body,
    List<Widget> actions = const [],
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: const Color(0xFF2D8CFF)),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(body),
        ),
        actions: [
          ...actions,
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _bottomNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          if (_selectedIndex != index) {
            if (index == 0) _expandedConnectionProvider = null;
            if (index == 1) _expandedQueryProvider = null;
          }
          _selectedIndex = index;
        }),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          scale: selected ? 1.04 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            height: 58,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            transform: Matrix4.translationValues(0, selected ? -3 : 0, 0),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF0B2A4A) : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: selected
                  ? Border.all(
                      color: const Color(0xFF2D8CFF).withOpacity(0.5),
                    )
                  : null,
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF2D8CFF).withOpacity(0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    icon,
                    key: ValueKey('$label-$selected'),
                    color:
                        selected ? const Color(0xFF2D8CFF) : Colors.white54,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        selected ? const Color(0xFF2D8CFF) : Colors.white54,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF101318),
        border: Border(
          top: BorderSide(color: Color(0xFF222832)),
        ),
      ),
      child: Row(
        children: [
          _bottomNavItem(
            index: 0,
            icon: Icons.storage_rounded,
            label: AppStrings.connections,
          ),
          _bottomNavItem(
            index: 1,
            icon: Icons.menu_rounded,
            label: AppStrings.queries,
          ),
          _bottomNavItem(
            index: 2,
            icon: Icons.settings_rounded,
            label: AppStrings.settings,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (_selectedIndex == 0) {
      content = _buildConnectionsList();
    } else if (_selectedIndex == 1) {
      content = _buildQueriesList();
    } else {
      content = _buildSettings();
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  content,
                  if (_connecting)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.18),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _loading ? null : _buildBottomNav(),
    );
  }
}

class _PaywallScreen extends StatelessWidget {
  const _PaywallScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF030817),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030817),
        title: const Text('Upgrade'),
      ),
      body: SafeArea(
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF071021), Color(0xFF030817)],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 150),
                  children: [
                    _PaywallHero(theme: theme),
                    const SizedBox(height: 22),
                    _PlanCard(
                      title: 'Pro',
                      subtitle: 'For serious database work',
                      icon: Icons.rocket_launch_rounded,
                      featured: true,
                      badge: 'PRO',
                      features: const [
                        _PlanFeature(Icons.all_inclusive_rounded, 'Unlimited connections', 'All 3 providers supported'),
                        _PlanFeature(Icons.storage_rounded, 'Full query history', 'No limits'),
                        _PlanFeature(Icons.description_rounded, 'Export in all formats', 'CSV, Excel, JSON and more'),
                        _PlanFeature(Icons.mic_rounded, 'Voice command', 'Build SQL requests with your voice'),
                        _PlanFeature(Icons.code_rounded, 'Advanced queries', 'SELECT, INSERT, UPDATE, DELETE, DDL and DML'),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PlanCard(
                      title: 'Free',
                      subtitle: 'Try DBPilot with no commitment',
                      icon: Icons.near_me_rounded,
                      features: const [
                        _PlanFeature(Icons.link_rounded, 'Up to 3 connections', '1 connection per provider'),
                        _PlanFeature(Icons.history_rounded, 'Limited history', 'Last 10 queries'),
                        _PlanFeature(Icons.description_rounded, 'Export to CSV only', 'Basic result sharing'),
                        _PlanFeature(Icons.code_rounded, 'SELECT queries only', 'Ideal for safe quick tests'),
                      ],
                    ),
                  ],
                ),
              ),
              _PaywallActions(
                onUpgrade: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payments are not connected yet.')),
                  );
                },
                onContinue: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallHero extends StatelessWidget {
  const _PaywallHero({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(AppAssets.appIcon, width: 44, height: 44),
            const SizedBox(width: 10),
            const Text(
              'DBPilot',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Unlock the full potential of DBPilot',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1.08, letterSpacing: 0),
        ),
        const SizedBox(height: 10),
        Text(
          'Work without limits: more connections, more history, more export formats and full access to advanced queries.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white.withOpacity(0.72),
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.features,
    this.featured = false,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<_PlanFeature> features;
  final bool featured;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final borderColor = featured ? const Color(0xFF2D8CFF) : Colors.white.withOpacity(0.16);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: featured ? const Color(0xFF10133A).withOpacity(0.92) : const Color(0xFF111827).withOpacity(0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor.withOpacity(featured ? 0.9 : 1)),
        boxShadow: featured
            ? [
                BoxShadow(
                  color: const Color(0xFF8D4DFF).withOpacity(0.24),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          if (badge != null)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2196F3), Color(0xFFB53DFF)]),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text(badge!, style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ),
          Icon(icon, color: featured ? const Color(0xFF2D8CFF) : const Color(0xFF7D73FF), size: 42),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 0)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: featured ? const Color(0xFFB99CFF) : const Color(0xFFC2B8FF))),
          const SizedBox(height: 18),
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0) Divider(color: Colors.white.withOpacity(0.1), height: 18),
            _PlanFeatureRow(feature: features[i], featured: featured),
          ],
        ],
      ),
    );
  }
}

class _PlanFeature {
  const _PlanFeature(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;
}

class _PlanFeatureRow extends StatelessWidget {
  const _PlanFeatureRow({required this.feature, required this.featured});

  final _PlanFeature feature;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: featured ? const Color(0xFF092B4E) : const Color(0xFF1B2030),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(feature.icon, color: featured ? const Color(0xFF21B8FF) : const Color(0xFF8B7BFF), size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(feature.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0)),
              const SizedBox(height: 3),
              Text(feature.subtitle, style: TextStyle(color: Colors.white.withOpacity(0.72), height: 1.25)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaywallActions extends StatelessWidget {
  const _PaywallActions({required this.onUpgrade, required this.onContinue});

  final VoidCallback onUpgrade;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF030817).withOpacity(0.96),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1EA7FF), Color(0xFFB536F5)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: FilledButton.icon(
                onPressed: onUpgrade,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Upgrade to Pro', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: onContinue,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white.withOpacity(0.78),
                side: BorderSide(color: Colors.white.withOpacity(0.24)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Continue with Free', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 14, color: Color(0xFFB38CFF)),
              const SizedBox(width: 6),
              Text('No credit card required. Upgrade anytime.', style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
