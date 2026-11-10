import 'package:flutter/material.dart';

import '../core/presentation/busy_label.dart';

import '../core/data/ledger_store.dart';
import '../core/data/recurring_notifications.dart';
import '../core/domain/ledger.dart';
import '../core/domain/category.dart';
import '../core/domain/recurring.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/entry_editor_sheet.dart';
import '../core/presentation/category_picker.dart';
import '../core/presentation/app_sheet.dart';
import '../core/presentation/info_button.dart';
import '../core/presentation/ledger_refresh.dart';
import '../core/presentation/responsive_pair.dart';
import '../core/presentation/recurring_payment_card.dart';

const _recurringInfo =
    'Automatic recurring entries are posted when you open or resume PaxFox. Manual entries wait for confirmation and can show reminders at your chosen local time. Missed due dates are kept separately. No bank connection: this updates your local ledger, not your real bank. Days 29-31 use the last day in shorter months. No weekend adjustment.';
const _recurringHistoryInfo =
    'Unpaid occurrences keep their original amount and account. Retry books the payment on today\'s date and preserves its scheduled due date in this history. Editing a rule affects future occurrences only. If a posted payment is edited or deleted in Transactions, it is never automatically recreated.';
const _recurringFormInfo =
    'Expenses and income can repeat daily, weekly, monthly or yearly in the chosen app or account currency. Future changes do not alter already posted payments or unpaid bills. Choose a start date today or later; past transactions do not create recurring rules.';

