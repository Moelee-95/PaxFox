import 'package:flutter/material.dart';

import '../data/ledger_store.dart';

/// A committed write is never offered again when only its reload failed.
class StoreStatus extends StatefulWidget {
  const StoreStatus({super.key, required this.store, required this.child});
  final LedgerStore store;
  final Widget child;

  @override
  State<StoreStatus> createState() => _StoreStatusState();
}

class _StoreStatusState extends State<StoreStatus> {
  bool retrying = false;

  Future<void> retry() async {
    setState(() => retrying = true);
    try {
      await widget.store.refresh();
    } catch (_) {
      // Keep the last complete snapshot and leave Retry available.
    } finally {
      if (mounted) setState(() => retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    child: widget.child,
    builder: (context, child) {
      final stale = widget.store.snapshotNeedsRefresh;
      final colors = Theme.of(context).colorScheme;
      return Column(
        children: [
          if (stale)
            Material(
              color: colors.errorContainer,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Changes saved. Reload data to continue.',
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                      TextButton(
                        onPressed: retrying ? null : retry,
                        child: Text(retrying ? 'Reloading…' : 'Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: ExcludeFocus(
              excluding: stale,
              child: ExcludeSemantics(
                excluding: stale,
                child: AbsorbPointer(absorbing: stale, child: child),
              ),
            ),
          ),
        ],
      );
    },
  );
}
