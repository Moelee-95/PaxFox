import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'selection_cards.dart';

/// The small, fixed set of transaction types stays visible and easy to select.
class EntryTypePicker extends StatelessWidget {
  const EntryTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.types = EntryType.values,
    this.allowAll = false,
    this.label = 'Transaction type',
  });

  final EntryType? value;
  final ValueChanged<EntryType?>? onChanged;
  final List<EntryType> types;
  final bool allowAll;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SelectionRow(
          count: types.length + (allowAll ? 1 : 0),
          itemBuilder: (context, index) {
            final type = allowAll && index == 0
                ? null
                : types[index - (allowAll ? 1 : 0)];
            return SelectionCard(
              key: ValueKey('entry-type-${type?.name ?? 'all'}'),
              width: 148,
              selected: value == type,
              icon: switch (type) {
                EntryType.expense => Icons.shopping_bag_outlined,
                EntryType.income => Icons.payments_outlined,
                EntryType.refund => Icons.undo,
                EntryType.transfer => Icons.swap_horiz,
                null => Icons.list_alt,
              },
              title: type == null
                  ? 'All types'
                  : '${type.name[0].toUpperCase()}${type.name.substring(1)}',
              onTap: onChanged == null ? null : () => onChanged!(type),
            );
          },
        ),
      ],
    ),
  );
}
