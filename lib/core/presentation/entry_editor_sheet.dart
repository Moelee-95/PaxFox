import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'bottom_action_bar.dart';
import 'entry_type_picker.dart';
import 'grouped_amount_formatter.dart';

/// Shared keyboard-aware transaction/recurrence/item editor. Controllers and
/// validation stay with the owning form; typing does not rebuild the sheet.
class EntryEditorSheet extends StatelessWidget {
  const EntryEditorSheet({
    super.key,
    required this.title,
    required this.type,
    required this.currency,
    required this.amount,
    required this.categoryPicker,
    required this.children,
    required this.onSave,
    required this.saveLabel,
    required this.amountValidator,
    this.amountLabel = 'Amount',
    this.busy = false,
    this.actions = const [],
  });
  final String title, saveLabel, amountLabel;
  final EntryType type;
  final Currency currency;
  final TextEditingController amount;
  final Widget categoryPicker;
  final List<Widget> children, actions;
  final VoidCallback onSave;
  final String? Function(String?) amountValidator;
  final bool busy;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        final height = (MediaQuery.sizeOf(context).height * .92 - keyboard)
            .clamp(180.0, constraints.maxHeight);
        final compact = keyboard > 0 || height < 500;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: SizedBox(
              height: height,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Material(
                  color: entryTypeColor(type),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ColoredBox(
                        color: entryTypeColor(type),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          child: Column(
                            children: [
                              if (!compact)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 12,
                                      bottom: 4,
                                    ),
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              Row(
                                key: const ValueKey('editor-category-row'),
                                children: [
                                  Expanded(child: categoryPicker),
                                  for (final action in actions)
                                    IgnorePointer(
                                      ignoring: busy,
                                      child: action,
                                    ),
                                  IconButton(
                                    tooltip: 'Close editor',
                                    onPressed: busy
                                        ? null
                                        : () => Navigator.pop(context),
                                    color: Colors.white,
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                              const Divider(color: Colors.white38, height: 12),
                              Row(
                                key: const ValueKey('editor-amount-row'),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white24,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      currency.symbol.trim(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: amount,
                                      enabled: !busy,
                                      inputFormatters: const [
                                        GroupedAmountFormatter(),
                                      ],
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                            signed: true,
                                          ),
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: compact ? 24 : 36,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: compact ? 4 : 12,
                                        ),
                                        floatingLabelBehavior: compact
                                            ? FloatingLabelBehavior.never
                                            : FloatingLabelBehavior.auto,
                                        labelText: amountLabel,
                                        hintText: '0',
                                        labelStyle: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        hintStyle: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                        errorStyle: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        errorBorder: InputBorder.none,
                                        focusedErrorBorder: InputBorder.none,
                                      ),
                                      validator: amountValidator,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.all(16),
                            children: children,
                          ),
                        ),
                      ),
                      ColoredBox(
                        color: Theme.of(context).colorScheme.surface,
                        child: BottomActionBar(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xff7c4dff),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          label: saveLabel,
                          busy: busy,
                          onPressed: onSave,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
