import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/recurring.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/bottom_action_bar.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/entry_type_picker.dart';
import '../core/presentation/grouped_amount_formatter.dart';
import '../core/presentation/info_button.dart';
import '../core/presentation/ledger_refresh.dart';
import '../core/presentation/responsive_pair.dart';

const _recurringInfo =
    'Monthly expenses and income are posted automatically when you open or resume Paxlee. Missed due dates are caught up. No bank connection: this updates your local ledger, not your real bank. Days 29-31 use the last day in shorter months. No weekend adjustment.';
const _recurringHistoryInfo =
    'Unpaid occurrences keep their original amount and account. Retry books the payment on today\'s date and preserves its scheduled due date in this history. Editing a rule affects future occurrences only. If a posted payment is edited or deleted in Transactions, it is never automatically recreated.';
const _recurringFormInfo =
    'Expenses and income repeat monthly in your app currency. Future changes do not alter already posted payments or unpaid bills. Choose a start date today or later; past transactions do not create recurring rules.';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  bool busy = false;
  String? error;
  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() => error = '${e.message}');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not update recurring payments. Please retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  void edit([RecurringRule? rule]) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RecurringForm(store: widget.store, rule: rule),
    ),
  );
  Future<void> remove(RecurringRule rule) async {
    final yes = await confirmAction(
      context,
      title: 'Delete recurring rule?',
      message: 'Future payments stop. Posted payments and unpaid occurrences remain for review.',
    );
    if (yes == true) {
      await action(() => widget.store.archiveRecurring(rule.id!));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Recurring payments'),
      actions: [
        InfoButton(
          title: 'Recurring payments information',
          message: '$_recurringInfo\n\n$_recurringHistoryInfo',
        ),
        IconButton(
          tooltip: 'Check due payments',
          onPressed: busy
              ? null
              : () => action(() => widget.store.processRecurring()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : () => edit(),
      icon: const Icon(Icons.add),
      label: const Text('Add recurring payment'),
    ),
    body: LedgerRefresh(
      store: widget.store,
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (widget.store.recurringRules.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No recurring payments yet. Add rent, subscriptions, salary or another monthly entry.',
                ),
              ),
            for (final rule in widget.store.recurringRules)
              Card(
                child: Column(
                  children: [
                    ListTile(
                      onTap: busy ? null : () => edit(rule),
                      title: Text(rule.description),
                      leading: Icon(
                        rule.type == EntryType.income
                            ? Icons.payments_outlined
                            : Icons.receipt_long_outlined,
                        color: rule.type == EntryType.income
                            ? Colors.green
                            : Colors.red,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rule.type == EntryType.income ? 'Income' : 'Expense'} - ${widget.store.currency.display(rule.amount)} - ${widget.store.accounts.where((a) => a.id == rule.accountId).firstOrNull?.name ?? 'Account unavailable'}',
                          ),
                          Text(
                            '${rule.active ? 'Next' : 'Paused; scheduled'}: ${dayKey(rule.nextDate)} - every ${rule.interval} month(s), day ${rule.day}',
                            style: TextStyle(
                              color: rule.active ? Colors.blue : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.edit_outlined),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: rule.active ? 'Pause' : 'Resume',
                          onPressed: busy
                              ? null
                              : () => action(
                                  () => widget.store.setRecurringActive(
                                    rule.id!,
                                    !rule.active,
                                  ),
                                ),
                          icon: Icon(
                            rule.active
                                ? Icons.pause_outlined
                                : Icons.play_arrow_outlined,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete recurring rule',
                          onPressed: busy ? null : () => remove(rule),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'History & pending entries',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final occurrence in widget.store.recurringOccurrences.take(
              100,
            ))
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: Text(
                        '${occurrence.description} - ${widget.store.currency.symbol}${widget.store.currency.formatGrouped(occurrence.amount)}',
                      ),
                      subtitle: Text(
                        '${occurrence.type.name} - ${dayKey(occurrence.date)} - ${occurrence.status == 'posted' && occurrence.transactionId == null ? 'Posted, then deleted manually' : occurrence.status}${occurrence.error == null ? '' : '\n${occurrence.error}'}',
                      ),
                    ),
                    if (occurrence.status == 'failed')
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => action(
                                      () => widget.store.retryRecurring(
                                        occurrence.id,
                                      ),
                                    ),
                              child: const Text('Retry posting'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final yes = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Skip this unpaid payment?',
                                          ),
                                          content: const Text(
                                            'No transaction will be posted. Future scheduled payments are unchanged.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Skip'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (yes == true) {
                                        await action(
                                          () => widget.store.skipRecurring(
                                            occurrence.id,
                                          ),
                                        );
                                      }
                                    },
                              child: const Text('Skip'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class RecurringForm extends StatefulWidget {
  const RecurringForm({super.key, required this.store, this.rule});
  final LedgerStore store;
  final RecurringRule? rule;
  @override
  State<RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends State<RecurringForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController description, amount, interval;
  int? accountId;
  late EntryType type;
  String? category;
  late int day;
  late DateTime start;
  DateTime? end;
  late final action = AsyncAction()..addListener(() => setState(() {}));
  bool get busy => action.busy;
  late bool isAsset, isLiability;
  String? get error => action.error;
  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    description = TextEditingController(text: rule?.description ?? '');
    amount = TextEditingController(
      text: rule == null
          ? ''
          : widget.store.currency.formatGrouped(rule.amount),
    );
    interval = TextEditingController(text: '${rule?.interval ?? 1}');
    type = rule?.type ?? EntryType.expense;
    isAsset = rule?.isAsset ?? false;
    isLiability = rule?.isLiability ?? false;
    accountId = rule?.accountId;
    category = rule?.category;
    start = rule?.nextDate ?? dateOnly(DateTime.now());
    day = rule?.day ?? start.day;
    end = rule?.endDate;
  }

  @override
  void dispose() {
    description.dispose();
    amount.dispose();
    interval.dispose();
    action.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    final saved = await action.run(
      () async => widget.store.saveRecurring(
        RecurringRule(
          id: widget.rule?.id,
          type: type,
          isAsset: type == EntryType.income && isAsset,
          isLiability: type == EntryType.expense && isLiability,
          description: description.text.trim(),
          amount: widget.store.currency.parseInput(amount.text),
          category: category!,
          accountId: accountId!,
          day: day,
          interval: int.parse(interval.text),
          nextDate: firstMonthlyDate(start, day),
          endDate: end,
          active: widget.rule?.active ?? true,
        ),
      ),
      failureMessage: 'Could not save recurring payment. Please retry.',
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.rule == null
              ? 'Add recurring payment'
              : 'Edit recurring payment',
        ),
        actions: const [
          InfoButton(
            title: 'Recurring schedule information',
            message: _recurringFormInfo,
          ),
        ],
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Save recurring payment',
        busy: busy,
        onPressed: save,
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            EntryTypePicker(
              value: type,
              types: const [EntryType.expense, EntryType.income],
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                      type = value!;
                      category = null;
                      accountId = null;
                      isAsset = false;
                      isLiability = false;
                    }),
            ),
            TextFormField(
              controller: description,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Description (e.g. Rent)',
              ),
              validator: (s) =>
                  s == null || s.trim().isEmpty ? 'Enter a description.' : null,
            ),
            const SizedBox(height: 16),
            ResponsivePair(
              left: TextFormField(
                controller: amount,
                inputFormatters: const [GroupedAmountFormatter()],
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: 'Amount (${widget.store.currency.symbol.trim()})',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (s) {
                  try {
                    if (widget.store.currency.parseInput(s ?? '') <= 0) {
                      return 'Enter an amount greater than zero.';
                    }
                  } on FormatException catch (e) {
                    return e.message;
                  }
                  return null;
                },
              ),
              right: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('category-$type'),
                initialValue: category,
                decoration: InputDecoration(
                  labelText: type == EntryType.income
                      ? 'Income category'
                      : 'Expense category',
                ),
                items: widget.store
                    .categoriesFor(type)
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.name, child: Text(c.name)),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) => setState(() => category = value),
                validator: (value) =>
                    value == null ? 'Select a category.' : null,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: ValueKey('account-$type'),
              initialValue:
                  widget.store.accounts.any(
                    (a) =>
                        a.id == accountId &&
                        (type == EntryType.income || a.available),
                  )
                  ? accountId
                  : null,
              decoration: InputDecoration(
                labelText: type == EntryType.income
                    ? 'Receiving account'
                    : 'Payment account',
              ),
              items: widget.store.accounts
                  .where((a) => type == EntryType.income || a.available)
                  .map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) => setState(() => accountId = value),
              validator: (value) => value == null
                  ? 'Select an account for this recurring entry.'
                  : null,
            ),
            const SizedBox(height: 16),
            ResponsivePair(
              left: DropdownButtonFormField<int>(
                initialValue: day,
                decoration: const InputDecoration(labelText: 'Day of month'),
                items: List.generate(
                  31,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: busy
                    ? null
                    : (value) => setState(() => day = value!),
              ),
              right: TextFormField(
                controller: interval,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Every N months'),
                keyboardType: TextInputType.number,
                validator: (s) {
                  final n = int.tryParse(s ?? '');
                  return n == null || n < 1 || n > 120
                      ? 'Use 1 to 120 months.'
                      : null;
                },
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Start on or after: ${dayKey(start)}'),
              subtitle: Text(
                'First scheduled payment: ${dayKey(firstMonthlyDate(start, day))}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: busy
                  ? null
                  : () async {
                      final today = dateOnly(DateTime.now());
                      final date = await showDatePicker(
                        context: context,
                        initialDate: start.isBefore(today) ? today : start,
                        firstDate: today,
                        lastDate: DateTime(2100),
                      );
                      if (date != null && mounted) {
                        setState(() => start = date);
                      }
                    },
            ),
            ResponsivePair(
              left: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  end == null ? 'End date: none' : 'End date: ${dayKey(end!)}',
                ),
                trailing: end == null
                    ? const Icon(Icons.calendar_today)
                    : IconButton(
                        tooltip: 'Clear end date',
                        onPressed: busy
                            ? null
                            : () => setState(() => end = null),
                        icon: const Icon(Icons.clear),
                      ),
                onTap: busy
                    ? null
                    : () async {
                        final today = dateOnly(DateTime.now());
                        final date = await showDatePicker(
                          context: context,
                          initialDate: end ?? today,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null && mounted) {
                          setState(() => end = date);
                        }
                      },
              ),
              right: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(type == EntryType.income ? 'Asset' : 'Liability'),
                value: type == EntryType.income ? isAsset : isLiability,
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (type == EntryType.income) {
                          isAsset = value;
                        } else {
                          isLiability = value;
                        }
                      }),
              ),
            ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
  );
}
