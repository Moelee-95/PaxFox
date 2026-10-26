import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/presentation/account_balance_card.dart';
import '../core/presentation/metric_card.dart';
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
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (store.accounts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No accounts configured. Add an opening balance to track available cash.',
          ),
        ),
      for (final account in store.accounts)
        AccountBalanceCard(
          account: account,
          balance:
              store.currentBalances.byAccount[account.id] ?? account.opening,
          onEdit: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AccountForm(store: store, account: account),
            ),
          ),
        ),
      const SizedBox(height: 24),
      Text(
        'Debts',
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
      const SizedBox(height: 8),
      if (store.debts.isEmpty) const Text('No outstanding debts.'),
      for (final debt in store.debts)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_outlined,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        debt.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Future<void> _editDebt(BuildContext context, Debt debt) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DebtEditor(
      currency: store.currency,
      debt: debt,
      onSave: store.saveDebt,
      onDelete: () => store.deleteDebt(debt.id!),
    ),
  );
}
