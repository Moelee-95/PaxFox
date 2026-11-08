import 'dart:async';

import 'debt_settlement_form.dart';
import '../core/presentation/debt_editor.dart';
import '../core/presentation/app_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/recurring.dart';

List<RecurringOccurrence> pendingPaymentNotifications(LedgerStore store) =>
    store.recurringOccurrences
        .where((o) => o.manual && o.status == 'failed')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

class PaymentNotificationsScreen extends StatefulWidget {
  const PaymentNotificationsScreen({
    super.key,
    required this.store,
    this.focusedOccurrence,
    this.takeDebtAction,
  });
  final LedgerStore store;
  final String? Function()? takeDebtAction;
  final ValueListenable<int?>? focusedOccurrence;

  @override
  State<PaymentNotificationsScreen> createState() =>
      _PaymentNotificationsScreenState();
}

class _PaymentNotificationsScreenState
    extends State<PaymentNotificationsScreen> {
  Timer? _deadlineTimer;
  bool loading = true;
  final pending = <int>{};
  String? error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.focusedOccurrence?.addListener(_focusChanged);
    checkDue();
    _deadlineTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => openDebtAction());
  }

  void _focusChanged() {
    if (!mounted) return;
    setState(() {});
    openDebtAction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    widget.focusedOccurrence?.removeListener(_focusChanged);
    _deadlineTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> checkDue() async {
    try {
      await widget.store.processRecurring();
    } catch (_) {
      if (mounted) error = 'Could not check due payments. Please reopen Notifications to retry.';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> confirm(RecurringOccurrence occurrence) async {
    if (pending.contains(occurrence.id)) return;
    setState(() {
      pending.add(occurrence.id);
      error = null;
    });
    try {
      await widget.store.retryRecurring(occurrence.id);
      final saved = widget.store.recurringOccurrences
          .where((o) => o.id == occurrence.id)
          .firstOrNull;
      if (mounted && saved?.status != 'posted') {
        error = saved?.error ?? 'Payment could not be confirmed. Please retry.';
      }
    } catch (_) {
      if (mounted) error = 'Payment could not be confirmed. Please retry.';
    } finally {
      if (mounted) setState(() => pending.remove(occurrence.id));
    }
  }

  Future<void> addToDebt(RecurringOccurrence occurrence) async {
    if (pending.contains(occurrence.id)) return;
    setState(() {
      pending.add(occurrence.id);
      error = null;
    });
    try {
      await widget.store.moveRecurringToDebt(occurrence.id);
    } on ArgumentError catch (e) {
      if (mounted) error = '${e.message}';
    } catch (_) {
      if (mounted) error = 'Could not add this payment to debts. Please retry.';
    } finally {
      if (mounted) setState(() => pending.remove(occurrence.id));
    }
  }

  void openDebtAction() {
    final id = widget.focusedOccurrence?.value;
    if (id == null || id >= 0 || !mounted) return;
    final action = widget.takeDebtAction?.call();
    if (action == null) return;
    final debt = widget.store.debts
        .where((d) => d.id == -id && d.hasPendingDeadline)
        .firstOrNull;
    if (debt != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) debtAction(debt, keep: action == 'keep');
      });
    }
  }

  Future<void> debtAction(Debt debt, {required bool keep}) async {
    final key = -debt.id!;
    if (pending.contains(key)) return;
    setState(() => pending.add(key));
    try {
      if (keep) {
        await widget.store.acknowledgeDebtDeadline(debt.id!, debt.deadline!);
        if (!mounted) return;
        final current = widget.store.debts
            .where((d) => d.id == debt.id)
            .firstOrNull;
        if (current == null) return;
        await showDialog<void>(
          context: context,
          builder: (_) => DebtEditor(
            currency: widget.store.currency,
            debt: current,
            lockIdentity: widget.store.debtPaymentLinks.containsValue(
              current.id,
            ),
            onSave: widget.store.saveDebt,
            onDelete: () => widget.store.deleteDebt(current.id!),
          ),
        );
      } else {
        await showAppSheet<bool>(
          context,
          editor: true,
          builder: (_) => DebtSettlementForm(store: widget.store, debt: debt),
        );
      }
    } catch (_) {
      if (mounted) error = 'Could not open this debt. Please retry.';
    } finally {
      if (mounted) setState(() => pending.remove(key));
    }
  }

  Widget deadlineCard(Debt debt, int? focus) => Card(
    key: ValueKey('debt-notification-${debt.id}'),
    color: focus == -debt.id!
        ? Theme.of(context).colorScheme.primaryContainer
        : null,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(debt.name, style: Theme.of(context).textTheme.titleMedium),
          Text(
            '${debt.isReceivable ? 'Money owed to you' : 'Debt'}: ${debt.currency.display(debt.amount)}',
          ),
          Text(
            'Due ${dayKey(debt.deadline!)} ${TimeOfDay.fromDateTime(debt.deadline!).format(context)}',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: pending.contains(-debt.id!)
                ? null
                : () => debtAction(debt, keep: true),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Keep / edit'),
          ),
          FilledButton.icon(
            onPressed: pending.contains(-debt.id!)
                ? null
                : () => debtAction(debt, keep: false),
            icon: const Icon(Icons.payments_outlined),
            label: Text(debt.isReceivable ? 'Receive payment' : 'Pay debt'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications'), centerTitle: true),
    body: ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final items = <Object>[
          ...widget.store.dueDebts(),
          ...pendingPaymentNotifications(widget.store),
        ];
        int itemId(Object item) =>
            item is Debt ? -item.id! : (item as RecurringOccurrence).id;
        final focus = widget.focusedOccurrence?.value;
        final focusedIndex = items.indexWhere((o) => itemId(o) == focus);
        // Put the opened reminder in view without estimating variable row heights.
        // All other pending payments retain their chronological order.
        if (focusedIndex > 0) items.insert(0, items.removeAt(focusedIndex));
        return Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          loading
                              ? 'Checking payments...'
                              : 'No payments awaiting confirmation.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final raw = items[index];
                        if (raw is Debt) return deadlineCard(raw, focus);
                        final item = raw as RecurringOccurrence;
                        final account = widget.store.accounts
                            .where((a) => a.id == item.accountId)
                            .firstOrNull;
                        final busy = pending.contains(item.id);
                        return Card(
                          key: ValueKey('payment-notification-${item.id}'),
                          color: item.id == focus
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          shape: item.id == focus
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    width: 2,
                                  ),
                                )
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (item.id == focus)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'Opened from reminder',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium,
                                    ),
                                  ),
                                Text(
                                  item.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.type == EntryType.income ? 'Income' : 'Expense'} - ${(item.currency ?? widget.store.currency).display(item.amount)}',
                                ),
                                Text('Due: ${dayKey(item.date)}'),
                                if (account != null) Text(account.name),
                                if (item.error != null)
                                  Text(
                                    item.error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                    side: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => addToDebt(item),
                                  icon: const Icon(
                                    Icons.account_balance_outlined,
                                  ),
                                  label: Text(
                                    item.type == EntryType.income
                                        ? 'Add to money owed to me'
                                        : 'Add to debts',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                FilledButton.icon(
                                  key: ValueKey('confirm-payment-${item.id}'),
                                  onPressed: busy ? null : () => confirm(item),
                                  icon: busy
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.check),
                                  label: Text(
                                    item.type == EntryType.income
                                        ? 'Confirm received'
                                        : 'Confirm paid',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
