import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../models/connection_request.dart';
import '../../models/database_provider.dart';
import '../../services/connection_api_service.dart';
import '../../services/saved_connection_storage_service.dart';
import '../widgets/saved_connection_card.dart';
import 'connection_screen.dart';
import 'oracle_main.dart';
import 'postgresql_main.dart';
import 'sqlserver_main.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storageService = SavedConnectionStorageService();
  final _apiService = ConnectionApiService();

  BannerAd? _bannerAd;
  bool _loadingConnections = true;
  bool _connecting = false;
  int _selectedIndex = 0;

  List<Map<String, dynamic>> _connections = [];
  String? _activeConnectionId;
  Map<String, dynamic>? _activeConnection;

  @override
  void initState() {
    super.initState();
    _loadSavedConnections();
    _loadBanner();
  }

  Future<void> _loadSavedConnections() async {
    final items = await _storageService.getSavedConnections();
    final activeId = await _storageService.getActiveConnectionId();

    Map<String, dynamic>? active;
    if (activeId != null) {
      for (final item in items) {
        if (item['id']?.toString() == activeId) {
          active = item;
          break;
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _connections = items.reversed.toList();
      _activeConnectionId = activeId;
      _activeConnection = active;
      _loadingConnections = false;
    });
  }

  void _loadBanner() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-3940256099942544/6300978111',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) => ad.dispose(),
      ),
    )..load();
  }

  Future<void> _openConnectionScreen({Map<String, dynamic>? initialData}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(initialData: initialData),
      ),
    );

    if (!mounted) return;
    await _loadSavedConnections();
  }

  Future<void> _deleteConnection(Map<String, dynamic> connection) async {
    final connectionId = _storageService.ensureConnectionId(connection);
    await _storageService.deleteConnectionById(connectionId);
    await _loadSavedConnections();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection deleted.')),
    );
  }

  Future<void> _openProviderMain(ConnectionRequest request) async {
    final databaseName = (request.database ?? '').trim().isNotEmpty
        ? request.database!.trim()
        : (request.provider == DatabaseProvider.postgresql ? 'postgres' : 'master');

    final oracleTarget = (request.serviceName ?? '').trim().isNotEmpty
        ? request.serviceName!.trim()
        : (request.sid ?? '').trim().isNotEmpty
            ? request.sid!.trim()
            : databaseName;

    Widget screen;
    switch (request.provider) {
      case DatabaseProvider.sqlServer:
        screen = SqlServerMain(
          connectionName: request.name,
          host: request.host,
          database: databaseName,
        );
        break;
      case DatabaseProvider.postgresql:
        screen = PostgreSqlMain(
          connectionName: request.name,
          host: request.host,
          database: databaseName,
        );
        break;
      case DatabaseProvider.oracle:
        screen = OracleMain(
          connectionName: request.name,
          host: request.host,
          targetName: oracleTarget.isEmpty ? 'XE' : oracleTarget,
        );
        break;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _activateSavedConnection(Map<String, dynamic> connection) async {
    setState(() => _connecting = true);

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      final connectionId = _storageService.ensureConnectionId(connection);
      final fullConnection = await _storageService.getConnectionById(connectionId);

      if (fullConnection == null) {
        throw Exception('Connection not found.');
      }

      final request = ConnectionRequest(
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

      final result = await _apiService.testConnection(request);

      if (!mounted) return;

      if (!result.success) {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
        return;
      }

      await _storageService.setActiveConnectionId(connectionId);
      await _loadSavedConnections();

      if (!mounted) return;

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.durationMs == null
                ? 'Connected successfully.'
                : 'Connected successfully (${result.durationMs} ms).',
          ),
        ),
      );

      await _openProviderMain(request);
    } catch (error) {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        setState(() => _connecting = false);
      }
    }
  }

  String _providerLabel(String providerName) {
    return DatabaseProviderX.fromString(providerName).label;
  }

  Widget _buildAdSection() {
    if (_bannerAd != null) {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: Center(
          child: SizedBox(
            width: _bannerAd!.size.width.toDouble(),
            height: _bannerAd!.size.height.toDouble(),
            child: AdWidget(ad: _bannerAd!),
          ),
        ),
      );
    }

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF132238),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'Ad banner area',
          style: TextStyle(color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildActiveConnectionCard() {
    if (_activeConnection == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF132238),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Connection',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No active connection selected.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF132238),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2D8CFF).withOpacity(0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Active Connection',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _activeConnection!['name']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_providerLabel(_activeConnection!['provider'] ?? '')}  •  ${_activeConnection!['host'] ?? ''}:${_activeConnection!['port'] ?? ''}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _apiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActiveConnectionCard(),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'My Connections',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openConnectionScreen(),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loadingConnections
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          ..._connections.map((c) {
                            final connectionId = _storageService.ensureConnectionId(c);
                            final isActive = connectionId == _activeConnectionId;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: _connecting ? null : () => _activateSavedConnection(c),
                                child: SavedConnectionCard(
                                  provider: _providerLabel(c['provider'] ?? ''),
                                  name: c['name'] ?? '',
                                  isConnected: isActive,
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1D4D3C),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(
                                              color: Colors.green.withOpacity(0.35),
                                            ),
                                          ),
                                          child: const Text(
                                            'Active',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          if (value == 'connect') {
                                            await _activateSavedConnection(c);
                                          } else if (value == 'edit') {
                                            await _openConnectionScreen(initialData: c);
                                          } else if (value == 'delete') {
                                            await _deleteConnection(c);
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
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 20),
                          const Text(
                            'Recent Queries',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Card(
                            color: const Color(0xFF132238),
                            child: ListTile(
                              leading: const Icon(
                                Icons.query_stats_rounded,
                                color: Colors.white70,
                              ),
                              title: const Text('Top Customers Q1'),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
              ),
              const SizedBox(height: 4),
              _buildAdSection(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storage_rounded),
            selectedIcon: Icon(Icons.storage_rounded),
            label: 'Connections',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_rounded),
            selectedIcon: Icon(Icons.menu_rounded),
            label: 'Queries',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
