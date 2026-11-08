import 'package:flutter/material.dart';

import '../core/domain/ledger.dart';
import '../core/presentation/transaction_list.dart';
import '../core/presentation/entry_type_picker.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.entries,
    required this.search,
    required this.type,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.tileBuilder,
    this.invoiceGroups = const {},
  });

  final List<LedgerEntry> entries;
  final String search;
  final EntryType? type;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<EntryType?> onTypeChanged;
  final Widget Function(LedgerEntry) tileBuilder;
  final Map<int, InvoiceGroupInfo> invoiceGroups;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  late final _search = TextEditingController(text: widget.search);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Search description, category or notes',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: widget.onSearchChanged,
              ),
              EntryTypePicker(
                value: widget.type,
                allowAll: true,
                onChanged: widget.onTypeChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverTransactionList(
                  entries: widget.entries,
                  tileBuilder: widget.tileBuilder,
                  invoiceGroups: widget.invoiceGroups,
                  emptyMessage: 'No matching transactions.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
