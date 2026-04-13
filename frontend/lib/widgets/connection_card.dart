import 'package:flutter/material.dart';

import '../models/connection_profile.dart';

class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.profile,
    this.onConnect,
  });

  final ConnectionProfile profile;
  final VoidCallback? onConnect;

  Color _providerColor() {
    final colors = {
      'sqlServer': const Color(0xFF2D8CFF),
      'oracle': const Color(0xFFFF7B54),
      'postgresql': const Color(0xFF4ED2C4),
    };

    return colors[profile.provider.name] ?? Colors.grey;
  }

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
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _providerColor(),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (profile.isFavorite)
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD54F),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${profile.provider.label} • ${profile.host}:${profile.port}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.database} • ${profile.username}',
                    style: const TextStyle(color: Colors.white54),
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