String _historyStatus(RecurringOccurrence occurrence) {
  if (occurrence.status == 'posted' && occurrence.transactionId == null) {
    return 'Posted, then deleted manually';
  }
  if (occurrence.status == 'skipped' &&
      occurrence.error?.startsWith('Moved to') == true) {
    return occurrence.error!;
  }
  final status = occurrence.manual && occurrence.status == 'failed'
      ? 'Awaiting confirmation'
      : occurrence.status;
  return '$status${occurrence.error == null ? '' : '\n${occurrence.error}'}';
}

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _switchChanges = <int, bool>{};
  bool busy = false;
  String? error;
  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
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

  Future<void> setActive(RecurringRule rule, bool value) async {
    final id = rule.id!;
    if (busy || _switchChanges.containsKey(id)) return;
    setState(() {
      _switchChanges[id] = value;
      error = null;
    });
    try {
      await widget.store.setRecurringActive(id, value);
    } on ArgumentError catch (e) {
      if (mounted) setState(() => error = '${e.message}');
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not update this payment. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _switchChanges.remove(id));
    }
  }

  void edit([RecurringRule? rule]) => showAppSheet<void>(
    context,
    editor: true,
    builder: (_) => RecurringForm(store: widget.store, rule: rule),
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
          icon: busy
              ? const BusyLabel(busy: true, label: '')
              : const Icon(Icons.refresh),
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
        builder: (context, _) {
          final pendingDates = <int, DateTime>{};
          for (final occurrence in widget.store.recurringOccurrences.where(
            (o) => o.status == 'failed',
          )) {
            final previous = pendingDates[occurrence.ruleId];
            if (previous == null || occurrence.date.isBefore(previous)) {
              pendingDates[occurrence.ruleId] = occurrence.date;
            }
          }
          final accounts = {
            for (final account in widget.store.accounts) account.id: account,
          };
          return ListView(
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
                AbsorbPointer(
                  absorbing: _switchChanges.containsKey(rule.id),
                  child: RecurringPaymentCard(
                    rule: rule,
                    activeValue: _switchChanges[rule.id],
                    currency: rule.currency ?? widget.store.currency,
                    accountName:
                        accounts[rule.accountId]?.name ?? 'Account unavailable',
                    categoryIcon:
                        widget.store
                            .categoryFor(rule.category, rule.type)
                            ?.icon ??
                        CategoryIcon.general,
                    categoryColor: widget.store
                        .categoryFor(rule.category, rule.type)
                        ?.color,
                    pendingDate: pendingDates[rule.id],
                    onEdit: busy ? null : () => edit(rule),
                    onDelete: busy ? null : () => remove(rule),
                    onActiveChanged: busy
                        ? null
                        : (value) => setActive(rule, value),
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
                          '${occurrence.description} - ${(occurrence.currency ?? widget.store.currency).display(occurrence.amount)}',
                        ),
                        subtitle: Text(
                          '${occurrence.type.name} - ${dayKey(occurrence.date)} - ${_historyStatus(occurrence)}',
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
                                child: Text(
                                  occurrence.manual
                                      ? 'Confirm payment'
                                      : 'Retry posting',
                                ),
                              ),
                              if (!occurrence.manual)
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
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
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
          );
        },
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
  late Currency inputCurrency;
  String? category;
  late int day;
  late RecurrenceFrequency frequency;
  late int yearlyMonth;
  late bool automatic;
  late TimeOfDay reminderTime;
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
    inputCurrency = rule?.currency ?? widget.store.currency;
    description = TextEditingController(text: rule?.description ?? '');
    amount = TextEditingController(
      text: rule == null ? '' : inputCurrency.formatGrouped(rule.amount),
    );
    interval = TextEditingController(text: '${rule?.interval ?? 1}');
    type = rule?.type ?? EntryType.expense;
    isAsset = rule?.isAsset ?? false;
    isLiability = rule?.isLiability ?? false;
    accountId = rule?.accountId;
    category = rule?.category;
    start = rule?.nextDate ?? dateOnly(DateTime.now());
    day = rule?.day ?? start.day;
    frequency = rule?.frequency ?? RecurrenceFrequency.month;
    yearlyMonth = rule?.month ?? start.month;
    automatic = rule?.automatic ?? true;
    final minutes = rule?.reminderMinutes ?? 540;
    reminderTime = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
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
    final saved = await action.run(() async {
      if (!automatic &&
          widget.store.notificationsEnabled &&
          RecurringNotifications.instance != null) {
        try {
          final enabled = await RecurringNotifications.instance!
              .requestPermissions();
          if (!mounted) return;
          if (!enabled) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Notifications are disabled. The payment will still wait for confirmation in Recurring.',
                ),
              ),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not enable notifications. Confirm pending payments in Recurring.',
                ),
              ),
            );
          }
        }
      }
      if (!mounted) return;
      await widget.store.saveRecurring(
        RecurringRule(
          id: widget.rule?.id,
          type: type,
          isAsset: type == EntryType.income && isAsset,
          isLiability: type == EntryType.expense && isLiability,
          description: description.text.trim(),
          amount: inputCurrency.parseInput(amount.text),
          currency: inputCurrency,
          category: category!,
          accountId: accountId!,
          day: day,
          interval: int.parse(interval.text),
          nextDate: firstRecurringDate(start, frequency, day, yearlyMonth),
          frequency: frequency,
          month: yearlyMonth,
          automatic: automatic,
          reminderMinutes: reminderTime.hour * 60 + reminderTime.minute,
          endDate: end,
          active: widget.rule?.active ?? true,
        ),
      );
    }, failureMessage: 'Could not save recurring payment. Please retry.');
    if (saved && mounted) Navigator.pop(context);
  }

  Account? get selectedAccount =>
      widget.store.accounts.where((a) => a.id == accountId).firstOrNull;

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: EntryEditorSheet(
      title: widget.rule == null
          ? 'Add recurring payment'
          : 'Edit recurring payment',
      type: type,
      currency: inputCurrency,
      amount: amount,
      busy: busy,
      saveLabel: 'Save recurring payment',
      onSave: save,
      amountLabel: 'Amount (${inputCurrency.symbol.trim()})',
      amountValidator: (s) {
        try {
          if (inputCurrency.parseInput(s ?? '') <= 0) {
            return 'Enter an amount greater than zero.';
          }
        } on FormatException catch (e) {
          return e.message;
        }
        return null;
      },
      categoryPicker: CategoryPickerField(
        store: widget.store,
        type: type,
        value: category,
        header: true,
        enabled: !busy,
        types: const [EntryType.expense, EntryType.income],
        onChanged: (value) => setState(() {
          if (type != value.type) {
            accountId = null;
            inputCurrency = widget.store.currency;
            isAsset = false;
            isLiability = false;
          }
          type = value.type;
          category = value.name;
        }),
      ),
      actions: const [
        InfoButton(
          title: 'Recurring schedule information',
          message: _recurringFormInfo,
        ),
      ],
      children: [
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
              .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                  int? base;
                  try {
                    final parsed = inputCurrency.parseInput(amount.text);
                    base = inputCurrency == widget.store.currency
                        ? parsed
                        : selectedAccount?.toBase(parsed);
                  } on FormatException {
                    /* No complete amount yet. */
                  }
                  accountId = value;
                  // Recurring entries default to the selected bank's native currency.
                  inputCurrency = selectedAccount!.currency;
                  if (base != null) {
                    amount.text = inputCurrency.formatGrouped(
                      selectedAccount!.fromBase(base),
                    );
                  }
                }),
          validator: (value) => value == null
              ? 'Select an account for this recurring entry.'
              : null,
        ),
        const SizedBox(height: 16),
        if (selectedAccount != null &&
            selectedAccount!.currency != widget.store.currency) ...[
          DropdownButtonFormField<Currency>(
            key: ValueKey(('recurring-currency', inputCurrency, accountId)),
            initialValue: inputCurrency,
            decoration: const InputDecoration(
              labelText: 'Recurring amount currency',
            ),
            items: [widget.store.currency, selectedAccount!.currency]
                .map((c) => DropdownMenuItem(value: c, child: Text(c.code)))
                .toList(),
            onChanged: busy
                ? null
                : (value) => setState(() {
                    try {
                      final parsed = inputCurrency.parseInput(amount.text);
                      final base = inputCurrency == widget.store.currency
                          ? parsed
                          : selectedAccount!.toBase(parsed);
                      amount.text = value!.formatGrouped(
                        value == widget.store.currency
                            ? base
                            : selectedAccount!.fromBase(base),
                      );
                    } on FormatException {
                      /* Empty amount remains empty. */
                    }
                    inputCurrency = value!;
                  }),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: amount,
            builder: (_, value, _) {
              try {
                final parsed = inputCurrency.parseInput(value.text);
                return Text(
                  'Current equivalent: ${widget.store.currency.display(inputCurrency == widget.store.currency ? parsed : selectedAccount!.toBase(parsed))}',
                );
              } on FormatException {
                return const SizedBox.shrink();
              }
            },
          ),
          const SizedBox(height: 16),
        ],
        DropdownButtonFormField<RecurrenceFrequency>(
          initialValue: frequency,
          decoration: const InputDecoration(labelText: 'Repeat every'),
          items: RecurrenceFrequency.values
              .map(
                (f) => DropdownMenuItem(
                  value: f,
                  child: Text(switch (f) {
                    RecurrenceFrequency.day => 'Day',
                    RecurrenceFrequency.week => 'Week',
                    RecurrenceFrequency.month => 'Month',
                    RecurrenceFrequency.year => 'Year',
                  }),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                  frequency = value!;
                  day = frequency == RecurrenceFrequency.week
                      ? start.weekday
                      : start.day;
                }),
        ),
        const SizedBox(height: 16),
        ResponsivePair(
          left: frequency == RecurrenceFrequency.day
              ? const Text('Every selected number of days')
              : DropdownButtonFormField<int>(
                  key: ValueKey(('schedule-day', frequency, day)),
                  initialValue: day,
                  decoration: InputDecoration(
                    labelText: frequency == RecurrenceFrequency.week
                        ? 'Day of week'
                        : 'Day of month',
                  ),
                  items: List.generate(
                    frequency == RecurrenceFrequency.week ? 7 : 31,
                    (i) => DropdownMenuItem(
                      value: i + 1,
                      child: Text(
                        frequency == RecurrenceFrequency.week
                            ? const [
                                'Monday',
                                'Tuesday',
                                'Wednesday',
                                'Thursday',
                                'Friday',
                                'Saturday',
                                'Sunday',
                              ][i]
                            : '${i + 1}',
                      ),
                    ),
                  ),
                  onChanged: busy
                      ? null
                      : (value) => setState(() => day = value!),
                ),
          right: TextFormField(
            controller: interval,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'Every N ${frequency.name}s',
            ),
            keyboardType: TextInputType.number,
            validator: (s) {
              final n = int.tryParse(s ?? '');
              return n == null || n < 1 || n > 120 ? 'Use 1 to 120.' : null;
            },
          ),
        ),
        if (frequency == RecurrenceFrequency.year)
          DropdownButtonFormField<int>(
            initialValue: yearlyMonth,
            decoration: const InputDecoration(labelText: 'Month of year'),
            items: List.generate(
              12,
              (i) => DropdownMenuItem(
                value: i + 1,
                child: Text(
                  MaterialLocalizations.of(context)
                      .formatMonthYear(DateTime(2000, i + 1))
                      .replaceAll('2000', '')
                      .trim(),
                ),
              ),
            ),
            onChanged: busy
                ? null
                : (value) => setState(() => yearlyMonth = value!),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Post automatically'),
          subtitle: Text(
            automatic
                ? 'Book due payments without confirmation'
                : 'Keep pending until you confirm payment',
          ),
          value: automatic,
          onChanged: busy ? null : (value) => setState(() => automatic = value),
        ),
        if (!automatic)
          const Text(
            'Your phone may allow notification dismissal. Payments remain pending here until confirmed. Open PaxFox regularly to refresh reminders.',
          ),
        if (!automatic)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Reminder time: ${reminderTime.format(context)}'),
            trailing: const Icon(Icons.notifications_outlined),
            onTap: busy
                ? null
                : () async {
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: reminderTime,
                    );
                    if (selected != null && mounted) {
                      setState(() => reminderTime = selected);
                    }
                  },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Start on or after: ${dayKey(start)}'),
          subtitle: Text(
            'First scheduled payment: ${dayKey(firstRecurringDate(start, frequency, day, yearlyMonth))}',
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
                    onPressed: busy ? null : () => setState(() => end = null),
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
  );
}
