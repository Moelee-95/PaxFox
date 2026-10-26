import 'package:flutter/material.dart';

import '../data/ledger_store.dart';

class LedgerRefresh extends StatelessWidget {
  const LedgerRefresh({super.key, required this.store, required this.child});
  final LedgerStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    notificationPredicate: (notification) =>
        notification.metrics.axis == Axis.vertical,
    onRefresh: () async {
      try {
        await store.refresh();
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not refresh data. Pull down to retry.'),
            ),
          );
        }
      }
    },
    child: child,
  );
}
