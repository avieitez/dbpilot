import 'package:flutter/material.dart';

import '../../models/database_provider.dart';

class ProviderSelectorCard extends StatelessWidget {
  const ProviderSelectorCard({
    super.key,
    required this.provider,
    required this.selected,
    required this.onTap,
  });

  final DatabaseProvider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF132238) : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF1EA7FF)
                : theme.colorScheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF1EA7FF).withOpacity(0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              provider.asset,
              width: 32,
              height: 32,
            ),
            const SizedBox(height: 12),
            Text(
              provider.label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : null,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              provider.helperText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: selected ? Colors.white70 : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
