import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/presentation/busy_label.dart';

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
  late final sourceUrl = TextEditingController(
    text: widget.store.geminiConfigUrl,
  );
  late final manualKey = TextEditingController(
    text: widget.store.geminiManualKey,
  );
  late bool useManualKey = widget.store.geminiUseManualKey;
  bool showKey = false;
  late final action = AsyncAction()..addListener(() => setState(() {}));
  bool get saving => action.busy;
  String? get error => action.error;
  @override
  void dispose() {
    timeout.dispose();
    sourceUrl.dispose();
    manualKey.dispose();
    action.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Invoice scanning',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),

              InfoButton(
                title: 'Invoice scanning settings',
                message: '30–900 seconds (up to 15 minutes). Default: 180. Long invoices may need more time. This limit covers image preparation, connection and Gemini extraction. Changes apply to the next extraction. Cancel and Back remain available. Gemini does not report a completion percentage for this request. The scanner shows the current stage and elapsed time instead. A timeout is still needed if the connection stalls.',
              ),
            ],
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
          const SizedBox(height: 20),
          DropdownButtonFormField<bool>(
            initialValue: useManualKey,
            decoration: const InputDecoration(labelText: 'Gemini key source'),
            items: const [
              DropdownMenuItem(
                value: false,
                child: Text('Online encrypted JSON'),
              ),
              DropdownMenuItem(value: true, child: Text('Manual API key')),
            ],
            onChanged: saving
                ? null
                : (value) => setState(() => useManualKey = value!),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: sourceUrl,
            enabled: !saving && !useManualKey,
            decoration: const InputDecoration(
              labelText: 'Encrypted JSON source URL',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            validator: (value) => LedgerStore.validGeminiConfigUrl(value ?? '')
                ? null
                : 'Enter a valid HTTPS URL.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: manualKey,
            enabled: !saving && useManualKey,
            obscureText: !showKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Manual Gemini API key',
              suffixIcon: IconButton(
                tooltip: showKey ? 'Hide API key' : 'Show API key',
                onPressed: saving
                    ? null
                    : () => setState(() => showKey = !showKey),
                icon: Icon(showKey ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            validator: (value) =>
                !useManualKey || LedgerStore.validGeminiKey(value ?? '')
                ? null
                : 'Enter a valid Gemini API key.',
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Saved locally on this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const InfoButton(
                title: 'Get a Gemini API key',
                message:
                    'Sign in to Google AI Studio and create an API key. '
                    'Copy it, select Manual API key here, paste it into the '
                    'key field, then save settings.',
                details: _GeminiKeyHelpLinks(),
              ),
            ],
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
                      () => widget.store.saveInvoiceSettings(
                        seconds: int.parse(timeout.text.trim()),
                        configUrl: sourceUrl.text,
                        useManualKey: useManualKey,
                        manualKey: manualKey.text,
                      ),
                      failureMessage: 'Could not save settings. Please retry.',
                    );
                    if (saved && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
            child: BusyLabel(
              busy: saving,
              label: saving ? 'Saving...' : 'Save settings',
            ),
          ),
        ],
      ),
    ),
  );
}

class _GeminiKeyHelpLinks extends StatefulWidget {
  const _GeminiKeyHelpLinks();

  @override
  State<_GeminiKeyHelpLinks> createState() => _GeminiKeyHelpLinksState();
}

class _GeminiKeyHelpLinksState extends State<_GeminiKeyHelpLinks> {
  static final uri = Uri.parse('https://aistudio.google.com/apikey');
  bool opening = false;
  bool failed = false;

  Future<void> open() async {
    setState(() {
      opening = true;
      failed = false;
    });
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Keep the selectable address available if the device cannot open it.
    }
    if (!mounted) return;
    setState(() {
      opening = false;
      failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      SelectableText(uri.toString()),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: opening ? null : open,
        icon: const Icon(Icons.open_in_new),
        label: Text(opening ? 'Opening...' : 'Open Google AI Studio'),
      ),
      if (failed)
        Text(
          'Could not open the browser. Copy the link above into your browser.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
    ],
  );
}
