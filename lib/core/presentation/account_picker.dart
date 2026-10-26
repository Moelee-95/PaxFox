import 'package:flutter/material.dart';

import '../domain/ledger.dart';

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
    final colors = theme.colorScheme;
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
          errorText: field.errorText,
        ),
        child: options.isEmpty
            ? const Text('No eligible accounts. Add an account to continue.')
            : SizedBox(
                height:
                    56 *
                    MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.6),
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final account = options[index];
                    final isSelected = selected == account?.id;
                    final name = account?.name ?? 'Unassigned';
                    return Semantics(
                      key: ValueKey(
                        'account-card-${account?.id ?? 'unassigned'}',
                      ),
                      button: true,
                      selected: isSelected,
                      enabled: widget.enabled,
                      child: Material(
                        color: isSelected
                            ? colors.primaryContainer
                            : colors.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? colors.primary
                                : colors.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: widget.enabled
                              ? () {
                                  field.didChange(account?.id);
                                  widget.onChanged(account?.id);
                                }
                              : null,
                          child: SizedBox(
                            width: 164,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    account == null
                                        ? Icons.help_outline
                                        : account.kind == AccountKind.cash
                                        ? Icons.payments_outlined
                                        : Icons.account_balance_outlined,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Tooltip(
                                          message: name,
                                          child: Text(
                                            name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelLarge,
                                          ),
                                        ),
                                        if (account != null)
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              account.currency.format(
                                                widget.balances[account.id] ??
                                                    account.opening,
                                              ),
                                              style: theme.textTheme.bodySmall,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (isSelected)
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 18,
                                    )
                                  else
                                    const SizedBox(width: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
