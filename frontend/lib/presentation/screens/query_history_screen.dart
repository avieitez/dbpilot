import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/query_history_storage_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../screens/query_editor/query_editor_screen.dart';

class QueryHistoryScreen extends StatefulWidget {
  const QueryHistoryScreen({super.key});

  @override
  State<QueryHistoryScreen> createState() => _QueryHistoryScreenState();
}

class _QueryHistoryScreenState extends State<QueryHistoryScreen> {
  final _historyService = QueryHistoryStorageService();
  final _connectionStorageService = SavedConnectionStorageService();
  final _apiService = ConnectionApiService();

  bool _loading = true;
  String? _openingQueryId;
  List<QueryHistoryItem> _queries = [];
  List<Map<String, dynamic>> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final queries = await _historyService.getQueries();
    final connections = await _connectionStorageService.getSavedConnections();

    if (!mounted) return;

    setState(() {
      _queries = queries;
      _connections = connections;
      _loading = false;
    });
  }

  Map<DatabaseProvider, List<QueryHistoryItem>> _groupByProvider() {
    final grouped = <DatabaseProvider, List<QueryHistoryItem>>{
      DatabaseProvider.sqlServer: [],
      DatabaseProvider.postgresql: [],
      DatabaseProvider.oracle: [],
    };

    for (final query in _queries) {
      final provider = DatabaseProviderX.fromString(query.provider);
      grouped[provider]!.add(query);
    }

    return grouped;
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(hour12)}:${two(value.minute)} $period';
  }

  String _connectionTarget(ConnectionRequest request) {
    if (request.provider == DatabaseProvider.oracle) {
      final serviceName = request.serviceName?.trim();
      final sid = request.sid?.trim();

      if (serviceName != null && serviceName.isNotEmpty) {
        return serviceName;
      }

      if (sid != null && sid.isNotEmpty) {
        return sid;
      }
    }

    return request.database;
  }

  Map<String, dynamic>? _findConnectionForQuery(QueryHistoryItem query) {
    final queryProvider = DatabaseProviderX.fromString(query.provider);
    final queryConnectionName = query.connectionName.trim().toLowerCase();

    for (final connection in _connections) {
      final provider = DatabaseProviderX.fromString(
        connection['provider']?.toString() ?? '',
      );

      final connectionName =
          connection['name']?.toString().trim().toLowerCase() ?? '';

      if (provider == queryProvider && connectionName == queryConnectionName) {
        return connection;
      }
    }

    for (final connection in _connections) {
      final provider = DatabaseProviderX.fromString(
        connection['provider']?.toString() ?? '',
      );

      if (provider == queryProvider) {
        return connection;
      }
    }

    return null;
  }

  Future<ConnectionRequest> _buildRequest(Map<String, dynamic> connection) async {
    final connectionId = _connectionStorageService.ensureConnectionId(connection);
    final fullConnection =
        await _connectionStorageService.getConnectionById(connectionId);

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

  Future<void> _openQuery(QueryHistoryItem query) async {
    if (_openingQueryId != null) return;

    final connection = _findConnectionForQuery(query);

    if (connection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No compatible connection found for this query.'),
        ),
      );
      return;
    }

    setState(() => _openingQueryId = query.id);

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

      await _connectionStorageService.setActiveConnectionId(
        _connectionStorageService.ensureConnectionId(connection),
      );

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
        setState(() => _openingQueryId = null);
      }
    }
  }

  @override
  void dispose() {
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByProvider();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queries'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _queries.isEmpty
                ? const Center(
                    child: Text('No saved queries.'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      for (final provider in DatabaseProvider.values) ...[
                        if ((grouped[provider] ?? []).isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
                            child: Text(
                              provider.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          ...grouped[provider]!.map((query) {
                            final preview = query.sql.replaceAll('\n', ' ');
                            final isOpening = _openingQueryId == query.id;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: const Icon(Icons.history_rounded),
                                title: Text(
                                  query.connectionName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                                trailing: isOpening
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.open_in_new_rounded),
                                onTap: _openingQueryId == null
                                    ? () => _openQuery(query)
                                    : null,
                              ),
                            );
                          }),
                        ],
                      ],
                    ],
                  ),
      ),
    );
  }
}
