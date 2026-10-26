import 'package:flutter/material.dart';

import '../core/domain/ledger.dart';
import '../core/domain/ledger_queries.dart';
import '../core/presentation/transaction_list.dart';

class MonthlyOverview extends StatelessWidget {
  const MonthlyOverview({
    super.key,
    required this.summary,
    required this.currency,
    required this.categoryIcon,
    required this.tileBuilder,
    required this.onCategoryChanged,
    this.selectedCategory,
  });
  final MonthlyLedger summary;
  final Currency currency;
  final IconData Function(String) categoryIcon;

  final Widget Function(LedgerEntry) tileBuilder;
  final ValueChanged<String?> onCategoryChanged;
  final String? selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final categories =
        summary.spendingByCategory.entries
            .where((item) => item.key.$1 == currency)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final maxAmount = categories.fold<int>(
      0,
      (max, item) => item.value.abs() > max ? item.value.abs() : max,
    );
    return CustomScrollView(
      key: const PageStorageKey('home-monthly-overview'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverList.list(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Net cashflow: ${currency.display(summary.totalsFor(currency).net)}',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Income minus spending after refunds',
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Spending by category', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (selectedCategory != null)
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Back to categories',
                      onPressed: () => onCategoryChanged(null),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        selectedCategory!,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
              if (selectedCategory == null && categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('No expenses or refunds in this month.'),
                ),
              if (selectedCategory == null)
                for (final item in categories)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => onCategoryChanged(item.key.$2),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: colors.secondaryContainer,
                              foregroundColor: colors.onSecondaryContainer,
                              child: Icon(categoryIcon(item.key.$2)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.key.$2,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value: maxAmount == 0
                                        ? 0
                                        : item.value.abs() / maxAmount,
                                    color: item.value < 0
                                        ? Colors.green
                                        : colors.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              currency.display(item.value),
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Refunds reduce spending. Transfers are excluded.'),
              ),
            ],
          ),
        ),
        if (selectedCategory != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverTransactionList(
              entries: summary.spendingEntries
                  .where(
                    (entry) =>
                        entry.currency == currency &&
                        entry.category == selectedCategory,
                  )
                  .toList(),
              tileBuilder: tileBuilder,
              emptyMessage: 'No transactions in this category for this month.',
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}
