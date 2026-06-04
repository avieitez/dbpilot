import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final provider = _providerFromMap(connection);

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
              _providerIcon(provider, active: isActive),
              const SizedBox(width: 14),
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
                      provider.label,
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
              subtitle: const Text('Only SELECT statements are allowed by default.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _confirmDangerousQueries,
              onChanged: (value) => _updateBoolSetting('settings.confirmDangerousQueries', value, (v) => _confirmDangerousQueries = v),
              title: const Text('Confirm dangerous queries'),
              subtitle: const Text('Ask before INSERT, UPDATE, DELETE, DROP and similar commands.'),
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
              title: 'Export / import settings',
              subtitle: 'Coming soon',
              onTap: () => _showInfo('Export / import settings will be added later.'),
            ),
            _actionTile(
              icon: Icons.cleaning_services_rounded,
              title: 'Clear local cache',
              subtitle: 'Coming soon',
              onTap: () => _showInfo('Local cache cleanup will be added later.'),
            ),
          ],
        ),
        _settingsSection(
          icon: Icons.info_outline_rounded,
          title: 'About',
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('DBPilot'),
              subtitle: Text('Version 0.1.0'),
            ),
            _actionTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy policy',
              subtitle: 'Coming soon',
              onTap: () => _showInfo('Privacy policy will be added later.'),
            ),
            _actionTile(
              icon: Icons.description_outlined,
              title: 'Terms',
              subtitle: 'Coming soon',
              onTap: () => _showInfo('Terms will be added later.'),
            ),
            _actionTile(
              icon: Icons.support_agent_rounded,
              title: 'Contact / support',
              subtitle: 'Coming soon',
              onTap: () => _showInfo('Support contact will be added later.'),
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
              onPressed: () => _showInfo('Paywall screen will be added next.'),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Upgrade to Pro'),
            ),
          ),
        ],
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
