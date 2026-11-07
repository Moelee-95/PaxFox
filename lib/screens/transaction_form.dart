import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/account_picker.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/entry_editor_sheet.dart';
import '../core/presentation/category_picker.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/transaction_tile.dart';
import '../features/receipts/invoice_source_details.dart';

class TransactionForm extends StatefulWidget {
  const TransactionForm({
    super.key,
    required this.store,
    this.entry,
    this.initialType = EntryType.expense,
    this.onSavedType,
  });
  final LedgerStore store;
  final LedgerEntry? entry;
  final EntryType initialType;
  final ValueChanged<EntryType>? onSavedType;
  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount, description, notes, received;
  late Currency originalInputCurrency;
  late int originalInputAmount;
  late String originalReceived;
  String? category;
  late EntryType type;
  late Currency currency;
  late DateTime date;
  int? accountId, destinationId;
  late final action = AsyncAction()..addListener(() => setState(() {}));
  bool get saving => action.busy;
  String? get error => action.error;
  Future<Map<String, Object?>?>? scannedInvoice;
  bool get originallyUnassigned =>
      widget.entry?.id != null && widget.entry?.accountId == null;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e?.id != null &&
        widget.store.scannedInvoiceTransactionIds.contains(e!.id)) {
      scannedInvoice = widget.store.scannedInvoiceFor(e.id!);
    }
    currency = e?.currency ?? widget.store.currency;
    type = e?.type ?? widget.initialType;
    date = e?.date ?? dateOnly(DateTime.now());
    accountId = e?.accountId;
    destinationId = e?.destinationId;
    final source = selectedAccount;
    if (type == EntryType.transfer && source != null) {
      currency = source.currency;
      originalInputAmount = e?.accountAmount ?? e?.amount ?? 0;
    } else {
      final inputCurrency = e?.fx?.inputCurrency;
      if (inputCurrency == widget.store.currency ||
          inputCurrency == source?.currency) {
        currency = inputCurrency ?? currency;
        originalInputAmount = e?.fx?.inputAmount ?? e?.amount ?? 0;
      } else {
        originalInputAmount = e?.amount ?? 0;
      }
    }
    originalInputCurrency = currency;
    amount = TextEditingController(
      text: e == null ? '' : currency.formatGrouped(originalInputAmount),
    );
    final receivedMinor =
        e?.destinationAmount ??
        (destinationAccount?.currency == e?.currency ? e?.amount : null);
    received = TextEditingController(
      text: receivedMinor == null
          ? ''
          : (destinationAccount?.currency ?? widget.store.currency)
                .formatGrouped(receivedMinor),
    );
    originalReceived = received.text;
    description = TextEditingController(text: e?.description ?? '');
    category = e?.type == EntryType.transfer ? null : e?.category;
    notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [amount, description, notes, received]) {
      c.dispose();
    }
    action.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    final saved = await action.run(
      () async {
        final parsed = currency.parseInput(amount.text);
        final old = widget.entry;
        var sameReceived = received.text == originalReceived;
        if (crossCurrencyTransfer) {
          try {
            sameReceived =
                destinationAccount!.currency.parseInput(received.text) ==
                destinationAccount!.currency.parseInput(originalReceived);
          } on FormatException {
            sameReceived = false;
          }
        }
        final unchanged =
            old != null &&
            parsed == originalInputAmount &&
            currency == originalInputCurrency &&
            type == old.type &&
            accountId == old.accountId &&
            destinationId == old.destinationId &&
            sameReceived;
        final entry = unchanged
            ? LedgerEntry.fromMap({
                ...old.toMap(),
                'id': old.id,
                'date': dayKey(date),
                'description': description.text.trim(),
                'category': type == EntryType.transfer ? 'Transfer' : category!,
                'notes': notes.text.trim(),
              })
            : widget.store.entryFromInput(
                id: old?.id,
                type: type,
                inputAmount: parsed,
                inputCurrency: currency,
                date: date,
                description: description.text.trim(),
                category: type == EntryType.transfer ? 'Transfer' : category!,
                notes: notes.text.trim(),
                accountId: accountId,
                destinationId: type == EntryType.transfer
                    ? destinationId
                    : null,
                receivedAmount: crossCurrencyTransfer
                    ? destinationAccount!.currency.parseInput(received.text)
                    : null,
              );
        await widget.store.saveEntry(entry);
      },
      failureMessage: 'Could not save. Check the fields and account currencies, then retry.',
    );
    if (saved && mounted) {
      widget.onSavedType?.call(type);
      Navigator.pop(context, true);
    }
  }

  Future<void> delete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete transaction?',
      message: 'This will update reports and account balances.',
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final deleted = await action.run(
      () => widget.store.deleteEntry(widget.entry!.id!),
      failureMessage: 'Could not delete. Please retry.',
    );
    if (deleted && mounted) Navigator.pop(context);
  }

  Account? get selectedAccount =>
      widget.store.accounts.where((a) => a.id == accountId).firstOrNull;
  Account? get destinationAccount =>
      widget.store.accounts.where((a) => a.id == destinationId).firstOrNull;
  bool get crossCurrencyTransfer =>
      type == EntryType.transfer &&
      selectedAccount != null &&
      destinationAccount != null &&
      selectedAccount!.currency != destinationAccount!.currency;

  void changeInputCurrency(Currency next) {
    if (next == currency) return;
    try {
      final value = currency.parseInput(amount.text);
      final base = currency == widget.store.currency
          ? value
          : selectedAccount!.toBase(value);
      final converted = next == widget.store.currency
          ? base
          : selectedAccount!.fromBase(base);
      amount.text = next.formatGrouped(converted);
    } on FormatException {
      /* Empty draft keeps its text until entered. */
    }
    currency = next;
  }

  Widget conversionPreview() => ValueListenableBuilder<TextEditingValue>(
    valueListenable: amount,
    builder: (context, value, _) {
      try {
        final parsed = currency.parseInput(value.text);
        final account = selectedAccount!;
        final old = widget.entry;
        if (old != null &&
            parsed == originalInputAmount &&
            currency == originalInputCurrency &&
            accountId == old.accountId &&
            type == old.type) {
          return Text(
            'Saved reporting amount: ${old.currency.display(old.amount)}\nChanging the amount uses the current account rate.',
          );
        }

        final base = currency == widget.store.currency
            ? parsed
            : account.toBase(parsed);
        final native = currency == account.currency
            ? parsed
            : account.fromBase(parsed);
        return Text(
          '${widget.store.currency.display(base)} = ${account.currency.display(native)}\n'
          '1 ${widget.store.currency.code} = ${account.exchangeRate} ${account.currency.code}',
        );
      } on FormatException {
        return const SizedBox.shrink();
      }
    },
  );

  Widget accountField(bool destination) => AccountPicker(
    balances: widget.store.currentBalances.byAccount,
    label: destination
        ? 'Destination account'
        : type == EntryType.income
        ? 'Receive income into'
        : 'Payment account',
    accounts: widget.store.accounts
        .where(
          (account) =>
              (destination ||
              (type != EntryType.expense && type != EntryType.transfer) ||
              account.available),
        )
        .toList(),
    selectedId: destination ? destinationId : accountId,
    enabled: !saving,
    allowUnassigned:
        !destination &&
        type != EntryType.transfer &&
        (originallyUnassigned || type == EntryType.refund),
    onChanged: (id) => setState(() {
      if (destination) {
        destinationId = id;
        received.clear();
      } else {
        changeInputCurrency(widget.store.currency);
        accountId = id;
        if (type == EntryType.transfer && selectedAccount != null) {
          changeInputCurrency(selectedAccount!.currency);
        }
      }
    }),
    validator: (id) =>
        ((type == EntryType.expense || type == EntryType.income) &&
            id == null &&
            !originallyUnassigned)
        ? (type == EntryType.income
              ? 'Select where this income is received.'
              : 'Select the account used for this payment.')
        : type == EntryType.transfer &&
              (id == null || (destination && id == accountId))
        ? 'Transfers need two different accounts.'
        : null,
  );
  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: EntryEditorSheet(
      title: widget.entry == null ? 'Add transaction' : 'Edit transaction',
      type: type,
      currency: currency,
      amount: amount,
      busy: saving,
      saveLabel: 'Save transaction',
      onSave: save,
      amountValidator: (value) {
        try {
          if (currency.parseInput(value ?? '') <= 0) {
            return 'Amount must be greater than zero.';
          }
        } on FormatException catch (error) {
          return error.message;
        }
        return null;
      },
      categoryPicker: CategoryPickerField(
        store: widget.store,
        type: type,
        value: category,
        header: true,
        enabled: !saving,
        types: EntryType.values,
        onChanged: (value) => setState(() {
          type = value.type;
          if (type == EntryType.transfer && selectedAccount != null) {
            changeInputCurrency(selectedAccount!.currency);
          } else {
            destinationId = null;
            changeInputCurrency(widget.store.currency);
          }
          category = value.name;
        }),
      ),
      actions: [
        if (widget.entry != null)
          IconButton(
            tooltip: 'Delete transaction',
            onPressed: saving ? null : delete,
            color: Colors.white,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
      children: [
        if (scannedInvoice != null)
          InvoiceSourceDetails(
            source: scannedInvoice!,
            title: type == EntryType.income
                ? 'Income document'
                : 'Scanned invoice',
          ),
        if (widget.entry?.createdAt != null)
          Text('Added ${creationTimestamp(context, widget.entry!.createdAt!)}'),
        TextFormField(
          controller: description,
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: 'Description / merchant',
          ),
          validator: (s) =>
              s == null || s.trim().isEmpty ? 'Enter a description.' : null,
        ),
        const SizedBox(height: 12),
        accountField(false),
        if (type != EntryType.transfer &&
            selectedAccount != null &&
            selectedAccount!.currency != widget.store.currency) ...[
          DropdownButtonFormField<Currency>(
            key: ValueKey(('transaction-input-currency', currency, accountId)),
            initialValue: currency,
            decoration: const InputDecoration(labelText: 'Enter amount in'),
            items: [widget.store.currency, selectedAccount!.currency]
                .map((c) => DropdownMenuItem(value: c, child: Text(c.code)))
                .toList(),
            onChanged: saving
                ? null
                : (value) => setState(() => changeInputCurrency(value!)),
          ),
          const SizedBox(height: 8),
          conversionPreview(),
        ],
        if (type == EntryType.transfer) ...[
          Text(
            'Amount deducted (${selectedAccount?.currency.code ?? currency.code}) is entered above.',
          ),
          accountField(true),
          if (crossCurrencyTransfer)
            TextFormField(
              controller: received,
              enabled: !saving,
              decoration: InputDecoration(
                labelText:
                    'Amount received (${destinationAccount!.currency.code})',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) {
                try {
                  if (destinationAccount!.currency.parseInput(value ?? '') >
                      0) {
                    return null;
                  }
                } on FormatException catch (e) {
                  return e.message;
                }
                return 'Enter the amount received.';
              },
            ),
        ],
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: Text('Date: ${dayKey(date)}'),
            leading: const Icon(Icons.calendar_today),
            trailing: TextButton(
              onPressed: saving
                  ? null
                  : () => setState(() {
                      final today = DateTime.now();
                      date = DateTime(today.year, today.month, today.day - 1);
                    }),
              child: const Text('Yesterday'),
            ),
            onTap: saving
                ? null
                : () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null && mounted) {
                      setState(() => date = chosen);
                    }
                  },
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: notes,
          enabled: !saving,
          decoration: const InputDecoration(labelText: 'Notes'),
          maxLines: 3,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}
