import 'package:flutter/material.dart';

import '../core/domain/ledger.dart';
import '../core/domain/ledger_queries.dart';
import '../core/presentation/transaction_list.dart';
import '../core/presentation/category_icons.dart';

class MonthlyOverview extends StatelessWidget {
  const MonthlyOverview({
    super.key,
    required this.summary,
    required this.currency,
    required this.categoryIcon,
    this.categoryColor,
    required this.tileBuilder,
    required this.onCategoryChanged,
    this.selectedCategory,
  });
  final MonthlyLedger summary;
  final Currency currency;
  final IconData Function(String) categoryIcon;
  final Color? Function(String)? categoryColor;

  final Widget Function(LedgerEntry) tileBuilder;
  final ValueChanged<String?> onCategoryChanged;
  final String? selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final categories = summary.rankedCategories(currency);
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
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
              ],
            ),
          ),
        ),
        if (selectedCategory == null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final item = categories[index];
                final name = item.key.$2;
                return _CategorySummaryCard(
                  name: name,
                  amount: item.value,
                  maxAmount: maxAmount,
                  currency: currency,
                  icon: categoryIcon(name),
                  color: categoryColor?.call(name),
                  onTap: () => onCategoryChanged(name),
                );
              },
            ),
          ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Text('Refunds reduce spending. Transfers are excluded.'),
          ),
        ),
        if (selectedCategory != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverTransactionList(
              entries: summary.spendingForCategory(currency, selectedCategory!),
              tileBuilder: tileBuilder,
              emptyMessage: 'No transactions in this category for this month.',
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({
    required this.name,
    required this.amount,
    required this.maxAmount,
    required this.currency,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String name;
  final int amount;
  final int maxAmount;
  final Currency currency;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    color?.withValues(alpha: .18) ?? colors.secondaryContainer,
                foregroundColor: color ?? colors.onSecondaryContainer,
                child: categoryGlyph(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: maxAmount == 0 ? 0 : amount.abs() / maxAmount,
                      color: amount < 0
                          ? Colors.green
                          : color ?? colors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(currency.display(amount), style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
