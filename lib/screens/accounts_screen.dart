import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key, required this.store});
  final LedgerStore store;
  void edit(BuildContext context, [Account? account]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountForm(store: store, account: account),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Accounts')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => edit(context),
      icon: const Icon(Icons.add),
      label: const Text('Add account'),
    ),
    body: ListenableBuilder(
      listenable: store,
      builder: (_, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const Text(
            'Blocked accounts count toward account wealth but cannot fund payments or outgoing transfers. Income can still be received into them. Tap an account to edit.',
          ),
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
                subtitle: Text(
                  '${a.kind == AccountKind.cash ? 'Cash' : 'Bank'} - ${!a.available
                      ? 'Blocked - included in wealth'
                      : a.canOverdraw
                      ? 'Overdraft allowed'
                      : 'Cannot go below zero'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '€${a.currency.format(store.currentBalances.byAccount[a.id] ?? a.opening)}',
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.edit_outlined),
                  ],
                ),
              ),
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
  bool busy = false;
  String? error;
  bool get editing => widget.account != null;
  @override
  void initState() {
    super.initState();
    final a = widget.account;
    name = TextEditingController(text: a?.name ?? '');
    balance = TextEditingController(
      text: a == null
          ? '0'
          : Currency.eur.format(
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
    super.dispose();
  }

  int amount() {
    final input = balance.text.trim();
    return Currency.eur.parse(input.replaceFirst(RegExp(r'^-'), '')) *
        (input.startsWith('-') ? -1 : 1);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
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
        currency: Currency.eur,
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
      if (mounted) {
        Navigator.pop(context);
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save account. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit account' : 'Add account')),
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
            const Text('Currency: €'),
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
                subtitle: const Text(
                  'Allow this bank account to go below zero.',
                ),
                value: overdraft,
                onChanged: busy ? null : (v) => setState(() => overdraft = v),
              ),
            TextFormField(
              controller: balance,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: editing
                    ? 'Current balance (€)'
                    : 'Starting balance (€)',
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
            if (editing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'A balance correction adjusts the starting balance and preserves all transactions. It also changes historical balances. Corrections that create a negative protected balance are rejected.',
                ),
              ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Starting date: ${dayKey(asOf)}'),
              subtitle: Text(
                editing ? 'Original starting date is preserved.' : 'Enter the balance before payments recorded on this date.',
              ),
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
                subtitle: const Text(
                  'Included in wealth. Cannot fund spending or transfers out.',
                ),
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
