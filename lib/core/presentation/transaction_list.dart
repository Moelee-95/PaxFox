import 'package:flutter/material.dart';

import '../domain/ledger.dart';

/// Lazy rows supplied by the shell retain its shared editing and selection actions.
class SliverTransactionList extends StatelessWidget {
  const SliverTransactionList({
    super.key,
    required this.entries,
    required this.tileBuilder,
    required this.emptyMessage,
  });
  final List<LedgerEntry> entries;
  final Widget Function(LedgerEntry) tileBuilder;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => entries.isEmpty
      ? SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(emptyMessage),
          ),
        )
      : SliverList.builder(
          itemCount: entries.length,
          itemBuilder: (_, index) => tileBuilder(entries[index]),
        );
}
