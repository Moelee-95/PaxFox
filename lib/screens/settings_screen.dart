import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/info_button.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final form = GlobalKey<FormState>();
  late final TextEditingController timeout = TextEditingController(
    text: '${widget.store.invoiceTimeoutSeconds}',
  );
  late final action = AsyncAction()..addListener(() => setState(() {}));
  bool get saving => action.busy;
  String? get error => action.error;
  @override
  void dispose() {
    timeout.dispose();
    action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Settings'),
      actions: const [
        InfoButton(
          title: 'Invoice scanning settings',
          message: '30–900 seconds (up to 15 minutes). Default: 180. Long invoices may need more time. This limit covers image preparation, connection and Gemini extraction. Changes apply to the next extraction. Cancel and Back remain available. Gemini does not report a completion percentage for this request. The scanner shows the current stage and elapsed time instead. A timeout is still needed if the connection stalls.',
        ),
      ],
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'Invoice scanning',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: timeout,
            enabled: !saving,
            decoration: const InputDecoration(
              labelText: 'Extraction timeout (seconds)',
            ),
            keyboardType: TextInputType.number,
            validator: (s) {
              final value = int.tryParse(s?.trim() ?? '');
              return value == null || value < 30 || value > 900
                  ? 'Enter a whole number from 30 to 900.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) {
                      return;
                    }
                    final saved = await action.run(
                      () => widget.store.saveInvoiceTimeout(
                        int.parse(timeout.text.trim()),
                      ),
                      failureMessage: 'Could not save settings. Please retry.',
                    );
                    if (saved && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Save settings'),
          ),
        ],
      ),
    ),
  );
}
