import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
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
  bool saving = false;
  String? error;
  @override
  void dispose() {
    timeout.dispose();
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
                    setState(() {
                      saving = true;
                      error = null;
                    });
                    try {
                      await widget.store.saveInvoiceTimeout(
                        int.parse(timeout.text.trim()),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = 'Could not save settings. Please retry.';
                        });
                      }
                    }
                  },
            child: Text(saving ? 'Saving...' : 'Save settings'),
          ),
        ],
      ),
    ),
  );
}
