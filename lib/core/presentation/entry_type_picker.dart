import 'package:flutter/material.dart';

import '../domain/ledger.dart';

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
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4
                ? 1
                : constraints.maxWidth >= 650
                ? 4
                : 2;
            final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in <EntryType?>[if (allowAll) null, ...types])
                  SizedBox(
                    width: width,
                    child: ChoiceChip(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                      showCheckmark: false,
                      avatar: Icon(switch (type) {
                        EntryType.expense => Icons.shopping_bag_outlined,
                        EntryType.income => Icons.payments_outlined,
                        EntryType.refund => Icons.undo,
                        EntryType.transfer => Icons.swap_horiz,
                        null => Icons.list_alt,
                      }),
                      label: Text(
                        type == null
                            ? 'All types'
                            : '${type.name[0].toUpperCase()}${type.name.substring(1)}',
                      ),
                      selected: value == type,
                      onSelected: onChanged == null
                          ? null
                          : (_) => onChanged!(type),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
