import 'package:dbpilot/core/constants/app_assets.dart';
import 'package:flutter/material.dart';

import '../../models/connection_profile.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.profile,
    this.onConnect,
  });

  final ConnectionProfile profile;
  final VoidCallback? onConnect;

  String _providerAsset() {
    switch (profile.provider.name) {
      case 'sqlServer':
        return AppAssets.sqlServer;
      case 'oracle':
        return AppAssets.oracle;
      case 'postgresql':
        return AppAssets.postgre;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerAsset = _providerAsset();

    return Card(
      color: const Color(0xFF132238),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: providerAsset.isNotEmpty
                  ? Image.asset(
                      providerAsset,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: const Color(0xFF0D1828),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.storage_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: const Color(0xFF0D1828),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.storage_rounded,
                        color: Colors.white70,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile.provider.label} • ${profile.host}:${profile.port}',
                    style: const TextStyle(color: Colors.white70),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.database} • ${profile.username}',
                    style: const TextStyle(color: Colors.white54),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: onConnect,
              child: const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}
