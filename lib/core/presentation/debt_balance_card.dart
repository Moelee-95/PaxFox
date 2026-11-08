import 'package:flutter/material.dart';

import '../domain/ledger.dart';

/// One compact, adaptive card for both liabilities and receivables.
class DebtBalanceCard extends StatelessWidget {
  const DebtBalanceCard({
    super.key,
    required this.debt,
    required this.mainCurrency,
    required this.mainAmount,
    required this.onEdit,
    this.onSettle,
    this.onMissingRate,
  });
  final Debt debt;
  final Currency mainCurrency;
  final int? mainAmount;
  final VoidCallback onEdit;
  final VoidCallback? onSettle, onMissingRate;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final accent = debt.isReceivable
        ? (dark ? const Color(0xff67c596) : const Color(0xff218759))
        : (dark ? const Color(0xffff8790) : const Color(0xffce3541));
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: accent.withValues(alpha: dark ? .07 : .035),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent.withValues(alpha: .65)),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    debt.isReceivable
                        ? Icons.call_received
                        : Icons.account_balance_outlined,
                    color: accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      debt.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit debt ${debt.name}',
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final amount = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mainAmount == null
                            ? debt.currency.display(debt.amount)
                            : mainCurrency.display(mainAmount!),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (debt.currency != mainCurrency && mainAmount != null)
                        Text(
                          debt.currency.display(debt.amount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (mainAmount == null)
                        TextButton.icon(
                          onPressed: onMissingRate,
                          icon: const Icon(Icons.currency_exchange, size: 16),
                          label: Text('Set ${mainCurrency.code} conversion'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (debt.deadline != null)
                        Text(
                          'Due ${dayKey(debt.deadline!)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  );
                  final action = onSettle == null || debt.amount == 0
                      ? const SizedBox.shrink()
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: accent,
                            side: BorderSide(
                              color: accent.withValues(alpha: .6),
                            ),
                            backgroundColor: accent.withValues(alpha: .04),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: onSettle,
                          icon: Icon(
                            debt.isReceivable
                                ? Icons.call_received
                                : Icons.payments_outlined,
                            size: 16,
                          ),
                          label: Text(
                            debt.isReceivable ? 'Receive payment' : 'Pay debt',
                          ),
                        );
                  if (constraints.maxWidth < 300 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        amount,
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: amount),
                      const SizedBox(width: 8),
                      action,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
