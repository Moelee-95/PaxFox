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
  late final TextEditingController amount, description, notes;
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
    amount = TextEditingController(
      text: e == null ? '' : currency.formatGrouped(e.amount),
    );
    description = TextEditingController(text: e?.description ?? '');
    category = e?.type == EntryType.transfer ? null : e?.category;
    notes = TextEditingController(text: e?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [amount, description, notes]) {
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
      () async => widget.store.saveEntry(
        LedgerEntry(
          id: widget.entry?.id,
          type: type,
          amount: currency.parseInput(amount.text),
          currency: currency,
          date: date,
          description: description.text.trim(),
          category: type == EntryType.transfer ? 'Transfer' : category!,
          notes: notes.text.trim(),
          accountId: accountId,
          destinationId: type == EntryType.transfer ? destinationId : null,
        ),
      ),
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
              account.currency == currency &&
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
      } else {
        accountId = id;
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
        if (type == EntryType.transfer) accountField(true),
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
