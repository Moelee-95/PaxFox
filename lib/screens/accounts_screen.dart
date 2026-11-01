import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/debt_editor.dart';
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
  Future<void> editDebt(BuildContext context, [Debt? debt]) => showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DebtEditor(
      currency: store.currency,
      debt: debt,
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
                  subtitle: Wrap(
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${a.currency.symbol}${a.currency.formatGrouped(store.currentBalances.byAccount[a.id] ?? a.opening)}',
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.edit_outlined),
                    ],
                  ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => edit(context),
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
            const SizedBox(height: 24),
            Text('Debts', style: Theme.of(context).textTheme.titleLarge),
            Text(
              'Outstanding: ${store.currency.display(store.totalDebt)} · Net wealth: ${store.currency.display(store.netWealth)}',
            ),
            for (final debt in store.debts)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(debt.name),
                  subtitle: const Text('Outstanding liability'),
                  trailing: Text(store.currency.display(debt.amount)),
                  onTap: () => editDebt(context, debt),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => editDebt(context),
              icon: const Icon(Icons.add),
              label: const Text('Add debt'),
            ),
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
  late final TextEditingController name, balance;
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
    balance = TextEditingController(
      text: a == null
          ? '0'
          : widget.store.currency.formatGrouped(
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
    action.dispose();
    super.dispose();
  }

  int amount() {
    final input = balance.text.trim();
    return widget.store.currency.parseInput(
          input.replaceFirst(RegExp(r'^-'), ''),
        ) *
        (input.startsWith('-') ? -1 : 1);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    final saved = await action.run(() async {
      final old = widget.account;
      final desired = amount();
      // Balance correction adjusts the opening baseline without deleting or
      // duplicating payments, and retains legacy snapshot date semantics.
      final opening = old == null
          ? desired
          : old.opening +
                desired -
                (widget.store.currentBalances.byAccount[old.id] ?? old.opening);
      final account = Account(
        id: old?.id,
        name: name.text.trim(),
        currency: widget.store.currency,
        opening: opening,
        asOf: asOf,
        kind: kind,
        available: available,
        includeOnAsOf: old?.includeOnAsOf ?? true,
        allowOverdraft: kind == AccountKind.bank && overdraft,
      );
      if (old == null) {
        await widget.store.addAccount(account);
      } else {
        await widget.store.updateAccount(account);
      }
    }, failureMessage: 'Could not save account. Please retry.');
    if (saved && mounted) Navigator.pop(context);
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
            Text('Currency: ${widget.store.currency.code}'),
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
              inputFormatters: const [GroupedAmountFormatter()],
              enabled: !busy,
              decoration: InputDecoration(
                labelText: editing
                    ? 'Current balance (${widget.store.currency.symbol.trim()})'
                    : 'Starting balance (${widget.store.currency.symbol.trim()})',
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
              child: Text(busy ? 'Saving...' : 'Save account'),
            ),
          ],
        ),
      ),
    ),
  );
}
