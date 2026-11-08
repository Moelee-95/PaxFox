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
  });

  final LedgerEntry entry;
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
                        final metadataStyle = theme.textTheme.bodySmall
                            ?.copyWith(
                              fontSize: 12,
                              height: 1.3,
                              color: colors.onSurfaceVariant,
                            );
                        final details = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            description,
                            if (entry.createdAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Tooltip(
                                  message: 'Added on',
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.history_outlined,
                                        size: 13,
                                        color: colors.onSurfaceVariant,
                                        semanticLabel: 'Added on',
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          creationTimestamp(
                                            context,
                                            entry.createdAt!,
                                          ),
                                          style: metadataStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                        final money = Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            price,
                            const SizedBox(height: 3),
                            Tooltip(
                              message: 'Transaction date',
                              child: Text(
                                dayKey(entry.date),
                                style: metadataStyle,
                              ),
                            ),
                          ],
                        );
                        final heading =
                            constraints.maxWidth < 230 ||
                                textScale > 1.3 ||
                                amount.length > 14
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  details,
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: money,
                                  ),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: details),
                                  const SizedBox(width: 8),
                                  money,
                                ],
                              );
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading,
                            if (entry.type == EntryType.refund)
                              Text('Refund', style: metadataStyle),
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
