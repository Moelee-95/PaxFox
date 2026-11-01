import 'package:flutter/material.dart';

import 'busy_label.dart';

class BottomActionBar extends StatelessWidget {
  const BottomActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Saving...',
    this.icon,
    this.style,
    this.padding = const EdgeInsets.all(16),
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String busyLabel;
  final IconData? icon;
  final ButtonStyle? style;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: padding,
    child: icon == null
        ? FilledButton(
            style: style,
            onPressed: busy ? null : onPressed,
            child: BusyLabel(busy: busy, label: busy ? busyLabel : label),
          )
        : FilledButton.icon(
            style: style,
            onPressed: busy ? null : onPressed,
            icon: busy ? null : Icon(icon),
            label: BusyLabel(busy: busy, label: busy ? busyLabel : label),
          ),
  );
}
