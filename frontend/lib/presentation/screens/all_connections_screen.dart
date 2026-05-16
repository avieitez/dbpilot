import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../widgets/saved_connection_card.dart';

import 'connection_screen.dart';
import 'oracle_main.dart';
import 'postgresql_main.dart';
import 'sqlserver_main.dart';

class AllConnectionsScreen extends StatefulWidget {
  const AllConnectionsScreen({super.key});

  @override
  State<AllConnectionsScreen> createState() => _AllConnectionsScreenState();
}

class _AllConnectionsScreenState extends State<AllConnectionsScreen> {
  final _storageService = SavedConnectionStorageService();
  final _apiService = ConnectionApiService();

  bool _loading = true;
  bool _connecting = false;
  List<Map<String, dynamic>> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final items = await _storageService.getSavedConnections();

    if (!mounted) return;

    setState(() {
      _connections = items.reversed.toList();
      _loading = false;
    });
  }

  Map<DatabaseProvider, List<Map<String, dynamic>>> _groupByProvider() {
    final grouped = <DatabaseProvider, List<Map<String, dynamic>>>{
      DatabaseProvider.sqlServer: [],
      DatabaseProvider.postgresql: [],
      DatabaseProvider.oracle: [],
    };

    for (final connection in _connections) {
      final provider = DatabaseProviderX.fromString(
        connection['provider']?.toString() ?? '',
      );

      grouped[provider]!.add(connection);
    }

    return grouped;
  }

  Future<ConnectionRequest> _buildRequest(Map<String, dynamic> connection) async {
    final connectionId = _storageService.ensureConnectionId(connection);
    final fullConnection = await _storageService.getConnectionById(connectionId);

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

  Future<void> _connect(Map<String, dynamic> connection) async {
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

      await _storageService.setActiveConnectionId(
        _storageService.ensureConnectionId(connection),
      );

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

  Future<void> _deleteConnection(Map<String, dynamic> connection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete connection'),
        content: Text('Delete "${connection['name']}"?'),
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

    final connectionId = _storageService.ensureConnectionId(connection);

    await _storageService.deleteConnectionById(connectionId);
    await _loadConnections();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connection deleted.'),
      ),
    );
  }

  Future<void> _editConnection(Map<String, dynamic> connection) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(
          initialData: connection,
        ),
      ),
    );

    if (result == true) {
      await _loadConnections();
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
        title: const Text('Connections'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _connections.isEmpty
                    ? const Center(
                        child: Text('No saved connections.'),
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
                              ...grouped[provider]!.map(
                                (connection) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: _connecting ? null : () => _connect(connection),
                                    child: SavedConnectionCard(
                                      provider: provider.label,
                                      name: connection['name']?.toString() ?? '',
                                      isConnected: false,
                                      trailing: PopupMenuButton<String>(
                                        enabled: !_connecting,
                                        onSelected: (value) async {
                                          if (value == 'connect') {
                                            await _connect(connection);
                                          } else if (value == 'edit') {
                                            await _editConnection(connection);
                                          } else if (value == 'delete') {
                                            await _deleteConnection(connection);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(
                                            value: 'connect',
                                            child: Text('Connect'),
                                          ),
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                        icon: const Icon(Icons.more_vert_rounded),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
            if (_connecting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.15),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
