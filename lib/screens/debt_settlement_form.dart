import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/currency_exchange.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/transaction_tile.dart';
import '../core/presentation/entry_editor_sheet.dart';
import '../core/presentation/grouped_amount_formatter.dart';

class DebtSettlementForm extends StatefulWidget {
  const DebtSettlementForm({
    super.key,
    required this.store,
    required this.debt,
    this.entry,
    this.onSavedDate,
  });
  final LedgerStore store;
  final Debt debt;
  final LedgerEntry? entry;
  final ValueChanged<DateTime>? onSavedDate;
  @override
  State<DebtSettlementForm> createState() => _DebtSettlementFormState();
}

class _DebtSettlementFormState extends State<DebtSettlementForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(),
      rate = TextEditingController(),
      fee = TextEditingController(text: '0');
  late final description = TextEditingController(
    text: widget.entry?.description ?? widget.debt.name,
  );
  late final action = AsyncAction()
    ..addListener(() {
      if (mounted) setState(() {});
    });
  Account? account;
  late DateTime? createdAt = widget.entry?.createdAt;
  late DateTime date = widget.entry?.date ?? dateOnly(DateTime.now());
  ConversionRate? suggested;
  String suggestedText = '';
  bool loading = false, loadFailed = false;
  int oldPrincipal = 0;
  LedgerEntry? oldFee;
  bool get cross =>
      account != null && account!.currency != widget.debt.currency;
  @override
  void initState() {
    super.initState();
    account =
        widget.store.accounts
            .where((a) => a.id == widget.entry?.accountId)
            .firstOrNull ??
        widget.store.accounts.firstOrNull;
    amount.text = widget.debt.currency.formatGrouped(widget.debt.amount);
    setDefault();
    amount.addListener(refreshPreview);
    if (widget.entry != null) load();
  }

  void refreshPreview() {
    if (mounted) setState(() {});
  }

  void setDefault() {
    suggested = account == null
        ? null
        : widget.store.exchangeTable.rate(
            widget.debt.currency,
            account!.currency,
          );
    suggestedText = suggested?.text ?? '';
    rate.text = suggestedText;
    fee.text = '0';
  }

  Future<void> load() async {
    loading = true;
    try {
      final link = await widget.store.debtSettlement(widget.entry!.id!);
      if (!mounted) return;
      if (link == null) throw StateError('Settlement no longer exists.');
      oldPrincipal = link['amount'] as int;
      amount.text = widget.debt.currency.formatGrouped(oldPrincipal);
      oldFee = widget.store.entries
          .where((e) => e.id == link['fee_transaction_id'])
          .firstOrNull;
      if (account != null) {
        // Derive from current native movements if the account currency was changed later.
        final details = link['details'] == null
            ? null
            : jsonDecode(link['details'] as String) as Map<String, dynamic>;
        suggested =
            details != null &&
                details['account_currency'] == account!.currency.name
            ? ConversionRate.fromMap(
                Map<String, dynamic>.from(details['rate'] as Map),
              )
            : ConversionRate.fromAmounts(
                oldPrincipal,
                widget.debt.currency,
                widget.entry!.accountAmount ?? widget.entry!.amount,
                account!.currency,
              );
        suggestedText = suggested!.text;
        rate.text = suggestedText;
        fee.text = account!.currency.formatGrouped(
          oldFee?.accountAmount ?? oldFee?.amount ?? 0,
        );
      }
    } catch (_) {
      loadFailed = true;
      await action.run(() async {
        throw StateError('Could not load this settlement. Reopen it to retry.');
      }, failureMessage: 'Could not load the settlement. Reopen it to retry.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  ConversionRate get conversion => !cross
      ? ConversionRate.parse('1')
      : rate.text == suggestedText && suggested != null
      ? suggested!
      : ConversionRate.parse(rate.text);
  ({int native, int fee, int balance})? get preview {
    if (account == null) return null;
    try {
      final a = account!;
      final native = conversion.convert(
        widget.debt.currency.parseInput(amount.text),
        widget.debt.currency,
        a.currency,
      );
      final charge = cross ? a.currency.parseInput(fee.text) : 0;
      // Project the balance through the chosen date and replace the previous effects.
      var balance = accountBalance(a, widget.store.entries, date);
      for (final old in [widget.entry, oldFee].whereType<LedgerEntry>()) {
        if (!old.date.isAfter(date) &&
            (a.includeOnAsOf
                ? !old.date.isBefore(a.asOf)
                : old.date.isAfter(a.asOf))) {
          balance -= old.changeFor(a);
        }
      }
      if (a.includeOnAsOf ? !date.isBefore(a.asOf) : date.isAfter(a.asOf)) {
        balance += (widget.debt.isReceivable ? native : -native) - charge;
      }
      return (native: native, fee: charge, balance: balance);
    } on FormatException {
      return null;
    }
  }

  Future<void> save() async {
    if (loading || loadFailed || !form.currentState!.validate()) return;
    final saved = await action.run(() async {
      if (account == null) throw ArgumentError('Select an account.');
      await widget.store.settleDebt(
        debtId: widget.debt.id!,
        principal: widget.debt.currency.parseInput(amount.text),
        accountId: account!.id!,
        rate: conversion,
        fee: cross ? account!.currency.parseInput(fee.text) : 0,
        date: date,
        transactionId: widget.entry?.id,
        description: description.text.trim(),
        createdAt: createdAt,
      );
    }, failureMessage: 'Could not save the payment. Please retry.');
    if (saved && mounted) {
      widget.onSavedDate?.call(date);
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    for (final c in [amount, rate, fee, description]) {
      c.dispose();
    }
    action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final busy = action.busy || loading;
    return Form(
      key: form,
      child: EntryEditorSheet(
        title: widget.debt.isReceivable ? 'Receive payment' : 'Pay debt',
        type: widget.debt.isReceivable ? EntryType.income : EntryType.expense,
        currency: widget.debt.currency,
        amount: amount,
        amountLabel: 'Debt payment',
        actions: [
          if (widget.entry != null)
            IconButton(
              tooltip: 'Delete payment',
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: busy
                  ? null
                  : () async {
                      final yes = await confirmAction(
                        context,
                        title: 'Delete payment?',
                        message: 'This also removes its fee and restores the outstanding balance.',
                      );
                      if (yes != true || !mounted) return;
                      final deleted = await action.run(
                        () => widget.store.deleteEntry(widget.entry!.id!),
                        failureMessage: 'Could not delete the payment.',
                      );
                      if (deleted && context.mounted) {
                        Navigator.pop(context, true);
                      }
                    },
            ),
        ],
        categoryPicker: Text(
          widget.debt.name,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        saveLabel: widget.entry == null ? 'Confirm payment' : 'Save payment',
        onSave: save,
        busy: busy,
        amountValidator: (v) {
          try {
            final n = widget.debt.currency.parseInput(v ?? '');
            if (n <= 0 || n > widget.debt.amount + oldPrincipal) {
              return 'Enter an amount up to the outstanding balance.';
            }
          } on FormatException catch (e) {
            return e.message;
          }
          return null;
        },
        children: [
          Text(
            'Outstanding: ${widget.debt.currency.display(widget.debt.amount + oldPrincipal)}',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: account?.id,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Payment account'),
            items: [
              for (final a in widget.store.accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text('${a.name} (${a.currency.code})'),
                ),
            ],
            onChanged: busy
                ? null
                : (id) => setState(() {
                    account = widget.store.accounts.firstWhere(
                      (a) => a.id == id,
                    );
                    setDefault();
                  }),
          ),
          if (cross) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: rate,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [GroupedAmountFormatter()],
              decoration: InputDecoration(
                labelText:
                    '1 ${widget.debt.currency.code} = X ${account!.currency.code}',
                helperText: suggested == null
                    ? 'No default rate. Enter the actual rate.'
                    : 'Default rate; editable for this payment.',
              ),
              onChanged: (_) => setState(() {}),
              validator: (_) {
                try {
                  conversion;
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: fee,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [GroupedAmountFormatter()],
              decoration: InputDecoration(
                labelText: 'Fee (${account!.currency.code})',
                helperText: 'Recorded as a separate expense.',
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                try {
                  account!.currency.parseInput(v ?? '');
                  return null;
                } on FormatException catch (e) {
                  return e.message;
                }
              },
            ),
          ],
          if (p != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '${widget.debt.isReceivable ? 'Received' : 'Deducted'}: ${account!.currency.display(widget.debt.isReceivable ? p.native - p.fee : p.native + p.fee)}\nBalance after payment: ${account!.currency.display(p.balance)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Date'),
            subtitle: Text(dayKey(date)),
            onTap: busy
                ? null
                : () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200),
                    );
                    if (d != null) setState(() => date = d);
                  },
          ),
          if (createdAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history),
              title: const Text('Added on'),
              subtitle: Text(creationTimestamp(context, createdAt!)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: busy
                  ? null
                  : () async {
                      final original = createdAt!.toLocal();
                      final chosen = await showDatePicker(
                        context: context,
                        initialDate: dateOnly(original),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (chosen == null || !context.mounted) return;
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(original),
                      );
                      if (time != null && mounted) {
                        setState(
                          () => createdAt = DateTime(
                            chosen.year,
                            chosen.month,
                            chosen.day,
                            time.hour,
                            time.minute,
                          ).toUtc(),
                        );
                      }
                    },
            ),
          TextFormField(
            controller: description,
            enabled: !busy,
            decoration: const InputDecoration(labelText: 'Description'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Enter a description.' : null,
          ),
          if (action.error != null)
            Text(
              action.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
