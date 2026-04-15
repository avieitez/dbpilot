import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../models/database_provider.dart';
import '../../services/saved_connection_storage_service.dart';
import '../widgets/saved_connection_card.dart';
import 'connection_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storageService = SavedConnectionStorageService();

  BannerAd? _bannerAd;
  bool _loadingConnections = true;
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadSavedConnections();
    _loadBanner();
  }

  Future<void> _loadSavedConnections() async {
    final items = await _storageService.getSavedConnections();
    if (!mounted) return;

    setState(() {
      _connections = items.reversed.toList();
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

  @override
  void dispose() {
    _bannerAd?.dispose();
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
                          ..._connections.map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => _openConnectionScreen(initialData: c),
                                child: SavedConnectionCard(
                                  provider: _providerLabel(c['provider'] ?? ''),
                                  name: c['name'] ?? '',
                                  isConnected: false,
                                  onDelete: () => _deleteConnection(c),
                                ),
                              ),
                            ),
                          ),
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
                          Card(
                            color: const Color(0xFF132238),
                            child: ListTile(
                              leading: const Icon(
                                Icons.query_stats_rounded,
                                color: Colors.white70,
                              ),
                              title: const Text('Daily Sales Report'),
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
