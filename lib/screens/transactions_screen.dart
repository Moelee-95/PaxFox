import 'package:flutter/material.dart';

import '../core/domain/ledger.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({
    super.key,
    required this.entries,
    required this.search,
    required this.type,
    required this.onSearchChanged,
    required this.onTypeChanged,
    required this.tileBuilder,
  });

  final List<LedgerEntry> entries;
  final String search;
  final EntryType? type;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<EntryType?> onTypeChanged;
  final Widget Function(LedgerEntry) tileBuilder;

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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<EntryType>(
                      initialValue: widget.type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All types'),
                        ),
                        ...EntryType.values.map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)),
                        ),
                      ],
                      onChanged: widget.onTypeChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (widget.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching transactions.'),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.entries.length,
            itemBuilder: (_, index) =>
                widget.tileBuilder(widget.entries[index]),
          ),
        ),
      ],
    );
  }
}
