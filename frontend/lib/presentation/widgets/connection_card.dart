import 'package:dbpilot/models/database_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF132238),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1828),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Image.asset(
                      profile.provider.asset,
                      width: 32,
                      height: 32,
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
