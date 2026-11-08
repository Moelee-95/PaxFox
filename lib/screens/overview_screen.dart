import 'currency_exchange_screen.dart';

import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/presentation/account_balance_card.dart';
import '../core/presentation/metric_card.dart';
import '../core/presentation/monthly_savings_chart.dart';
import '../core/presentation/responsive_pair.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/debt_editor.dart';
import 'accounts_screen.dart';
import 'debt_settlement_form.dart';
import '../core/presentation/debt_balance_card.dart';
import '../core/presentation/app_sheet.dart';

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
                'Debts: ${store.currency.display(store.totalDebt)} | Owed to you: ${store.currency.display(store.totalReceivable)}',
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
    final debts = store.debts.where((d) => !d.isReceivable).toList();
    final receivables = store.debts.where((d) => d.isReceivable).toList();
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
        ..._debtSection(context, debts, receivable: false),
        ..._debtSection(context, receivables, receivable: true),
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

  List<Widget> _debtSection(
    BuildContext context,
    List<Debt> items, {
    required bool receivable,
  }) => [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    receivable ? 'Money owed to you' : 'Debts',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: receivable ? 'Add receivable' : 'Add debt',
                  icon: const Icon(Icons.add),
                  onPressed: () =>
                      _editDebt(context, null, receivable: receivable),
                ),
              ],
            ),
            Text(
              store.currency.display(
                receivable ? store.totalReceivable : store.totalDebt,
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (items.any(
              (d) => d.amount > 0 && store.debtMainAmount(d) == null,
            ))
              const Text(
                'Totals exclude balances missing an exchange rate. Set a default in Settings.',
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  receivable
                      ? 'No money owed to you.'
                      : 'No outstanding debts.',
                ),
              ),
          ],
        ),
      ),
    ),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, index) => _debtCard(context, items[index]),
      ),
    ),
  ];

  Widget _debtCard(BuildContext context, Debt debt) => DebtBalanceCard(
    debt: debt,
    mainCurrency: store.currency,
    mainAmount: store.debtMainAmount(debt),
    onMissingRate: () => Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CurrencyExchangeScreen(
          store: store,
          initialFrom: debt.currency,
          initialTo: store.currency,
        ),
      ),
    ),
    onEdit: () => _editDebt(context, debt),
    onSettle: () => showAppSheet<bool>(
      context,
      editor: true,
      builder: (_) => DebtSettlementForm(store: store, debt: debt),
    ),
  );

  Future<void> _editDebt(
    BuildContext context,
    Debt? debt, {
    bool receivable = false,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DebtEditor(
      currency: store.currency,
      debt: debt,
      lockIdentity: store.debtPaymentLinks.containsValue(debt?.id),
      initialIsReceivable: receivable,
      onSave: store.saveDebt,
      onDelete: debt == null ? null : () => store.deleteDebt(debt.id!),
    ),
  );
}
