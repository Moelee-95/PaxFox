import 'package:flutter/material.dart';

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
  });
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
  late final amount = TextEditingController(
    text: widget.debt == null
        ? ''
        : widget.currency.formatGrouped(widget.debt!.amount),
  );
  late final action = AsyncAction()..addListener(() => setState(() {}));
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.debt == null ? 'Add debt' : 'Edit debt')),
          InfoButton(
            title: 'About debts',
            message: 'Enter what you still owe to a person or bank. Debts reduce account wealth. Update the remaining amount after repayments; record the payment separately in your account.',
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
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: 'Lender / debt name',
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
                    labelText: 'Outstanding amount (${widget.currency.code})',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    try {
                      widget.currency.parseInput(value ?? '');
                    } on FormatException catch (e) {
                      return e.message;
                    }
                    return null;
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
                            title: 'Delete debt?',
                            message: 'This removes the outstanding liability and increases net wealth. It does not record a repayment.',
                          );
                          if (yes == true && mounted) {
                            await run(widget.onDelete!);
                          }
                        },
                  child: const FittedBox(child: Text('Delete')),
                ),
              ),
            Expanded(
              child: TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const FittedBox(child: Text('Cancel')),
              ),
            ),
            Expanded(
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        if (form.currentState!.validate()) {
                          run(
                            () => widget.onSave(
                              Debt(
                                id: widget.debt?.id,
                                name: name.text.trim(),
                                amount: widget.currency.parseInput(amount.text),
                                currency: widget.currency,
                              ),
                            ),
                          );
                        }
                      },
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(busy ? 'Saving...' : 'Save debt'),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
