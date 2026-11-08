import 'currency_exchange_screen.dart';

import 'package:flutter/material.dart';

import '../core/presentation/busy_label.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/debt_editor.dart';
import '../core/presentation/debt_balance_card.dart';
import '../core/presentation/app_sheet.dart';
import 'debt_settlement_form.dart';
import '../core/presentation/grouped_amount_formatter.dart';
import '../core/presentation/info_button.dart';
import '../core/presentation/ledger_refresh.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.store});
  final LedgerStore store;
  void edit(BuildContext context, [Account? account]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountForm(store: store, account: account),
    ),
  );
  Future<void> editDebt(
    BuildContext context, [
    Debt? debt,
    bool receivable = false,
  ]) => showDialog<void>(
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
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Accounts'),
      actions: const [
        InfoButton(
          title: 'About accounts',
          message: 'Blocked accounts count toward account wealth but cannot fund payments or outgoing transfers. Income can still be received into them. Tap an account to edit.',
        ),
      ],
    ),
    body: LedgerRefresh(
      store: store,
      child: ListenableBuilder(
        listenable: store,
        builder: (_, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'Bank accounts & cash',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (store.accounts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No accounts yet.'),
              ),
            for (final a in store.accounts)
              Card(
                child: ListTile(
                  onTap: () => edit(context, a),
                  title: Text(a.name),
                  leading: Icon(
                    a.kind == AccountKind.cash
                        ? Icons.payments_outlined
                        : Icons.account_balance_outlined,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.currency.display(
                          store.currentBalances.byAccount[a.id] ?? a.opening,
                        ),
                      ),
                      if (a.currency != store.currency)
                        Text(
                          store.currency.display(
                            a.toBase(
                              store.currentBalances.byAccount[a.id] ??
                                  a.opening,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: 4,
                        children: [
                          _policyIcon(
                            context,
                            a.canOverdraw
                                ? Icons.credit_score_outlined
                                : Icons.shield_outlined,
                            a.canOverdraw
                                ? 'Overdraft allowed'
                                : 'Cannot go below zero',
                          ),
                          if (!a.available)
                            _policyIcon(
                              context,
                              Icons.lock_outline,
                              'Blocked account: cannot fund spending or outgoing transfers',
                            ),
                          _policyIcon(
                            context,
                            Icons.account_balance_wallet_outlined,
                            'Included in account wealth',
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
            const SizedBox(height: 12),
            Text('Net wealth: ${store.currency.display(store.netWealth)}'),
            if (store.hasUnvaluedDebts)
              const Text(
                'Totals exclude balances missing an exchange rate. Set a default in Settings.',
              ),
            const SizedBox(height: 24),
            for (final receivable in [false, true]) ...[
              if (receivable) const SizedBox(height: 24),
              Text(
                receivable ? 'Money owed to you' : 'Debts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                store.currency.display(
                  receivable ? store.totalReceivable : store.totalDebt,
                ),
              ),
              if (!store.debts.any((d) => d.isReceivable == receivable))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    receivable
                        ? 'No money owed to you.'
                        : 'No outstanding debts.',
                  ),
                ),
              for (final debt in store.debts.where(
                (d) => d.isReceivable == receivable,
              ))
                DebtBalanceCard(
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
                  onEdit: () => editDebt(context, debt),
                  onSettle: () => showAppSheet<bool>(
                    context,
                    editor: true,
                    builder: (_) =>
                        DebtSettlementForm(store: store, debt: debt),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => editDebt(context, null, receivable),
                icon: const Icon(Icons.add),
                label: Text(receivable ? 'Add receivable' : 'Add debt'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Widget _policyIcon(BuildContext context, IconData icon, String message) =>
      IconButton(
        tooltip: message,
        visualDensity: VisualDensity.compact,
        iconSize: 20,
        icon: Icon(icon),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Account information'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
}

class AccountForm extends StatefulWidget {
  const AccountForm({super.key, required this.store, this.account});
  final LedgerStore store;
  final Account? account;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, balance, exchangeRate;
  late Currency accountCurrency;
  bool balanceEdited = false;
  Account? conversionSource;
  int? conversionAmount;
  late AccountKind kind;
  late DateTime asOf;
  late bool available, overdraft;
  late final action = AsyncAction()..addListener(() => setState(() {}));
  bool get busy => action.busy;
  String? get error => action.error;
  bool get editing => widget.account != null;
  @override
  void initState() {
    super.initState();
    final a = widget.account;
    name = TextEditingController(text: a?.name ?? '');
    accountCurrency = a?.currency ?? widget.store.currency;
    exchangeRate = TextEditingController(text: a?.exchangeRate ?? '1');
    balance = TextEditingController(
      text: a == null
          ? '0'
          : accountCurrency.formatGrouped(
              widget.store.currentBalances.byAccount[a.id] ?? a.opening,
            ),
    );
    kind = a?.kind ?? AccountKind.bank;
    asOf = a?.asOf ?? dateOnly(DateTime.now());
    available = a?.available ?? true;
    overdraft = a?.canOverdraw ?? false;
  }

  @override
  void dispose() {
    name.dispose();
    balance.dispose();
    exchangeRate.dispose();
    action.dispose();
    super.dispose();
  }

  int amount() {
    final input = balance.text.trim();
    return accountCurrency.parseInput(input.replaceFirst(RegExp(r'^-'), '')) *
        (input.startsWith('-') ? -1 : 1);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    final saved = await action.run(() async {
      final old = widget.account;
      final desired = amount();
      final account = Account(
        id: old?.id,
        name: name.text.trim(),
        currency: accountCurrency,
        baseCurrency: widget.store.currency,
        exchangeRate: accountCurrency == widget.store.currency
            ? '1'
            : ExchangeRate.parse(exchangeRate.text).value,
        opening: old?.opening ?? desired,
        asOf: asOf,
        kind: kind,
        available: available,
        includeOnAsOf: old?.includeOnAsOf ?? true,
        allowOverdraft: kind == AccountKind.bank && overdraft,
      );
      if (old == null) {
        await widget.store.addAccount(account);
      } else {
        await widget.store.updateAccount(account, currentBalance: desired);
      }
    }, failureMessage: 'Could not save account. Please retry.');
    if (saved && mounted) Navigator.pop(context);
  }

  void changeAccountCurrency(Currency next) {
    try {
      conversionAmount = amount();
      conversionSource = Account(
        name: '',
        currency: accountCurrency,
        baseCurrency: widget.store.currency,
        exchangeRate: accountCurrency == widget.store.currency
            ? '1'
            : ExchangeRate.parse(exchangeRate.text).value,
        opening: 0,
        asOf: asOf,
      );
    } on FormatException {
      conversionSource = null;
      conversionAmount = null;
    }
    accountCurrency = next;
    balanceEdited = false;
    exchangeRate.text = next == widget.store.currency
        ? '1'
        : next == widget.account?.currency
        ? widget.account!.exchangeRate
        : '';
    updateConvertedBalance();
  }

  void updateConvertedBalance() {
    final old = conversionSource;
    if (old == null ||
        conversionAmount == null ||
        old.currency == accountCurrency ||
        balanceEdited) {
      return;
    }
    try {
      final target = Account(
        name: '',
        currency: accountCurrency,
        baseCurrency: widget.store.currency,
        exchangeRate: accountCurrency == widget.store.currency
            ? '1'
            : ExchangeRate.parse(exchangeRate.text).value,
        opening: 0,
        asOf: asOf,
      );
      final native = conversionAmount!;
      balance.text = accountCurrency.formatGrouped(
        old.convertTo(target, native),
      );
    } on FormatException {
      /* Complete the rate before converting. */
    }
  }

  String? get basePreview {
    if (accountCurrency == widget.store.currency) return null;
    try {
      final converted = ExchangeRate.parse(exchangeRate.text)
          .toBase(amount(), accountCurrency.scale, widget.store.currency.scale);
      return 'Equivalent: ${widget.store.currency.display(converted)}';
    } on FormatException {
      return null;
    }
  }

  Future<void> delete() async {
    final yes = await confirmAction(
      context,
      title: 'Delete bank account?',
      message: 'This removes the unused bank account and its starting balance.',
    );
    if (yes != true || !mounted) return;
    final deleted = await action.run(
      () => widget.store.deleteBankAccount(widget.account!.id!),
      failureMessage: 'Could not delete account. Please retry.',
    );
    if (deleted && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit account' : 'Add account'),
        actions: [
          if (widget.account?.id != null &&
              widget.store.canDeleteBankAccount(widget.account!.id!))
            IconButton(
              tooltip: 'Delete bank account',
              onPressed: busy ? null : delete,
              icon: const Icon(Icons.delete_outline),
            ),
          const InfoButton(
            title: 'Account settings',
            message: 'Balance corrections adjust the starting balance while keeping existing payments and the original starting date. Historical balances also change; corrections creating a negative protected balance are rejected. For new accounts enter the balance before payments recorded on the starting date. Cash cannot go below zero. Banks require overdraft permission to go below zero. Blocked accounts count toward wealth and can receive money but cannot fund spending or outgoing transfers.',
          ),
        ],
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: name,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Account name'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Enter a name.' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Currency>(
              key: ValueKey(('account-currency', accountCurrency)),
              initialValue: accountCurrency,
              decoration: const InputDecoration(labelText: 'Account currency'),
              items: Currency.values
                  .where(
                    (c) =>
                        kind == AccountKind.bank || c == widget.store.currency,
                  )
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.code)))
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      changeAccountCurrency(value!);
                    }),
            ),
            if (accountCurrency != widget.store.currency) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: exchangeRate,
                enabled: !busy,
                inputFormatters: const [GroupedAmountFormatter()],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      '1 ${widget.store.currency.code} equals (${accountCurrency.code})',
                ),
                onChanged: (_) => setState(updateConvertedBalance),
                validator: (value) {
                  try {
                    ExchangeRate.parse(value ?? '');
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Text(
                'The latest rate values this account. Saved income and expenses keep their original ${widget.store.currency.code} values.',
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<AccountKind>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Account type'),
              items: const [
                DropdownMenuItem(value: AccountKind.bank, child: Text('Bank')),
                DropdownMenuItem(value: AccountKind.cash, child: Text('Cash')),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      kind = value!;
                      if (kind == AccountKind.cash) {
                        overdraft = false;
                        available = true;
                        if (accountCurrency != widget.store.currency) {
                          changeAccountCurrency(widget.store.currency);
                        }
                      }
                    }),
            ),
            if (kind == AccountKind.bank)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow overdraft'),
                value: overdraft,
                onChanged: busy ? null : (v) => setState(() => overdraft = v),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: balance,
              onChanged: (_) => setState(() => balanceEdited = true),
              inputFormatters: const [GroupedAmountFormatter()],
              enabled: !busy,
              decoration: InputDecoration(
                labelText: editing
                    ? 'Current balance (${accountCurrency.symbol.trim()})'
                    : 'Starting balance (${accountCurrency.symbol.trim()})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (_) {
                try {
                  if (amount() < 0 &&
                      !(kind == AccountKind.bank && overdraft)) {
                    return 'This account cannot have a negative balance.';
                  }
                } on FormatException catch (e) {
                  return e.message;
                }
                return null;
              },
            ),
            if (basePreview != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(basePreview!),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Starting date: ${dayKey(asOf)}'),
              trailing: editing ? null : const Icon(Icons.calendar_today),
              onTap: editing || busy
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: asOf,
                        firstDate: DateTime(1900),
                        lastDate: dateOnly(DateTime.now()),
                      );
                      if (date != null && mounted) {
                        setState(() => asOf = date);
                      }
                    },
            ),
            if (kind == AccountKind.bank)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Blocked account'),
                value: !available,
                onChanged: busy ? null : (v) => setState(() => available = !v),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : save,
              child: BusyLabel(
                busy: busy,
                label: busy ? 'Saving...' : 'Save account',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
