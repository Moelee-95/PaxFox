import 'package:flutter/material.dart';

import '../data/ledger_store.dart';
import 'async_action.dart';

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({super.key, required this.store});
  final LedgerStore store;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.store.profileName);
  late final _email = TextEditingController(text: widget.store.profileEmail);
  late final _action = AsyncAction()..addListener(() => setState(() {}));

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final saved = await _action.run(
      () => widget.store.saveProfile(name: _name.text, email: _email.text),
      failureMessage: 'Could not save your profile. Please retry.',
    );
    if (saved && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_action.busy,
    child: AlertDialog(
      title: const Text('Edit profile'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Your profile is saved only on this device.'),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                enabled: !_action.busy,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                enabled: !_action.busy,
                maxLength: 254,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                ),
                validator: (value) {
                  final email = value?.trim() ?? '';
                  return email.isNotEmpty &&
                          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                      ? 'Enter a valid email address.'
                      : null;
                },
                onFieldSubmitted: (_) {
                  if (!_action.busy) _save();
                },
              ),
              if (_action.error != null)
                Text(
                  _action.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _action.busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _action.busy ? null : _save,
          child: Text(_action.busy ? 'Saving...' : 'Save profile'),
        ),
      ],
    ),
  );
}
