import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/presentation/account_balance_card.dart';
import '../core/presentation/metric_card.dart';
import '../core/presentation/monthly_savings_chart.dart';
import '../core/presentation/responsive_pair.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/debt_editor.dart';
import 'accounts_screen.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({
    super.key,
    required this.store,
    required this.onOpenRecurring,
    this.recurringError,
  });

  final LedgerStore store;
  final VoidCallback onOpenRecurring;
  final String? recurringError;

  Widget _accountOverview(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final balances = store.currentBalances;
    final wealth = store.netWealth;
    final available = balances.available;
    final blocked = balances.blocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResponsivePair(
          left: MetricCard(
            label: 'Account wealth',
            amount: store.currency.display(wealth),
            detail:
                'Outstanding debts: ${store.currency.display(store.totalDebt)}',
            icon: Icons.account_balance_outlined,
            color: colors.primary,
          ),
          right: MetricCard(
            label: 'Available to spend',
            amount: store.currency.display(available),
            icon: Icons.account_balance_wallet_outlined,
            color: colors.primary,
            detail:
                'Excludes blocked accounts: ${store.currency.symbol}${store.currency.formatGrouped(blocked)}',
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = store.accounts;
    final debts = store.debts;
    final balances = store.currentBalances.byAccount;
    return CustomScrollView(
      key: const PageStorageKey('account-overview'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _accountOverview(context),
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
                  style: theme.textTheme.titleLarge,
                ),
                if (accounts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No accounts configured. Add an opening balance to track available cash.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final account = accounts[index];
              return AccountBalanceCard(
                account: account,
                balance: balances[account.id] ?? account.opening,
                onEdit: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AccountForm(store: store, account: account),
                  ),
                ),
              );
            },
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Debts',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                if (debts.isEmpty) const Text('No outstanding debts.'),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: debts.length,
            itemBuilder: (context, index) => _debtCard(context, debts[index]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          sliver: SliverToBoxAdapter(
            child: MonthlySavingsChart(
              currency: store.currency,
              summaryForMonth: store.monthSummary,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    );
  }

  Widget _debtCard(BuildContext context, Debt debt) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_outlined, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    debt.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit debt ${debt.name}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editDebt(context, debt),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            Text(
              store.currency.display(debt.amount),
              style: theme.textTheme.headlineSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editDebt(BuildContext context, Debt debt) => showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DebtEditor(
      currency: store.currency,
      debt: debt,
      onSave: store.saveDebt,
      onDelete: () => store.deleteDebt(debt.id!),
    ),
  );
}
