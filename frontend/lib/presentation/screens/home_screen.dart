import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_assets.dart';
import '../../core/strings/strings.dart';
import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/auth_service.dart';
import '../../services/connection_api_service.dart';
import '../../services/connection_backup_service.dart';
import '../../services/plan_access_service.dart';
import '../../services/query_history_storage_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../../services/subscription_service.dart';
import 'connection_screen.dart';
import 'oracle_main.dart';
import 'postgresql_main.dart';
import 'query_editor/query_editor_screen.dart';
import 'sqlserver_main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.initialSession,
    required this.showInitialPaywall,
    required this.onSignedOut,
  });

  final AppUserSession initialSession;
  final bool showInitialPaywall;
  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _appName = 'DBPilot';
  static const String _appVersion = '0.1.0';
  static const String _appBuildNumber = '1';
  static const String _supportEmail = 'dbpilot.app@gmail.com';
  static const List<IconData> _avatarIcons = [
    Icons.person_rounded,
    Icons.terminal_rounded,
    Icons.storage_rounded,
    Icons.code_rounded,
    Icons.bolt_rounded,
    Icons.shield_rounded,
  ];
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
  final _authService = AuthService();
  final _connectionBackupService = ConnectionBackupService();

  bool _loading = true;
  bool _connecting = false;
  bool _authLoading = false;
  bool _initialPaywallHandled = false;
  int _selectedIndex = 0;
  int _avatarIndex = 0;
  DatabaseProvider? _expandedConnectionProvider;
  DatabaseProvider? _expandedQueryProvider;
  String? _expandedQueryConnectionKey;

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
  AppUserSession? _authSession;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final connections = await _storageService.getSavedConnections();
    final queries = await _queryHistoryService.getQueries();
    final activeId = await _storageService.getActiveConnectionId();
    final authSession =
        await _authService.currentSession() ?? widget.initialSession;
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
      _authSession = authSession;
      _avatarIndex = prefs.getInt('settings.avatar.${authSession.uid}') ?? 0;
      _defaultSafeMode = prefs.getBool('settings.defaultSafeMode') ?? true;
      _confirmDangerousQueries =
          prefs.getBool('settings.confirmDangerousQueries') ?? true;
      _showLineNumbers = prefs.getBool('settings.showLineNumbers') ?? true;
      _autoFormatOnLoad = prefs.getBool('settings.autoFormatOnLoad') ?? false;
      _exportHeaders = prefs.getBool('settings.exportHeaders') ?? true;
      _defaultTimeout = prefs.getInt('settings.defaultTimeout') ?? 30;
      _defaultLimit = prefs.getInt('settings.defaultLimit') ?? 100;
      _editorFontSize = prefs.getDouble('settings.editorFontSize') ?? 14;
      _editorTheme = prefs.getString('settings.editorTheme') ?? 'Dark';
      _defaultExportFormat =
          prefs.getString('settings.defaultExportFormat') ?? 'CSV';
      _csvSeparator = prefs.getString('settings.csvSeparator') ?? ',';
      _loading = false;
    });

    PlanAccessService.instance.updateSession(authSession);
    if (widget.showInitialPaywall && !_initialPaywallHandled) {
      _initialPaywallHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _openPaywall();
        await prefs.setBool('onboarding.paywallShown.${authSession.uid}', true);
      });
    }
  }

  Future<void> _reloadQueries() async {
    final queries = await _queryHistoryService.getQueries();
    if (!mounted) return;
    setState(() => _queries = queries);
  }

  String _providerLabel(String value) {
    return DatabaseProviderX.fromString(value).label;
  }

  DatabaseProvider _providerFromMap(Map<String, dynamic> connection) {
    return DatabaseProviderX.fromString(
        connection['provider']?.toString() ?? '');
  }

  String _connectionId(Map<String, dynamic> connection) {
    return _storageService.ensureConnectionId(connection);
  }

  Future<ConnectionRequest> _buildRequest(
      Map<String, dynamic> connection) async {
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
        return SqlServerMain(
          connection: request,
          onUpgradeRequested: _openPaywall,
        );
      case DatabaseProvider.postgresql:
        return PostgreSqlMain(
          connection: request,
          onUpgradeRequested: _openPaywall,
        );
      case DatabaseProvider.oracle:
        return OracleMain(
          connection: request,
          onUpgradeRequested: _openPaywall,
        );
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

  Future<void> _openConnectionScreen({
    Map<String, dynamic>? initialData,
    bool duplicate = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(
          initialData: initialData,
          duplicate: duplicate,
          onUpgradeRequested: _openPaywall,
        ),
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
      await _reloadQueries();
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
                'Connection: ${request.name}\nDatabase: ${_connectionTarget(request)}',
            onUpgradeRequested: _openPaywall,
          ),
        ),
      );
      await _reloadQueries();
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
                'Connection: ${request.name}\nDatabase: ${_connectionTarget(request)}',
            initialSql: query.sql,
            onUpgradeRequested: _openPaywall,
          ),
        ),
      );
      await _reloadQueries();
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
    final provider = _providerFromMap(connection);

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
    await _queryHistoryService.deleteQueriesForConnection(
      provider: provider.apiValue,
      connectionName: name,
    );
    await _loadData();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStrings.connectionDeleted)),
    );
  }

  Future<void> _duplicateConnection(Map<String, dynamic> connection) async {
    final fullConnection = await _storageService.getConnectionById(
      _connectionId(connection),
    );

    if (!mounted) return;

    if (fullConnection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection not found.')),
      );
      return;
    }

    final duplicateData = Map<String, dynamic>.from(fullConnection);
    duplicateData.remove('id');
    duplicateData['name'] =
        _copyConnectionName(fullConnection['name']?.toString() ?? '');

    await _openConnectionScreen(initialData: duplicateData, duplicate: true);
  }

  String _copyConnectionName(String name) {
    final baseName = name.trim().isEmpty ? 'Connection' : name.trim();
    final existingNames = _connections
        .map((connection) =>
            connection['name']?.toString().trim().toLowerCase() ?? '')
        .toSet();

    var candidate = '$baseName Copy';
    var index = 2;
    while (existingNames.contains(candidate.toLowerCase())) {
      candidate = '$baseName Copy $index';
      index++;
    }

    return candidate;
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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final minute = value.minute.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${months[value.month - 1]} ${value.day}, ${value.year} · $hour12:$minute $period';
  }

  Widget _providerIcon(DatabaseProvider provider, {bool active = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF0F3B61) : const Color(0xFF1A1D23),
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
    final provider =
        hasActive ? _providerFromMap(active) : DatabaseProvider.sqlServer;

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  } else if (value == 'duplicate') {
                    await _duplicateConnection(connection);
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
                    value: 'duplicate',
                    child: Text('Duplicate'),
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
    final preview = query.sql.replaceAll('\n', ' ');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF15181E),
      child: ListTile(
        title: Text(
          _formatDateTime(query.executedAt),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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

  Map<String, List<QueryHistoryItem>> _groupQueriesByConnection(
      List<QueryHistoryItem> queries) {
    final grouped = <String, List<QueryHistoryItem>>{};

    for (final query in queries) {
      final connectionName = query.connectionName.trim().isEmpty
          ? 'Unnamed connection'
          : query.connectionName.trim();
      grouped
          .putIfAbsent(connectionName, () => <QueryHistoryItem>[])
          .add(query);
    }

    return grouped;
  }

  String _queryConnectionKey(DatabaseProvider provider, String connectionName) {
    return '${provider.apiValue}|${connectionName.trim().toLowerCase()}';
  }

  Widget _queryConnectionSection({
    required String connectionName,
    required List<QueryHistoryItem> queries,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      connectionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFEAF1FF),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      queries.length.toString(),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
                      child: Column(
                        children: queries.map(_queryCard).toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Map<DatabaseProvider, List<Map<String, dynamic>>>
      _groupConnectionsByProvider() {
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
    final groupedByConnection = _groupQueriesByConnection(queries);

    return _buildProviderAccordion(
      provider: provider,
      count: queries.length,
      expanded: expanded,
      onToggle: () {
        setState(() {
          if (expanded) {
            _expandedQueryProvider = null;
            _expandedQueryConnectionKey = null;
          } else {
            _expandedQueryProvider = provider;
            _expandedQueryConnectionKey = null;
          }
        });
      },
      children: groupedByConnection.entries.map((entry) {
        final key = _queryConnectionKey(provider, entry.key);
        final connectionExpanded = _expandedQueryConnectionKey == key;

        return _queryConnectionSection(
          connectionName: entry.key,
          queries: entry.value,
          expanded: connectionExpanded,
          onToggle: () {
            setState(() {
              if (connectionExpanded) {
                _expandedQueryConnectionKey = null;
              } else {
                _expandedQueryConnectionKey = key;
              }
            });
          },
        );
      }).toList(),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
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
              onChanged: (value) => _updateBoolSetting(
                  'settings.defaultSafeMode',
                  value,
                  (v) => _defaultSafeMode = v),
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
                    onChanged: (value) => _updateIntSetting(
                        'settings.defaultTimeout',
                        value,
                        (v) => _defaultTimeout = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _settingsDropdown<int>(
                    label: 'Default row limit',
                    value: _defaultLimit,
                    values: const [50, 100, 250, 500],
                    labelFor: (value) => '$value',
                    onChanged: (value) => _updateIntSetting(
                        'settings.defaultLimit',
                        value,
                        (v) => _defaultLimit = v),
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
              onChanged: (value) => _updateStringSetting(
                  'settings.editorTheme', value, (v) => _editorTheme = v),
            ),
            const SizedBox(height: 10),
            _settingsDropdown<double>(
              label: 'Font size',
              value: _editorFontSize,
              values: const [12, 14, 16, 18],
              labelFor: (value) => value.toStringAsFixed(0),
              onChanged: (value) => _updateDoubleSetting(
                  'settings.editorFontSize', value, (v) => _editorFontSize = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _showLineNumbers,
              onChanged: (value) => _updateBoolSetting(
                  'settings.showLineNumbers',
                  value,
                  (v) => _showLineNumbers = v),
              title: const Text('Show line numbers'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoFormatOnLoad,
              onChanged: (value) => _updateBoolSetting(
                  'settings.autoFormatOnLoad',
                  value,
                  (v) => _autoFormatOnLoad = v),
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
              onChanged: (value) => _updateStringSetting(
                  'settings.defaultExportFormat',
                  value,
                  (v) => _defaultExportFormat = v),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _exportHeaders,
              onChanged: (value) => _updateBoolSetting(
                  'settings.exportHeaders', value, (v) => _exportHeaders = v),
              title: const Text('Include headers'),
            ),
            _settingsDropdown<String>(
              label: 'CSV separator',
              value: _csvSeparator,
              values: const [',', ';', '\t'],
              labelFor: (value) => value == '\t' ? 'Tab' : value,
              onChanged: (value) => _updateStringSetting(
                  'settings.csvSeparator', value, (v) => _csvSeparator = v),
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
              icon: Icons.file_upload_outlined,
              title: 'Export connections',
              subtitle: 'Share a JSON backup without passwords',
              proOnly: true,
              onTap: _exportConnections,
            ),
            _actionTile(
              icon: Icons.file_download_outlined,
              title: 'Import connections',
              subtitle: 'Restore connections from a DBPilot JSON file',
              proOnly: true,
              onTap: _importConnections,
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
            _actionTile(
              icon: Icons.delete_forever_rounded,
              title: 'Delete account',
              subtitle: 'Delete your account and all associated DBPilot data',
              destructive: true,
              onTap: _deleteAccount,
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
              title: const Text(_appName,
                  style: TextStyle(fontWeight: FontWeight.w900)),
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
              title: 'Terms of Service',
              subtitle: 'Usage conditions and responsibilities',
              onTap: _showTerms,
            ),
            _actionTile(
              icon: Icons.support_agent_rounded,
              title: 'Support',
              subtitle: _supportEmail,
              onTap: _showSupport,
            ),
            _actionTile(
              icon: Icons.bug_report_outlined,
              title: 'Report a bug',
              subtitle: 'Open your email app',
              onTap: _reportBug,
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

  Future<void> _signInWithGoogle() async {
    if (_authLoading) return;

    setState(() => _authLoading = true);
    try {
      final session = await _authService.signInWithGoogle();
      if (!mounted) return;

      setState(() => _authSession = session);
      PlanAccessService.instance.updateSession(session);
      if (session == null) {
        _showInfo('Google sign-in was cancelled.');
        return;
      }

      _showInfo('Signed in. UID: ${session.uid}');
    } catch (error) {
      if (!mounted) return;
      _showInfo('Google sign-in failed: ${_friendlySignInError(error)}');
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  String _friendlySignInError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    if (message.contains('GoogleSignInExceptionCode.canceled') ||
        message.contains('Account reauth failed')) {
      return 'Google sign-in was cancelled or could not reauthenticate this account. Try again or select another Google account.';
    }
    return message;
  }

  Future<void> _signOut() async {
    if (_authLoading) return;

    setState(() => _authLoading = true);
    try {
      await _authService.signOut();
      if (!mounted) return;
      QueryEditorScreen.clearSessionCache();
      setState(() => _authSession = null);
      PlanAccessService.instance.updateSession(null);
      widget.onSignedOut();
    } catch (error) {
      if (!mounted) return;
      _showInfo(
          'Sign-out failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _refreshSubscriptionPlan() async {
    if (_authLoading) return;

    setState(() => _authLoading = true);
    try {
      final session = await _authService.currentSession();
      if (!mounted) return;
      setState(() => _authSession = session);
      PlanAccessService.instance.updateSession(session);
      _showInfo(session == null
          ? 'Sign in to check your plan.'
          : 'Plan checked: ${session.plan.label}.');
    } catch (error) {
      if (!mounted) return;
      _showInfo(
          'Plan check failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Widget _planTile() {
    final session = _authSession;
    final currentPlan = session?.plan ?? SubscriptionPlan.free;

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
          Text(
            'Current plan: ${currentPlan.label}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            currentPlan == SubscriptionPlan.pro
                ? 'Unlimited connections, full history, all export formats and advanced query workflows.'
                : 'Up to 3 connections, limited history, CSV export and SELECT-only workflow.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          if (session == null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _authLoading ? null : _signInWithGoogle,
                icon: _authLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login_rounded),
                label: const Text('Continuar con Google'),
              ),
            )
          else
            _signedInPlanDetails(session),
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

  Widget _signedInPlanDetails(AppUserSession session) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: _showAvatarPicker,
                borderRadius: BorderRadius.circular(8),
                child: _accountAvatar(size: 46),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.displayName?.trim().isNotEmpty == true
                          ? session.displayName!
                          : 'Google account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (session.email != null &&
                        session.email!.trim().isNotEmpty)
                      Text(
                        session.email!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _showAvatarPicker,
                tooltip: 'Choose avatar',
                icon: const Icon(Icons.edit_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _authLoading ? null : _refreshSubscriptionPlan,
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Check plan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: _authLoading ? null : _signOut,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountAvatar({double size = 38}) {
    final index = _avatarIndex.clamp(0, _avatarIcons.length - 1);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF123B63),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2D8CFF)),
      ),
      child: Icon(
        _avatarIcons[index],
        size: size * 0.55,
        color: const Color(0xFF9EC5FF),
      ),
    );
  }

  Future<void> _showAvatarPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose your avatar',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _avatarIcons.length,
                itemBuilder: (context, index) => InkWell(
                  onTap: () => Navigator.of(context).pop(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: index == _avatarIndex
                          ? const Color(0xFF123B63)
                          : const Color(0xFF171C24),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: index == _avatarIndex
                            ? const Color(0xFF2D8CFF)
                            : Colors.white12,
                      ),
                    ),
                    child: Icon(
                      _avatarIcons[index],
                      size: 34,
                      color: index == _avatarIndex
                          ? const Color(0xFF9EC5FF)
                          : Colors.white70,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;

    final session = _authSession;
    if (session == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('settings.avatar.${session.uid}', selected);
    if (mounted) setState(() => _avatarIndex = selected);
  }

  Widget _accountHeader() {
    final session = _authSession!;
    return Material(
      color: const Color(0xFF101318),
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = 2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              _accountAvatar(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session.email ?? session.displayName ?? 'Google account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: session.plan == SubscriptionPlan.pro
                      ? const Color(0xFF173D32)
                      : const Color(0xFF252B35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  session.plan.label,
                  style: TextStyle(
                    color: session.plan == SubscriptionPlan.pro
                        ? const Color(0xFF61D9A7)
                        : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPaywall() async {
    final session = _authSession;

    final upgraded = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => _PaywallScreen(
          uid: session?.uid,
          onSignIn: _signInForPurchase,
        ),
      ),
    );

    if (upgraded == true) {
      await _refreshSubscriptionPlan();
    }
  }

  Future<String?> _signInForPurchase() async {
    try {
      final session = await _authService.signInWithGoogle();
      if (!mounted || session == null) return null;
      setState(() => _authSession = session);
      PlanAccessService.instance.updateSession(session);
      return session.uid;
    } catch (error) {
      if (mounted) {
        _showInfo(
          'Google sign-in failed: ${_friendlySignInError(error)}',
        );
      }
      return null;
    }
  }

  Widget _settingsDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) labelFor,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
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
    bool proOnly = false,
    bool destructive = false,
  }) {
    final accentColor =
        destructive ? const Color(0xFFFF8A8A) : const Color(0xFF2D8CFF);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: accentColor),
      title: Text(
        title,
        style: destructive ? TextStyle(color: accentColor) : null,
      ),
      subtitle: Text(subtitle),
      trailing: proOnly
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF173D32),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PRO',
                    style: TextStyle(
                      color: Color(0xFF61D9A7),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded),
              ],
            )
          : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Future<void> _updateBoolSetting(
      String key, bool value, ValueChanged<bool> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateIntSetting(
      String key, int value, ValueChanged<int> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateDoubleSetting(
      String key, double value, ValueChanged<double> assign) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
    if (!mounted) return;
    setState(() => assign(value));
  }

  Future<void> _updateStringSetting(
      String key, String value, ValueChanged<String> assign) async {
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
    final file =
        File('${directory.path}/dbpilot_settings_${_exportTimestamp()}.json');
    await file.writeAsString(encoder.convert(payload), flush: true);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'DBPilot settings backup',
    );

    _showInfo('Settings exported.');
  }

  Future<bool> _requireProFeature(ProFeature feature) async {
    if (PlanAccessService.instance.canUse(feature)) return true;

    final upgrade = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('DBPilot Pro'),
        content: Text('${feature.title} is available with DBPilot Pro.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('View Pro'),
          ),
        ],
      ),
    );
    if (upgrade == true) await _openPaywall();
    return false;
  }

  Future<void> _exportConnections() async {
    if (!await _requireProFeature(ProFeature.connectionBackup)) return;
    if (_connections.isEmpty) {
      _showInfo('There are no connections to export.');
      return;
    }

    try {
      final json = await _connectionBackupService.exportJson();
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/dbpilot_connections_${_exportTimestamp()}.json',
      );
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'DBPilot connections backup (passwords are not included)',
      );
      _showInfo('${_connections.length} connections exported.');
    } catch (error) {
      _showInfo(
        'Connections export failed: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  Future<void> _importConnections() async {
    if (!await _requireProFeature(ProFeature.connectionBackup)) return;

    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;

      final selectedFile = selection.files.single;
      String source;
      if (selectedFile.bytes != null) {
        source = utf8.decode(selectedFile.bytes!);
      } else if (selectedFile.path != null) {
        source = await File(selectedFile.path!).readAsString();
      } else {
        throw const FormatException('The selected file could not be read.');
      }
      if (source.length > 2 * 1024 * 1024) {
        throw const FormatException('The connections backup is too large.');
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Import connections?'),
          content: const Text(
            'Existing connections will not be overwritten. Duplicate names will be imported with a new name. Passwords must be entered again after import.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final result = await _connectionBackupService.importJson(source);
      await _loadData();
      _showInfo(
        '${result.imported} connections imported'
        '${result.renamed > 0 ? ', ${result.renamed} renamed' : ''}'
        '${result.skipped > 0 ? ', ${result.skipped} skipped' : ''}.',
      );
    } catch (error) {
      _showInfo(
        'Connections import failed: ${error.toString().replaceFirst('FormatException: ', '').replaceFirst('Exception: ', '')}',
      );
    }
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
              const Text(
                  'Paste a DBPilot settings JSON backup. This will update app preferences only.'),
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
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Import')),
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
      final settings =
          settingsPayload is Map<String, dynamic> ? settingsPayload : decoded;
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
    await setString(
        'settings.defaultExportFormat', const ['CSV', 'JSON', 'Excel']);
    await setString('settings.csvSeparator', const [',', ';', '\t']);

    return applied;
  }

  Future<void> _clearLocalCache() async {
    final confirmed = await _confirmSettingsAction(
      title: 'Clear local cache?',
      message:
          'This clears the active connection and temporary query editor sessions. Saved connections, query history and settings will not be deleted.',
    );
    if (!confirmed) return;

    await _storageService.clearActiveConnectionId();
    QueryEditorScreen.clearSessionCache();

    if (!mounted) return;
    setState(() {
      _expandedConnectionProvider = null;
      _expandedQueryProvider = null;
      _expandedQueryConnectionKey = null;
    });
    await _loadData();
    _showInfo('Local cache cleared.');
  }

  Future<void> _deleteAccount() async {
    final session = _authSession;
    if (session == null) {
      _showInfo('Sign in to delete your account.');
      return;
    }

    final confirmed = await _confirmSettingsAction(
      title: 'Delete account?',
      message:
          'This permanently deletes your DBPilot account, subscription record, saved connections, stored passwords, query history and account preferences. This action cannot be undone.',
    );
    if (!confirmed) return;

    setState(() => _authLoading = true);
    try {
      await _authService.deleteAccount();
      await _storageService.clearAllConnections();
      await _queryHistoryService.clearHistory();
      await _clearAccountPreferences(session.uid);
      QueryEditorScreen.clearSessionCache();
      PlanAccessService.instance.updateSession(null);

      if (!mounted) return;
      setState(() {
        _authSession = null;
        _connections = [];
        _queries = [];
        _activeConnectionId = null;
        _activeConnection = null;
        _expandedConnectionProvider = null;
        _expandedQueryProvider = null;
        _expandedQueryConnectionKey = null;
      });
      _returnToSignInAfterAccountDeletion();
    } catch (error) {
      if (!mounted) return;
      _showInfo(
        'Account deletion failed: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      if (mounted) setState(() => _authLoading = false);
    }
  }

  Future<void> _clearAccountPreferences(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('onboarding.paywallShown.$uid');
  }

  void _returnToSignInAfterAccountDeletion() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    widget.onSignedOut();
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
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm')),
        ],
      ),
    );
    return result == true;
  }

  void _showAppAboutDialog() {
    _showAboutTextDialog(
      title: _appName,
      icon: Icons.info_outline_rounded,
      body: 'Version $_appVersion ($_appBuildNumber)\n\n'
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
      title: 'Terms of Service',
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
      title: 'Support',
      icon: Icons.support_agent_rounded,
      body: 'For support, send an email to:\n\n'
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

  Future<void> _reportBug() async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {'subject': 'DBPilot - Bug report'},
    );

    try {
      final opened = await launchUrl(
        emailUri,
        mode: LaunchMode.externalApplication,
      );
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }

    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    if (mounted) {
      _showInfo('No email app was found. Support email copied.');
    }
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _bottomNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final selected = _selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () async {
          setState(() {
            if (_selectedIndex != index) {
              if (index == 0) _expandedConnectionProvider = null;
              if (index == 1) {
                _expandedQueryProvider = null;
                _expandedQueryConnectionKey = null;
              }
            }
            _selectedIndex = index;
          });
          if (index == 1) await _reloadQueries();
        },
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
                    color: selected ? const Color(0xFF2D8CFF) : Colors.white54,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? const Color(0xFF2D8CFF) : Colors.white54,
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
            if (!_loading && _authSession != null) _accountHeader(),
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

class _PaywallScreen extends StatefulWidget {
  const _PaywallScreen({required this.uid, required this.onSignIn});

  final String? uid;
  final Future<String?> Function() onSignIn;

  @override
  State<_PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<_PaywallScreen> {
  final _subscriptionService = SubscriptionService();
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  List<SubscriptionProduct> _products = const [];
  SubscriptionProduct? _selectedProduct;
  String? _uid;
  bool _loadingProduct = true;
  bool _buying = false;
  String? _storeMessage;

  @override
  void initState() {
    super.initState();
    _uid = widget.uid;
    _purchaseSubscription = _subscriptionService.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _buying = false;
          _storeMessage = 'Purchase update failed: $error';
        });
      },
    );
    unawaited(_loadProduct());
  }

  Future<void> _loadProduct() async {
    setState(() {
      _loadingProduct = true;
      _storeMessage = null;
    });

    try {
      final products = await _subscriptionService.loadProProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _selectedProduct = products.isEmpty ? null : products.last;
        _loadingProduct = false;
        _storeMessage = products.isEmpty
            ? 'Pro subscription is not available yet. Check Google Play product setup.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingProduct = false;
        _storeMessage = 'Could not load subscription: $error';
      });
    }
  }

  Future<void> _buyPro() async {
    final product = _selectedProduct;
    if (product == null || _buying) return;

    setState(() {
      _buying = true;
      _storeMessage = null;
    });

    try {
      final uid = await _ensureSignedIn();
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _buying = false;
          _storeMessage = 'Sign in with Google to start your subscription.';
        });
        return;
      }
      await _subscriptionService.buyPro(product, uid: uid);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _buying = false;
        _storeMessage = 'Could not start purchase: $error';
      });
    }
  }

  Future<void> _restorePurchases() async {
    if (_buying) return;

    setState(() {
      _buying = true;
      _storeMessage = null;
    });

    try {
      final uid = await _ensureSignedIn();
      if (uid == null) {
        if (!mounted) return;
        setState(() {
          _buying = false;
          _storeMessage = 'Sign in with Google to restore your purchases.';
        });
        return;
      }
      await _subscriptionService.restorePurchases();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _buying = false;
        _storeMessage = 'Could not restore purchases: $error';
      });
    }
  }

  Future<String?> _ensureSignedIn() async {
    final currentUid = _uid;
    if (currentUid != null && currentUid.trim().isNotEmpty) return currentUid;

    final uid = await widget.onSignIn();
    if (uid != null && uid.trim().isNotEmpty) {
      _uid = uid;
      return uid;
    }
    return null;
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final uid = _uid;
      if (uid == null || uid.trim().isEmpty) {
        if (mounted) {
          setState(() {
            _buying = false;
            _storeMessage = 'Sign in with Google to verify this purchase.';
          });
        }
        continue;
      }
      final result = await _subscriptionService.handlePurchaseUpdate(
        uid: uid,
        purchase: purchase,
      );
      if (!mounted || result == null) continue;

      setState(() {
        _buying = false;
        _storeMessage = result.message;
      });

      if (result.plan == SubscriptionPlan.pro) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _selectedProduct;

    return Scaffold(
      backgroundColor: const Color(0xFF030817),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030817),
        title: const Text('DBPilot Pro'),
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  children: [
                    _PaywallHero(theme: theme),
                    const SizedBox(height: 26),
                    const _ProBenefits(
                      features: [
                        _PlanFeature(
                            Icons.all_inclusive_rounded,
                            'Unlimited connections',
                            'Connect every database you work with'),
                        _PlanFeature(Icons.mic_rounded, 'Voice SQL',
                            'Build SQL requests using your voice'),
                        _PlanFeature(Icons.code_rounded, 'Advanced SQL',
                            'CREATE, INSERT, UPDATE, DELETE and more'),
                        _PlanFeature(
                            Icons.history_rounded,
                            'Full query history',
                            'Keep and revisit all your executed queries'),
                        _PlanFeature(Icons.file_download_outlined,
                            'All export formats', 'Excel, JSON and CSV'),
                        _PlanFeature(
                            Icons.dns_outlined,
                            'All database providers',
                            'SQL Server, PostgreSQL and Oracle'),
                      ],
                    ),
                    const SizedBox(height: 22),
                    _ProPlanSelector(
                      products: _products,
                      selectedProduct: _selectedProduct,
                      loading: _loadingProduct,
                      onSelected: _buying
                          ? null
                          : (selected) {
                              setState(() {
                                _selectedProduct = selected;
                              });
                            },
                    ),
                  ],
                ),
              ),
              if (_storeMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    _storeMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              _PaywallActions(
                busy: _loadingProduct || _buying,
                product: product,
                onUpgrade: _loadingProduct || _buying || product == null
                    ? null
                    : _buyPro,
                onRestore:
                    _loadingProduct || _buying ? null : _restorePurchases,
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
            Image.asset(AppAssets.appIcon, width: 40, height: 40),
            const SizedBox(width: 10),
            const Text(
              'DBPilot',
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 0),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF1D7BF2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Text(
          'Your database workspace, without limits',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.12,
              letterSpacing: 0),
        ),
        const SizedBox(height: 10),
        Text(
          'Everything you need to connect, query and export with confidence.',
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

class _ProBenefits extends StatelessWidget {
  const _ProBenefits({required this.features});

  final List<_PlanFeature> features;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1527),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF24344E)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < features.length; i++) ...[
            if (i > 0)
              Divider(color: Colors.white.withOpacity(0.08), height: 1),
            _PlanFeatureRow(feature: features[i]),
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
  const _PlanFeatureRow({required this.feature});

  final _PlanFeature feature;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF0B315A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(feature.icon, color: const Color(0xFF48A7FF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0)),
                const SizedBox(height: 3),
                Text(feature.subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.66), height: 1.25)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF41D69B), size: 20),
        ],
      ),
    );
  }
}

