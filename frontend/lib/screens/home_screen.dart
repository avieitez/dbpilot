import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/mock_connections_service.dart';
import '../widgets/connection_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _service = MockConnectionsService();
  late final List connections;
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    connections = _service.loadConnections();
    _loadBanner();
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

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icons/dbpilot_icon_1024.png', width: 28, height: 28),
            const SizedBox(width: 10),
            const Text('DBPilot'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('New Connection'),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Connect to your databases in seconds',
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Choose SQL Server, Oracle or PostgreSQL, then connect or manage existing instances.',
                              style: TextStyle(color: Colors.white70, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.storage_rounded, size: 48, color: Color(0xFF1EA7FF)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Saved Connections',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: connections.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => ConnectionCard(profile: connections[index]),
                ),
              ),
              const SizedBox(height: 12),
              if (_bannerAd != null)
                Center(
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                )
              else
                Card(
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    child: const Text('Ad banner area'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
