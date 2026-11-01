import 'package:flutter/material.dart';

import '../core/presentation/busy_label.dart';

import '../core/presentation/grouped_amount_formatter.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/debt_editor.dart';

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
  late Currency currency = widget.store.currency;
  final debts = <Debt>[];
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
    return currency.parseInput(trimmed.replaceFirst(RegExp(r'^-'), '')) *
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
      await widget.store.completeSetup(
        [
          if (!hasCash)
            Account(
              name: 'Cash',
              currency: currency,
              opening: currency.parseInput(cash.text),
              asOf: today,
              kind: AccountKind.cash,
              includeOnAsOf: true,
            ),
          if (!noBank)
            for (final bank in banks)
              Account(
                name: bank.name.text.trim(),
                currency: currency,
                opening: bankAmount(bank.balance.text),
                asOf: today,
                kind: AccountKind.bank,
                allowOverdraft: overdrafts[banks.indexOf(bank)],
                available: !blockedBanks[banks.indexOf(bank)],
                includeOnAsOf: true,
              ),
        ],
        selectedCurrency: currency,
        initialDebts: debts,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Setup could not be saved. Your previous data is unchanged. Please retry.';
        });
      }
    }
  }

  Future<void> editDebt([int? index]) => showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => DebtEditor(
      currency: currency,
      debt: index == null ? null : debts[index],
      onSave: (debt) async {
        setState(() {
          if (index == null) {
            debts.add(debt);
          } else {
            debts[index] = debt;
          }
        });
      },
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to PaxFox'),
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
                        'Choose your app currency before entering balances. This currency will be used for all accounts and transactions. Enter 0 if you have no cash.',
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<Currency>(
                        initialValue: currency,
                        decoration: const InputDecoration(
                          labelText: 'App currency',
                        ),
                        items: Currency.values
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  '${value.code} (${value.symbol.trim()})',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged:
                            widget.store.accounts.isNotEmpty ||
                                widget.store.entries.isNotEmpty ||
                                debts.isNotEmpty
                            ? null
                            : (value) => setState(() {
                                currency = value!;
                                cash.clear();
                                for (final bank in banks) {
                                  bank.balance.clear();
                                }
                              }),
                      ),
                      const SizedBox(height: 20),
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
                          inputFormatters: const [GroupedAmountFormatter()],
                          decoration: InputDecoration(
                            labelText:
                                'Cash balance (${currency.symbol.trim()})',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            try {
                              currency.parseInput(value ?? '');
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
                            'Existing account kept · ${currency.symbol}${currency.formatGrouped(accountBalance(account, widget.store.entries, DateTime.now()))}',
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
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: banks[i].balance,
                                    inputFormatters: const [
                                      GroupedAmountFormatter(),
                                    ],
                                    decoration: InputDecoration(
                                      labelText:
                                          'Bank balance (${currency.symbol.trim()})',
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
                      '${currency.symbol}${currency.formatGrouped(currency.parseInput(cash.text))}',
                    ),
                  ),
                for (final account in widget.store.accounts)
                  ListTile(
                    title: Text('${account.name} (kept)'),
                    trailing: Text(
                      '${currency.symbol}${currency.formatGrouped(accountBalance(account, widget.store.entries, DateTime.now()))}',
                    ),
                  ),
                if (!noBank)
                  for (final bank in banks)
                    ListTile(
                      title: Text(bank.name.text.trim()),
                      trailing: Text(
                        '${currency.symbol}${currency.formatGrouped(bankAmount(bank.balance.text))}',
                      ),
                    ),
                const Text(
                  'Cash cannot go below zero. Bank payments are rejected if funds are insufficient, unless overdraft is enabled for that bank. Setup is saved only when you finish.',
                ),
              ],
              if (step == 2) ...[
                const SizedBox(height: 20),
                Text(
                  'Outstanding debts (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Include loans from people or banks. Starting account balances should already include any borrowed money you still hold.',
                ),
                for (var i = 0; i < debts.length; i++)
                  ListTile(
                    title: Text(debts[i].name),
                    subtitle: Text(currency.display(debts[i].amount)),
                    trailing: IconButton(
                      tooltip: 'Remove debt',
                      icon: const Icon(Icons.close),
                      onPressed: saving
                          ? null
                          : () => setState(() => debts.removeAt(i)),
                    ),
                    onTap: saving ? null : () => editDebt(i),
                  ),
                TextButton.icon(
                  onPressed: saving ? null : () => editDebt(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add debt'),
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
                child: BusyLabel(
                  busy: saving,
                  label: saving
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
