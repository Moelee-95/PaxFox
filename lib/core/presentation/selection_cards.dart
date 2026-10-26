import 'package:flutter/material.dart';

class SelectionRow extends StatelessWidget {
  const SelectionRow({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.controller,
  });
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
    child: ListView.separated(
      controller: controller,
      scrollDirection: Axis.horizontal,
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: itemBuilder,
    ),
  );
}

class SelectionCard extends StatelessWidget {
  const SelectionCard({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.width = 164,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Tooltip(
                          message: title,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        ?subtitle,
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 18,
                    )
                  else
                    const SizedBox(width: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
