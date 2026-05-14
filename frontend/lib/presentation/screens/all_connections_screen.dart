import 'package:flutter/material.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../screens/query_editor/query_editor_screen.dart';
import '../widgets/saved_connection_card.dart';

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

  void _showConnectingDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  void _closeConnectingDialog() {
    if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _openQueryEditor(Map<String, dynamic> connection) async {
    if (_connecting) return;

    setState(() => _connecting = true);
    _showConnectingDialog();

    try {
      final request = await _buildRequest(connection);
      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      _closeConnectingDialog();

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
          builder: (_) => QueryEditorScreen(
            connection: request,
            providerLabel: request.provider.label.toUpperCase(),
            connectionSummary:
                '${request.name}\n${request.host} / ${_connectionTarget(request)}',
          ),
        ),
      );
    } catch (error) {
      _closeConnectingDialog();

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
        child: _loading
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
                                onTap: _connecting
                                    ? null
                                    : () => _openQueryEditor(connection),
                                child: SavedConnectionCard(
                                  provider: provider.label,
                                  name: connection['name']?.toString() ?? '',
                                  isConnected: false,
                                  trailing: _connecting
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.open_in_new_rounded),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
      ),
    );
  }
}
