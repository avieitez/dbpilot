import 'package:flutter/material.dart';

class SavedConnectionCard extends StatelessWidget {
  const SavedConnectionCard({
    super.key,
    required this.provider,
    required this.name,
    required this.isConnected,
    this.trailing,
  });

  final String provider;
  final String name;
  final bool isConnected;
  final Widget? trailing;

  String _providerAsset(String provider) {
    switch (provider.toLowerCase().trim()) {
      case 'postgresql':
      case 'postgres':
        return 'assets/providers/postgre.png';
      case 'oracle':
        return 'assets/providers/oracle.png';
      case 'sql server':
      case 'sqlserver':
      case 'sql_server':
      case 'mssql':
        return 'assets/providers/sql_server.png';
      default:
        return 'assets/icons/database.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerAsset = _providerAsset(provider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF132A4A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF2D8CFF).withOpacity(0.30),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF233F6B),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Image.asset(
              providerAsset,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.storage_rounded,
                  size: 34,
                  color: Colors.white,
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  provider,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (trailing != null) trailing!,
          if (trailing == null && isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
        ],
      ),
    );
  }
}