import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'confirmation_dialog.dart';

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
        : widget.currency.format(widget.debt!.amount),
  );
  bool busy = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not save the debt. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.debt == null ? 'Add debt' : 'Edit debt'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Enter what you still owe to a person or bank. Debts reduce account wealth. Update the remaining amount after repayments; record the payment separately in your account.',
                ),
                const SizedBox(height: 20),
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
                  enabled: !busy,
                  decoration: InputDecoration(
                    labelText: 'Outstanding amount (${widget.currency.code})',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (value) {
                    try {
                      widget.currency.parse(value ?? '');
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
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final yes = await confirmAction(
                      context,
                      title: 'Delete debt?',
                      message: 'This removes the outstanding liability and increases net wealth. It does not record a repayment.',
                    );
                    if (yes == true && mounted) await run(widget.onDelete!);
                  },
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () {
                  if (form.currentState!.validate()) {
                    run(
                      () => widget.onSave(
                        Debt(
                          id: widget.debt?.id,
                          name: name.text.trim(),
                          amount: widget.currency.parse(amount.text),
                          currency: widget.currency,
                        ),
                      ),
                    );
                  }
                },
          child: Text(busy ? 'Saving...' : 'Save debt'),
        ),
      ],
    ),
  );
}
