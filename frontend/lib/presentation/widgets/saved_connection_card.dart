import 'package:flutter/material.dart';

class SavedConnectionCard extends StatelessWidget {
  const SavedConnectionCard({
    super.key,
    required this.provider,
    required this.name,
    this.host,
    this.database,
    this.isConnected = false,
    this.trailing,
  });

  final String provider;
  final String name;
  final String? host;
  final String? database;
  final bool isConnected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF132238),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF2D8CFF).withOpacity(0.45)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFF203A5F)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.storage_rounded,
              color: isConnected ? const Color(0xFF9EC5FF) : Colors.white70,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Unnamed connection' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[];
    if (provider.trim().isNotEmpty) parts.add(provider.trim());
    if ((host ?? '').trim().isNotEmpty) parts.add(host!.trim());
    if ((database ?? '').trim().isNotEmpty) parts.add(database!.trim());
    return parts.isEmpty ? 'Database connection' : parts.join(' • ');
  }
}
