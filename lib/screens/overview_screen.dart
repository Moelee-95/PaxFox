import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger_queries.dart';
import '../core/presentation/account_balance_card.dart';
import '../core/presentation/metric_card.dart';
import '../core/presentation/responsive_pair.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.store,
    required this.month,
    required this.summary,
    required this.onOpenRecurring,
    this.recurringError,
  });

  final LedgerStore store;
  final DateTime month;
  final MonthlyLedger summary;
  final VoidCallback onOpenRecurring;
  final String? recurringError;

  Widget _monthlyOverview(BuildContext context) {
    final monthly = summary.totalsFor(store.currency);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final balances = store.currentBalances;
    final wealth = store.netWealth;
    final available = balances.available;
    final blocked = balances.blocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Monthly overview',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Text(
                    '${month.year}-${month.month.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Net cashflow: ${store.currency.display(monthly.net)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Income minus spending after refunds',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ResponsivePair(
          left: MetricCard(
            text: 'Income: ${store.currency.display(monthly.income)}',
            icon: Icons.payments_outlined,
            color: Colors.green,
          ),
          right: MetricCard(
            text:
                'Spending after refunds: ${store.currency.display(monthly.spending)}',
            icon: Icons.shopping_bag_outlined,
            color: Colors.red,
          ),
        ),
        const SizedBox(height: 10),
        ResponsivePair(
          left: MetricCard(
            text:
                'Account wealth: ${store.currency.symbol}${store.currency.format(wealth)}',
            detail:
                'Outstanding debts: ${store.currency.display(store.totalDebt)}',
            icon: Icons.account_balance_outlined,
            color: colors.primary,
          ),
          right: MetricCard(
            text:
                'Available to spend: ${store.currency.symbol}${store.currency.format(available)}',
            icon: Icons.account_balance_wallet_outlined,
            color: colors.primary,
            detail:
                'Excludes blocked accounts: ${store.currency.symbol}${store.currency.format(blocked)}',
          ),
        ),
        if (store.hasLegacyCurrencyData)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Existing data in other currencies is preserved and excluded from these totals.',
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
    children: [
      _monthlyOverview(context),
      if (recurringError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(recurringError!),
        ),
      const SizedBox(height: 20),
      if (store.recurringOccurrences.any((o) => o.status == 'failed'))
        TextButton(
          onPressed: onOpenRecurring,
          child: const Text('Review unpaid recurring payments'),
        ),
      Text(
        'Account balances today',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (store.accounts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No accounts configured. Add an opening balance to track available cash.',
          ),
        ),
      if (store.accounts.isNotEmpty)
        SizedBox(
          height: 128 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: store.accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final account = store.accounts[index];
              final balance =
                  store.currentBalances.byAccount[account.id] ??
                  account.opening;
              return AccountBalanceCard(account: account, balance: balance);
            },
          ),
        ),
    ],
  );
}
