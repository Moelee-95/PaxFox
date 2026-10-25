import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final cashForm = GlobalKey<FormState>(), bankForm = GlobalKey<FormState>();
  final cash = TextEditingController();
  final overdrafts = <bool>[];
  final blockedBanks = <bool>[];
  final banks =
      <({TextEditingController name, TextEditingController balance})>[];
  int step = 0;
  bool noBank = false, saving = false;
  String? error;
  bool get hasCash =>
      widget.store.accounts.any((a) => a.kind == AccountKind.cash);
  bool get hasBank =>
      widget.store.accounts.any((a) => a.kind == AccountKind.bank);
  @override
  void initState() {
    super.initState();
    if (!hasBank) {
      addBank();
    }
  }

  void addBank() {
    overdrafts.add(false);
    blockedBanks.add(false);
    banks.add((
      name: TextEditingController(),
      balance: TextEditingController(),
    ));
  }

  @override
  void dispose() {
    cash.dispose();
    for (final bank in banks) {
      bank.name.dispose();
      bank.balance.dispose();
    }
    super.dispose();
  }

  int bankAmount(String input) {
    final trimmed = input.trim();
    return Currency.eur.parse(trimmed.replaceFirst(RegExp(r'^-'), '')) *
        (trimmed.startsWith('-') ? -1 : 1);
  }

  Future<void> next() async {
    if (step == 0) {
      if (cashForm.currentState!.validate()) {
        setState(() => step = 1);
      }
      return;
    }
    if (step == 1) {
      if (noBank || bankForm.currentState!.validate()) {
        setState(() => step = 2);
      }
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final today = dateOnly(DateTime.now());
      await widget.store.completeSetup([
        if (!hasCash)
          Account(
            name: 'Cash',
            currency: Currency.eur,
            opening: Currency.eur.parse(cash.text),
            asOf: today,
            kind: AccountKind.cash,
            includeOnAsOf: true,
          ),
        if (!noBank)
          for (final bank in banks)
            Account(
              name: bank.name.text.trim(),
              currency: Currency.eur,
              opening: bankAmount(bank.balance.text),
              asOf: today,
              kind: AccountKind.bank,
              allowOverdraft: overdrafts[banks.indexOf(bank)],
              available: !blockedBanks[banks.indexOf(bank)],
              includeOnAsOf: true,
            ),
      ]);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Setup could not be saved. Your previous data is unchanged. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to Moneva'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Step ${step + 1} of 3',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              if (step == 0)
                Form(
                  key: cashForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set up your cash',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Text(
                        'All balances are in EUR. Enter the cash you have before recording today’s payments in Moneva. Enter 0 if you have no cash.',
                      ),
                      if (hasCash)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'Your existing cash accounts will be kept.',
                          ),
                        )
                      else
                        TextFormField(
                          controller: cash,
                          decoration: const InputDecoration(
                            labelText: 'Cash balance (€)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            try {
                              Currency.eur.parse(value ?? '');
                            } on FormatException catch (e) {
                              return e.message;
                            }
                            return null;
                          },
                        ),
                      if (widget.store.accounts.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'Existing accounts and transactions are kept. We will not reset their balances. Existing accounts are treated as bank accounts.',
                          ),
                        ),
                    ],
                  ),
                ),
              if (step == 1)
                Form(
                  key: bankForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set up your bank accounts',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Text(
                        'Add each bank account and its starting balance. Enable overdraft only for banks that can go below zero.',
                      ),
                      for (final account in widget.store.accounts.where(
                        (a) => a.kind == AccountKind.bank,
                      ))
                        ListTile(
                          title: Text(account.name),
                          subtitle: Text(
                            'Existing account kept · €${Currency.eur.format(accountBalance(account, widget.store.entries, DateTime.now()))}',
                          ),
                        ),
                      if (!hasBank)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I do not have a bank account'),
                          value: noBank,
                          onChanged: (value) => setState(() => noBank = value!),
                        ),
                      if (!noBank) ...[
                        for (var i = 0; i < banks.length; i++)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: banks[i].name,
                                    decoration: InputDecoration(
                                      labelText: 'Bank account ${i + 1} name',
                                    ),
                                    validator: (value) =>
                                        value == null || value.trim().isEmpty
                                        ? 'Enter a bank account name.'
                                        : null,
                                  ),
                                  TextFormField(
                                    controller: banks[i].balance,
                                    decoration: const InputDecoration(
                                      labelText: 'Bank balance (€)',
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                          signed: true,
                                        ),
                                    validator: (value) {
                                      try {
                                        if (bankAmount(value ?? '') < 0 &&
                                            !overdrafts[i]) {
                                          return 'Enable overdraft for a negative bank balance.';
                                        }
                                      } on FormatException catch (e) {
                                        return e.message;
                                      }
                                      return null;
                                    },
                                  ),
                                  SwitchListTile(
                                    title: const Text('Allow overdraft'),
                                    value: overdrafts[i],
                                    onChanged: (value) =>
                                        setState(() => overdrafts[i] = value),
                                  ),
                                  SwitchListTile(
                                    title: const Text('Blocked account'),
                                    subtitle: const Text(
                                      'Counts toward wealth, but cannot fund spending.',
                                    ),
                                    value: blockedBanks[i],
                                    onChanged: (value) =>
                                        setState(() => blockedBanks[i] = value),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: () => setState(addBank),
                          icon: const Icon(Icons.add),
                          label: const Text('Add another bank account'),
                        ),
                      ],
                    ],
                  ),
                ),
              if (step == 2) ...[
                Text(
                  'Review your starting balances',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (!hasCash)
                  ListTile(
                    title: const Text('Cash'),
                    trailing: Text(
                      '€${Currency.eur.format(Currency.eur.parse(cash.text))}',
                    ),
                  ),
                for (final account in widget.store.accounts)
                  ListTile(
                    title: Text('${account.name} (kept)'),
                    trailing: Text(
                      '€${Currency.eur.format(accountBalance(account, widget.store.entries, DateTime.now()))}',
                    ),
                  ),
                if (!noBank)
                  for (final bank in banks)
                    ListTile(
                      title: Text(bank.name.text.trim()),
                      trailing: Text(
                        '€${Currency.eur.format(bankAmount(bank.balance.text))}',
                      ),
                    ),
                const Text(
                  'Cash cannot go below zero. Bank payments are rejected if funds are insufficient, unless overdraft is enabled for that bank. Setup is saved only when you finish.',
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: saving ? null : next,
                child: Text(
                  saving
                      ? 'Saving...'
                      : step == 2
                      ? 'Finish setup'
                      : 'Continue',
                ),
              ),
              if (step > 0)
                TextButton(
                  onPressed: saving ? null : () => setState(() => step--),
                  child: const Text('Back'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
