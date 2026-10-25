import 'package:flutter/material.dart';

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.detail,
  });

  final String text;
  final IconData icon;
  final Color color;
  final String? detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 8),
        Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(height: 1.5),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}
