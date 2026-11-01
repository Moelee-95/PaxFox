import 'package:flutter/material.dart';

/// Consistent progress feedback without changing the button's label or height.
class BusyLabel extends StatelessWidget {
  const BusyLabel({super.key, required this.busy, required this.label});
  final bool busy;
  final String label;

  @override
  Widget build(BuildContext context) => !busy
      ? Text(label)
      : Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: 'Loading',
              ),
            ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(child: Text(label)),
            ],
          ],
        );
}
