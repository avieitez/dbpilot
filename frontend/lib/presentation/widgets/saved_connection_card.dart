import 'package:flutter/material.dart';

class SavedConnectionCard extends StatelessWidget {
  const SavedConnectionCard({
    super.key,
    required this.provider,
    required this.name,
    required this.onDelete,
    this.isConnected = false,
  });

  final String provider;
  final String name;
  final VoidCallback onDelete;
  final bool isConnected;

  String _providerAsset() {
    switch (provider) {
      case 'SQL Server':
        return 'assets/providers/sql_server.png';
      case 'Oracle':
        return 'assets/providers/oracle.png';
      case 'PostgreSQL':
        return 'assets/providers/postgre.png';
      default:
        return 'assets/providers/database.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF132238),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Image.asset(_providerAsset()),
          ),
        ),

        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),

        subtitle: Text(
          provider,
          style: const TextStyle(color: Colors.white70),
        ),

        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isConnected ? Icons.check_circle : Icons.circle_outlined,
              color: isConnected ? Colors.green : Colors.white30,
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: Colors.white54,
            ),
          ],
        ),
      ),
    );
  }
}