class _ProPlanSelector extends StatelessWidget {
  const _ProPlanSelector({
    required this.products,
    required this.selectedProduct,
    required this.loading,
    required this.onSelected,
  });

  final List<SubscriptionProduct> products;
  final SubscriptionProduct? selectedProduct;
  final bool loading;
  final ValueChanged<SubscriptionProduct>? onSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (products.isEmpty) {
      return const Text(
        'Subscription price unavailable',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white60,
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      );
    }

    return Column(
      children: [
        for (final product in products) ...[
          _ProPlanOption(
            product: product,
            selected: product.id == selectedProduct?.id,
            onTap: onSelected == null ? null : () => onSelected!(product),
          ),
          if (product != products.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ProPlanOption extends StatelessWidget {
  const _ProPlanOption({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  final SubscriptionProduct product;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final yearly = product.period == SubscriptionProductPeriod.yearly;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0D2B4D) : const Color(0xFF0A1221),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF48A7FF)
                  : Colors.white.withOpacity(0.14),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? const Color(0xFF9FC2FF) : Colors.white54,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          product.period.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        if (yearly) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF173F2F),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    const Color(0xFF41D69B).withOpacity(0.45),
                              ),
                            ),
                            child: const Text(
                              'BEST VALUE',
                              style: TextStyle(
                                color: Color(0xFF8DF0C1),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      product.description.isEmpty
                          ? 'DBPilot Pro subscription'
                          : product.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${product.displayPrice} / ${product.period.suffix}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallActions extends StatelessWidget {
  const _PaywallActions({
    required this.onUpgrade,
    required this.onRestore,
    required this.onContinue,
    required this.busy,
    required this.product,
  });

  final VoidCallback? onUpgrade;
  final VoidCallback? onRestore;
  final VoidCallback onContinue;
  final bool busy;
  final SubscriptionProduct? product;

  @override
  Widget build(BuildContext context) {
    final selectedProduct = product;
    final upgradeLabel = selectedProduct == null
        ? 'Start DBPilot Pro'
        : 'Start ${selectedProduct.period.label} Pro - ${selectedProduct.displayPrice}';

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
                gradient: const LinearGradient(
                    colors: [Color(0xFF1EA7FF), Color(0xFFB536F5)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: FilledButton.icon(
                onPressed: onUpgrade,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.workspace_premium_rounded),
                label: Text(
                  upgradeLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRestore,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('Restore purchases'),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Continue with Free',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined,
                  size: 14, color: Color(0xFFB38CFF)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Secure payment managed by your app store. Cancel anytime.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.62), fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
