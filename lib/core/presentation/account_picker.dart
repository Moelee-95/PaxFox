import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'selection_cards.dart';

class AccountPicker extends StatefulWidget {
  const AccountPicker({
    super.key,
    required this.accounts,
    required this.selectedId,
    required this.balances,
    required this.onChanged,
    this.label = 'Payment account',
    this.enabled = true,
    this.allowUnassigned = false,
    this.validator,
  });

  final List<Account> accounts;
  final Map<int, int> balances;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  final String label;
  final bool enabled;
  final bool allowUnassigned;
  final FormFieldValidator<int>? validator;

  @override
  State<AccountPicker> createState() => _AccountPickerState();
}

class _AccountPickerState extends State<AccountPicker> {
  final _scrollController = ScrollController(keepScrollOffset: false);

  @override
  void didUpdateWidget(covariant AccountPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedId != widget.selectedId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        widget.accounts.any((account) => account.id == widget.selectedId)
        ? widget.selectedId
        : null;
    final options = <Account?>[
      if (widget.allowUnassigned) null,
      ...widget.accounts,
    ];
    final selectedIndex = options.indexWhere(
      (account) => account?.id == selected,
    );
    if (selectedIndex > 0) options.insert(0, options.removeAt(selectedIndex));
    final theme = Theme.of(context);
    return FormField<int>(
      key: ValueKey((
        widget.label,
        selected,
        widget.accounts.map((account) => account.id).join(','),
      )),
      initialValue: selected,
      validator: widget.validator,
      builder: (field) => InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: field.errorText,
        ),
        child: options.isEmpty
            ? const Text('No eligible accounts. Add an account to continue.')
            : SelectionRow(
                controller: _scrollController,
                count: options.length,
                itemBuilder: (context, index) {
                  final account = options[index];
                  return SelectionCard(
                    key: ValueKey(
                      'account-card-${account?.id ?? 'unassigned'}',
                    ),
                    selected: selected == account?.id,
                    icon: account == null
                        ? Icons.help_outline
                        : account.kind == AccountKind.cash
                        ? Icons.payments_outlined
                        : Icons.account_balance_outlined,
                    title: account?.name ?? 'Unassigned',
                    subtitle: account == null
                        ? null
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              account.currency.format(
                                widget.balances[account.id] ?? account.opening,
                              ),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                    onTap: widget.enabled
                        ? () {
                            field.didChange(account?.id);
                            widget.onChanged(account?.id);
                          }
                        : null,
                  );
                },
              ),
      ),
    );
  }
}
