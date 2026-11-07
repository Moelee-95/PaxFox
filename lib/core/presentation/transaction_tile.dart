import 'package:flutter/material.dart';

import '../domain/category.dart';
import '../domain/ledger.dart';
import 'category_icons.dart';
import 'category_colors.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onLongPress,
    this.categoryIcon = CategoryIcon.general,
    this.categoryColor,
    this.compact = false,
    this.selected = false,
    this.selectionMode = false,
    this.invoiceLabel,
  });

  final LedgerEntry entry;
  final String? invoiceLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final CategoryIcon categoryIcon;
  final Color? categoryColor;
  final bool compact;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final transfer = entry.type == EntryType.transfer;
    final label = transfer ? 'Transfer' : entry.category;
    final background = transfer
        ? colors.secondaryContainer
        : categoryColor ?? colors.surfaceContainerHighest;
    final amount =
        '${switch (entry.type) {
          EntryType.expense => '-',
          EntryType.income || EntryType.refund => '+',
          EntryType.transfer => '',
        }}${entry.currency.display(entry.amount)}';
    final dark = theme.brightness == Brightness.dark;
    final priceColor = switch (entry.type) {
      EntryType.expense => dark ? Colors.red.shade300 : Colors.red.shade700,
      EntryType.income ||
      EntryType.refund => dark ? Colors.green.shade300 : Colors.green.shade700,
      EntryType.transfer => dark ? Colors.blue.shade200 : Colors.blue.shade700,
    };
    final price = Text(
      amount,
      key: const ValueKey('transaction-price'),
      style: theme.textTheme.titleSmall?.copyWith(
        color: priceColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.1,
      ),
    );
    return Card(
      margin: EdgeInsets.symmetric(horizontal: compact ? 0 : 16, vertical: 1),
      color: selected
          ? colors.secondaryContainer
          : colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Semantics(
        selected: selected,
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          onLongPress: onLongPress,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: 6,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  DecoratedBox(
                    key: const ValueKey('transaction-category-badge'),
                    decoration: BoxDecoration(
                      color: background,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Center(
                        child: categoryGlyph(
                          transfer
                              ? Icons.swap_horiz
                              : categoryIconData(categoryIcon),
                          size: 20,
                          color: categoryForeground(background),
                          semanticLabel: '${entry.type.name} - $label',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(16) / 16;
                        final description = Text(
                          entry.description.isNotEmpty
                              ? entry.description
                              : transfer
                              ? 'Transfer'
                              : 'Transaction',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            color: colors.onSurface,
                          ),
                        );
                        // Measure the available text column once for both lines.
                        final heading =
                            constraints.maxWidth < 180 ||
                                textScale > 1.3 ||
                                amount.length > 14
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  description,
                                  const SizedBox(height: 1),
                                  price,
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: description),
                                  const SizedBox(width: 6),
                                  price,
                                ],
                              );
                        final metadataStyle = theme.textTheme.bodySmall
                            ?.copyWith(
                              fontSize: 12,
                              height: 1.3,
                              color: colors.onSurfaceVariant,
                            );
                        // One paragraph wraps naturally and avoids laying out
                        // a separate text render object for each date label.
                        final metadata = Text(
                          [
                            if (entry.createdAt != null)
                              'Added on ${creationTimestamp(context, entry.createdAt!)}',
                            'Date: ${dayKey(entry.date)}${entry.type == EntryType.refund ? ' \u00b7 Refund' : ''}',
                          ].join('  \u00b7  '),
                          style: metadataStyle,
                        );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            const SizedBox(height: 3),
                            metadata,
                            if (invoiceLabel != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: 14,
                                      color: colors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        invoiceLabel!,
                                        style: metadataStyle?.copyWith(
                                          color: colors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (entry.fx != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                transfer
                                    ? '${entry.fx!.sourceCurrency.display(entry.fx!.sourceAmount)} \u2192 ${entry.fx!.targetCurrency!.display(entry.fx!.targetAmount!)}\n${entry.fx!.transferRate}'
                                    : '${entry.fx!.sourceCurrency.display(entry.fx!.sourceAmount)} \u00b7 1 ${entry.currency.code} = ${entry.fx!.sourceRate} ${entry.fx!.sourceCurrency.code}',
                                style: metadataStyle,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  if (selectionMode) ...[
                    const SizedBox(width: 8),
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      semanticLabel: selected ? 'Selected' : 'Not selected',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String creationTimestamp(BuildContext context, DateTime timestamp) {
  final local = timestamp.toLocal();
  final locale = MaterialLocalizations.of(context);
  return '${locale.formatCompactDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
}
