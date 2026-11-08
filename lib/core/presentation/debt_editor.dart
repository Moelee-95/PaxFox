import 'package:flutter/material.dart';

import '../data/recurring_notifications.dart';

import 'busy_label.dart';

import '../domain/ledger.dart';
import 'async_action.dart';
import 'confirmation_dialog.dart';
import 'grouped_amount_formatter.dart';
import 'info_button.dart';

class DebtEditor extends StatefulWidget {
  const DebtEditor({
    super.key,
    required this.currency,
    required this.onSave,
    this.debt,
    this.onDelete,
    this.initialIsReceivable = false,
    this.lockIdentity = false,
  });
  final bool initialIsReceivable, lockIdentity;
  final Currency currency;
  final Debt? debt;
  final Future<void> Function(Debt) onSave;
  final Future<void> Function()? onDelete;

  @override
  State<DebtEditor> createState() => _DebtEditorState();
}

class _DebtEditorState extends State<DebtEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.debt?.name ?? '');
  late Currency selectedCurrency = widget.debt?.currency ?? widget.currency;
  late final amount = TextEditingController(
    text: widget.debt == null
        ? ''
        : selectedCurrency.formatGrouped(widget.debt!.amount),
  );
  late final action = AsyncAction()..addListener(() => setState(() {}));
  late bool isReceivable =
      widget.debt?.isReceivable ?? widget.initialIsReceivable;
  late DateTime? deadline = widget.debt?.deadline;
  late bool deadlineEnabled = deadline != null;
  bool get busy => action.busy;
  String? get error => action.error;

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    action.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() operation) async {
    final saved = await action.run(
      operation,
      failureMessage: 'Could not save the debt. Please retry.',
    );
    if (saved && mounted) Navigator.pop(context);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    await run(() async {
      if (deadlineEnabled && deadline != widget.debt?.deadline) {
        final reminders = RecurringNotifications.instance;
        if (reminders != null && reminders.store.notificationsEnabled) {
          try {
            await reminders.requestPermissions();
          } catch (_) {
            /* Saving remains available when permission is unavailable. */
          }
        }
      }
      await widget.onSave(
        Debt(
          id: widget.debt?.id,
          name: name.text.trim(),
          amount: selectedCurrency.parseInput(amount.text),
          currency: selectedCurrency,
          isReceivable: isReceivable,
          deadline: deadlineEnabled ? deadline : null,
          deadlineAcknowledged:
              deadlineEnabled && deadline == widget.debt?.deadline
              ? widget.debt?.deadlineAcknowledged
              : null,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              isReceivable
                  ? (widget.debt == null ? 'Add receivable' : 'Edit receivable')
                  : (widget.debt == null ? 'Add debt' : 'Edit debt'),
            ),
          ),
          InfoButton(
            title: 'About debts',
            message: 'Enter what you still owe to a person or bank, or choose money owed to you. Use Pay debt or Receive payment in Overview to record a partial or full settlement and update the remaining balance together.',
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<bool>(
                  initialValue: isReceivable,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Debt direction',
                  ),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('I owe')),
                    DropdownMenuItem(value: true, child: Text('Owed to me')),
                  ],
                  onChanged: busy || widget.lockIdentity
                      ? null
                      : (value) => setState(() => isReceivable = value!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Currency>(
                  initialValue: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final c in Currency.values)
                      DropdownMenuItem(value: c, child: Text(c.code)),
                  ],
                  onChanged: busy || widget.lockIdentity
                      ? null
                      : (value) => setState(() {
                          selectedCurrency = value!;
                          amount.clear();
                        }),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Person / debt name',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a lender.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amount,
                  inputFormatters: const [GroupedAmountFormatter()],
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: 'Outstanding amount (${selectedCurrency.code})',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    try {
                      selectedCurrency.parseInput(value ?? '');
                    } on FormatException catch (e) {
                      return e.message;
                    }
                    return null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set a deadline'),
                  value: deadlineEnabled,
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                          deadlineEnabled = value;
                          if (value && deadline == null) {
                            final now = DateTime.now();
                            deadline = DateTime(
                              now.year,
                              now.month,
                              now.day + 1,
                              9,
                            );
                          }
                        }),
                ),
                if (deadlineEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: Text(dayKey(deadline!)),
                    subtitle: Text(
                      TimeOfDay.fromDateTime(deadline!).format(context),
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: busy
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: dateOnly(deadline!),
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2200),
                            );
                            if (d == null || !context.mounted) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(deadline!),
                            );
                            if (time != null && mounted) {
                              setState(
                                () => deadline = DateTime(
                                  d.year,
                                  d.month,
                                  d.day,
                                  time.hour,
                                  time.minute,
                                ),
                              );
                            }
                          },
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      actions: [
        Row(
          children: [
            if (widget.onDelete != null)
              Expanded(
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final yes = await confirmAction(
                            context,
                            title: isReceivable
                                ? 'Delete receivable?'
                                : 'Delete debt?',
                            message: 'This removes the outstanding balance without recording a payment. Existing transactions are kept.',
                          );
                          if (yes == true && mounted) {
                            await run(widget.onDelete!);
                          }
                        },
                  child: const Text('Delete'),
                ),
              ),
            Expanded(
              child: TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : save,
                child: BusyLabel(
                  busy: busy,
                  label: busy ? 'Saving...' : 'Save',
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
