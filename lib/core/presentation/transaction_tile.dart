import 'package:flutter/material.dart';

import '../domain/category.dart';
import '../domain/ledger.dart';
import 'category_icons.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.categoryIcon = CategoryIcon.general,
    this.compact = false,
    this.selected = false,
    this.selectionMode = false,
  });

  final LedgerEntry entry;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final CategoryIcon categoryIcon;
  final bool compact;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: compact,
    visualDensity: compact ? VisualDensity.compact : null,
    contentPadding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    onLongPress: onLongPress,
    onTap: onTap,
    leading: Icon(
      entry.type == EntryType.transfer
          ? Icons.account_balance_outlined
          : categoryIconData(categoryIcon),
      color: transactionColor(entry.type),
      semanticLabel:
          '${entry.type.name} - ${entry.type == EntryType.transfer ? 'Transfer' : entry.category}',
    ),
    title: Text(entry.description),
    subtitle: Text(
      (compact
              ? dayKey(entry.date)
              : '${dayKey(entry.date)} · ${entry.type.name} · ${entry.category}') +
          (entry.createdAt == null
              ? ''
              : '\nAdded ${creationTimestamp(context, entry.createdAt!)}'),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(entry.currency.display(entry.amount)),
        if (selectionMode) ...[
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
        ],
      ],
    ),
  );
}

String creationTimestamp(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatCompactDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}
