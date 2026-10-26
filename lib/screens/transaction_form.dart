import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/presentation/grouped_amount_formatter.dart';

import '../core/presentation/entry_type_picker.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/account_picker.dart';
import '../core/presentation/bottom_action_bar.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/transaction_tile.dart';
import '../features/receipts/invoice_images.dart';

class TransactionForm extends StatefulWidget {
  const TransactionForm({super.key, required this.store, this.entry});
  final LedgerStore store;
  final LedgerEntry? entry;
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
  bool saving = false;
  String? error;
  Future<Map<String, Object?>?>? scannedInvoice;
  bool get originallyUnassigned =>
      widget.entry?.id != null && widget.entry?.accountId == null;
  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e?.id != null) {
      scannedInvoice = widget.store.scannedInvoiceFor(e!.id!);
    }
    currency = e?.currency ?? widget.store.currency;
    type = e?.type ?? EntryType.expense;
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
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.saveEntry(
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
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save. Check the fields and account currencies, then retry.';
        });
      }
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
    setState(() => saving = true);
    try {
      await widget.store.deleteEntry(widget.entry!.id!);
      if (mounted) {
        Navigator.pop(context);
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '${e.message}';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not delete. Please retry.';
        });
      }
    }
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
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: BottomActionBar(
      label: 'Save transaction',
      busy: saving,
      busyLabel: 'Saving…',
      onPressed: save,
    ),
    appBar: AppBar(
      title: Text(
        widget.entry == null ? 'Add transaction' : 'Edit transaction',
      ),
      actions: [
        if (widget.entry != null)
          IconButton(
            tooltip: 'Delete transaction',
            onPressed: saving ? null : delete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Form(
          key: form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              if (scannedInvoice != null)
                FutureBuilder<Map<String, Object?>?>(
                  future: scannedInvoice,
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null) {
                      return const SizedBox.shrink();
                    }
                    final paths = (jsonDecode(
                      data['image_paths'] as String,
                    ) as List).cast<String>();
                    return ExpansionTile(
                      title: const Text('Scanned invoice'),
                      children: [
                        for (final path in paths)
                          FutureBuilder<File>(
                            future: InvoiceImages().resolve(path),
                            builder: (_, image) => image.hasData
                                ? SizedBox(
                                    height: 220,
                                    child: Image.file(
                                      image.data!,
                                      errorBuilder: (_, _, _) =>
                                          const Text('Image unavailable'),
                                    ),
                                  )
                                : const SizedBox(height: 20),
                          ),
                        ExpansionTile(
                          title: const Text('Original extracted data'),
                          children: [
                            SelectableText(data['raw_response'] as String),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              if (widget.entry?.createdAt != null)
                Text(
                  'Added ${creationTimestamp(context, widget.entry!.createdAt!)}',
                ),
              EntryTypePicker(
                value: type,
                onChanged: saving
                    ? null
                    : (t) => setState(() {
                        if (categoryKind(type) != categoryKind(t!)) {
                          category = null;
                        }
                        type = t;
                      }),
              ),
              TextFormField(
                controller: description,
                enabled: !saving,
                decoration: const InputDecoration(
                  labelText: 'Description / merchant',
                ),
                validator: (s) => s == null || s.trim().isEmpty
                    ? 'Enter a description.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amount,
                inputFormatters: const [GroupedAmountFormatter()],
                enabled: !saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: '${currency.symbol.trim()} ',
                ),
                validator: (s) {
                  try {
                    if (currency.parseInput(s ?? '') <= 0) {
                      return 'Amount must be greater than zero.';
                    }
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date: ${dayKey(date)}'),
                trailing: const Icon(Icons.calendar_today),
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
              if (type != EntryType.transfer)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey(
                    '$type-$category-${widget.store.categories.map((c) => c.name).join('|')}',
                  ),
                  initialValue:
                      widget.store
                          .categoriesFor(type)
                          .any((c) => c.name == category)
                      ? category
                      : null,
                  decoration: InputDecoration(
                    labelText: type == EntryType.income
                        ? 'Income category'
                        : 'Expense category',
                  ),
                  items: widget.store
                      .categoriesFor(type)
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.name,
                          child: Row(
                            children: [
                              Icon(categoryIconData(c.icon)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (value) => setState(() => category = value),
                  validator: (value) =>
                      value == null ? 'Select a category.' : null,
                ),
              accountField(false),
              if (type == EntryType.transfer) accountField(true),
              if (widget.store.accounts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Create accounts from Home before recording transfers.',
                  ),
                ),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
