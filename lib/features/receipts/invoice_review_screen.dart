import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/data/ledger_store.dart';
import '../../core/domain/ledger.dart';
import 'invoice.dart';
import 'invoice_images.dart';

class InvoiceReviewScreen extends StatefulWidget {
  const InvoiceReviewScreen({
    super.key,
    required this.store,
    required this.draft,
    this.images = const [],
    this.storedPaths = const [],
    this.entry,
  });
  final LedgerStore store;
  final InvoiceDraft draft;
  final List<File> images;
  final List<String> storedPaths;
  final LedgerEntry? entry;
  @override
  State<InvoiceReviewScreen> createState() => _InvoiceReviewScreenState();
}

class _InvoiceReviewScreenState extends State<InvoiceReviewScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController merchant, total, adjustment, note;
  late List<InvoiceItem> items;
  DateTime? date;
  String? category;
  int? accountId;
  bool busy = false, euroConfirmed = false;
  String? error;
  bool showItemErrors = false;
  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    merchant = TextEditingController(
      text: widget.entry?.description ?? draft.merchant,
    );
    total = TextEditingController(
      text: draft.total == null ? '' : Currency.eur.format(draft.total!),
    );
    adjustment = TextEditingController(
      text: Currency.eur.format(draft.adjustment ?? 0),
    );
    note = TextEditingController(text: draft.adjustmentNote);
    items = expandInvoiceItems(draft.items);
    date = widget.entry?.date ?? draft.date;
    category = widget.entry?.category ?? draft.category;
    accountId = widget.entry?.accountId;
    euroConfirmed = draft.currency == 'EUR';
  }

  @override
  void dispose() {
    for (final c in [merchant, total, adjustment, note]) {
      c.dispose();
    }
    super.dispose();
  }

  int signed(String s) {
    final text = s.trim();
    return Currency.eur.parse(text.replaceFirst(RegExp(r'^-'), '')) *
        (text.startsWith('-') ? -1 : 1);
  }

  Future<void> editItem([int? index]) async {
    final result = await showDialog<InvoiceItem>(
      context: context,
      builder: (_) => InvoiceItemDialog(
        item: index == null ? null : items[index],
        categories: widget.store
            .categoriesFor(EntryType.expense)
            .map((c) => c.name)
            .toList(),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          items.add(result);
        } else {
          items[index] = result;
        }
      });
    }
  }

  Future<void> save() async {
    setState(() {
      showItemErrors = true;
      error = null;
    });
    final availableCategories = widget.store
        .categoriesFor(EntryType.expense)
        .map((c) => c.name)
        .toSet();
    final hasItemErrors = items.any(
      (item) => invoiceItemError(item, availableCategories) != null,
    );
    final validForm = form.currentState!.validate();
    if (hasItemErrors || !validForm) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    var retained = <String>[];
    try {
      final draft = InvoiceDraft(
        merchant: merchant.text.trim(),
        date: date,
        currency: 'EUR',
        total: Currency.eur.parse(total.text),
        category: category,
        adjustment: signed(adjustment.text),
        adjustmentNote: note.text.trim(),
        items: items,
        raw: widget.draft.raw,
      );
      validateInvoice(
        draft,
        widget.store
            .categoriesFor(EntryType.expense)
            .map((c) => c.name)
            .toSet(),
      );
      retained = await InvoiceImages().retain(widget.images);
      if (widget.entry == null) {
        await widget.store.saveInvoiceBatch(
          draft: draft,
          accountId: accountId!,
          imagePaths: retained,
        );
      } else {
        await widget.store.saveInvoice(
          draft: draft,
          accountId: accountId!,
          imagePaths: [...widget.storedPaths, ...retained],
          transactionId: widget.entry!.id,
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      await InvoiceImages().remove(retained);
      if (mounted) {
        setState(() {
          busy = false;
          error = e is ArgumentError ? '${e.message}' : 'Could not save invoice. No partial transaction was created. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = items.fold<int>(0, (sum, item) => sum + (item.total ?? 0));
    int? adjusted;
    try {
      adjusted = sum + signed(adjustment.text);
    } on FormatException {
      adjusted = null;
    }
    int? charged;
    try {
      charged = Currency.eur.parse(total.text);
    } on FormatException {
      charged = null;
    }
    final names = widget.store
        .categoriesFor(EntryType.expense)
        .map((c) => c.name)
        .toList();
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? 'Saving...'
                  : widget.entry == null
                  ? 'Save transactions'
                  : 'Save invoice expense',
            ),
          ),
        ),
        appBar: AppBar(
          title: const Text('Review invoice'),
          actions: [
            if (widget.entry != null)
              IconButton(
                tooltip: 'Delete invoice',
                onPressed: busy
                    ? null
                    : () async {
                        final yes = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete invoice?'),
                            content: const Text(
                              'The expense, attached item details and stored photos will be removed.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (yes != true || !mounted) {
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await widget.store.deleteEntry(widget.entry!.id!);
                          await InvoiceImages().remove(widget.storedPaths);
                          if (context.mounted) {
                            Navigator.pop(context, true);
                          }
                        } catch (_) {
                          if (mounted) {
                            setState(() {
                              busy = false;
                              error = 'Could not delete invoice.';
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        body: Form(
          key: form,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              const Text(
                'Review the extracted items. Each item saves as a separate transaction with its own description, price and category, using the date and payment account below. Discounts save as refunds. All items are saved together.',
              ),
              for (final file in widget.images)
                SizedBox(
                  height: 180,
                  child: Image.file(
                    file,
                    errorBuilder: (_, _, _) => const Text('Image unavailable'),
                  ),
                ),
              for (final path in widget.storedPaths)
                FutureBuilder<File>(
                  future: InvoiceImages().resolve(path),
                  builder: (_, snapshot) => snapshot.hasData
                      ? SizedBox(
                          height: 180,
                          child: Image.file(
                            snapshot.data!,
                            errorBuilder: (_, _, _) =>
                                const Text('Stored image unavailable'),
                          ),
                        )
                      : const SizedBox(height: 30),
                ),
              if (widget.draft.currency != 'EUR')
                Text(
                  'Detected currency: ${widget.draft.currency ?? 'unknown'}. Only EUR invoices can be saved. Do not relabel a foreign-currency amount.',
                ),
              FormField<bool>(
                initialValue: euroConfirmed,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) => euroConfirmed
                    ? null
                    : 'Confirm that the original invoice is in EUR.',
                builder: (field) => InputDecorator(
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    errorText: field.errorText,
                  ),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('I confirm this invoice is in EUR'),
                    value: euroConfirmed,
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => euroConfirmed = v!);
                            field.didChange(v);
                          },
                  ),
                ),
              ),
              TextFormField(
                controller: merchant,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Merchant / description',
                ),
                validator: (s) =>
                    s == null || s.trim().isEmpty ? 'Enter a merchant.' : null,
              ),
              FormField<DateTime>(
                initialValue: date,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (_) => date == null
                    ? 'Choose the invoice date. It could not be determined from the scan.'
                    : null,
                builder: (field) => InputDecorator(
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    errorText: field.errorText,
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      date == null
                          ? 'Invoice date: choose date'
                          : 'Invoice date: ${dayKey(date!)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: busy
                        ? null
                        : () async {
                            final chosen = await showDatePicker(
                              context: context,
                              initialDate: date ?? DateTime.now(),
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2100),
                            );
                            if (chosen != null && mounted) {
                              setState(() => date = chosen);
                              field.didChange(chosen);
                            }
                          },
                  ),
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: names.contains(category) ? category : null,
                decoration: const InputDecoration(
                  labelText: 'Expense category',
                ),
                items: names
                    .map(
                      (name) =>
                          DropdownMenuItem(value: name, child: Text(name)),
                    )
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => category = v),
                validator: (s) => s == null ? 'Select a category.' : null,
              ),
              DropdownButtonFormField<int>(
                initialValue:
                    widget.store.accounts.any(
                      (a) => a.id == accountId && a.available,
                    )
                    ? accountId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Paid from (cash or bank)',
                ),
                items: widget.store.accounts
                    .where((a) => a.available)
                    .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                    )
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => accountId = v),
                validator: (id) => id == null
                    ? 'Choose the cash or bank account used to pay this invoice.'
                    : null,
              ),
              const SizedBox(height: 20),
              Text(
                'Items (${items.length})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (var i = 0; i < items.length; i++)
                Card(
                  key: ValueKey('invoice-item-$i'),
                  shape:
                      showItemErrors &&
                          invoiceItemError(items[i], names.toSet()) != null
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.error,
                            width: 2,
                          ),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        onTap: busy ? null : () => editItem(i),
                        title: Text(
                          items[i].description.isEmpty
                              ? 'Missing item name'
                              : items[i].description,
                        ),
                        subtitle: Text(items[i].category ?? 'Choose category'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              items[i].total == null
                                  ? 'Check price'
                                  : 'EUR ${Currency.eur.format(items[i].total!)}',
                            ),
                            IconButton(
                              tooltip: 'Delete item',
                              onPressed: busy
                                  ? null
                                  : () => setState(() => items.removeAt(i)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      if (showItemErrors &&
                          invoiceItemError(items[i], names.toSet()) != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            invoiceItemError(items[i], names.toSet())!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : () => editItem(),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
              Text('Item subtotal: EUR ${Currency.eur.format(sum)}'),
              TextFormField(
                controller: adjustment,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Adjustment (EUR, signed)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (s) {
                  try {
                    signed(s ?? '');
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: note,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Adjustment explanation / notes',
                ),
              ),
              TextFormField(
                controller: total,
                enabled: !busy,
                decoration: const InputDecoration(
                  labelText: 'Charged total (EUR)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (s) {
                  try {
                    if (Currency.eur.parse(s ?? '') <= 0) {
                      return 'Enter a positive charged amount.';
                    }
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              Text(
                adjusted == charged && charged != null
                    ? 'Prices add up. Verify the charged total against the original invoice.'
                    : 'Total mismatch: item subtotal plus adjustments must equal the charged total.',
                style: TextStyle(
                  color: adjusted == charged && charged != null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              if (widget.draft.raw.isNotEmpty)
                ExpansionTile(
                  title: const Text('Original AI response'),
                  children: [SelectableText(widget.draft.raw)],
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class InvoiceItemDialog extends StatefulWidget {
  const InvoiceItemDialog({super.key, this.item, required this.categories});
  final InvoiceItem? item;
  final List<String> categories;
  @override
  State<InvoiceItemDialog> createState() => _InvoiceItemDialogState();
}

class _InvoiceItemDialogState extends State<InvoiceItemDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name = TextEditingController(
        text: widget.item?.description ?? '',
      ),
      price = TextEditingController(
        text: widget.item?.total == null
            ? ''
            : Currency.eur.format(widget.item!.total!),
      );
  late String? category = widget.item?.category;
  @override
  void dispose() {
    name.dispose();
    price.dispose();
    super.dispose();
  }

  int signed(String value) {
    final text = value.trim();
    return Currency.eur.parse(text.replaceFirst(RegExp(r'^-'), '')) *
        (text.startsWith('-') ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review item'),
    content: Form(
      key: form,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Item name'),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Enter a name.' : null,
            ),
            TextFormField(
              controller: price,
              decoration: const InputDecoration(labelText: 'Price (EUR)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (s) {
                try {
                  signed(s ?? '');
                } on FormatException catch (e) {
                  return e.message;
                }
                return null;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: widget.categories.contains(category)
                  ? category
                  : null,
              decoration: const InputDecoration(labelText: 'Item category'),
              items: widget.categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => category = v,
              validator: (s) => s == null ? 'Select a category.' : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(
              context,
              InvoiceItem(
                description: name.text.trim(),
                quantity: '1',
                total: signed(price.text),
                category: category,
                edited: true,
              ),
            );
          }
        },
        child: const Text('Apply item'),
      ),
    ],
  );
}
