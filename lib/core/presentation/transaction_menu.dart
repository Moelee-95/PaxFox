import 'package:flutter/material.dart';

import '../domain/ledger.dart';

enum TransactionCreation { manual, scan, upload }

typedef TransactionCreationRequest = ({
  EntryType type,
  TransactionCreation action,
});

Future<TransactionCreationRequest?> showTransactionMenu(
  BuildContext context, {
  required Rect anchor,
}) => showGeneralDialog<TransactionCreationRequest>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Cancel adding transaction',
  barrierColor: Colors.white.withValues(alpha: 0.9),
  transitionDuration: const Duration(milliseconds: 180),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => Material(
    type: MaterialType.transparency,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final right = (constraints.maxWidth - anchor.right).clamp(
          16.0,
          constraints.maxWidth - 16,
        );
        final availableHeight =
            (anchor.top - MediaQuery.paddingOf(context).top - 24).clamp(
              0.0,
              constraints.maxHeight,
            );
        return Stack(
          children: [
            Positioned(
              left: 16,
              right: right,
              bottom: constraints.maxHeight - anchor.top + 12,
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 560,
                    maxHeight: availableHeight,
                  ),
                  child: SingleChildScrollView(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final type in [
                          EntryType.expense,
                          EntryType.income,
                        ]) ...[
                          if (type == EntryType.income)
                            const SizedBox(width: 12),
                          Expanded(child: _CreationColumn(type: type)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: anchor,
              child: FloatingActionButton(
                heroTag: null,
                tooltip: 'Cancel adding transaction',
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.close),
              ),
            ),
          ],
        );
      },
    ),
  ),
);

class _CreationColumn extends StatelessWidget {
  const _CreationColumn({required this.type});
  final EntryType type;
  @override
  Widget build(BuildContext context) {
    final income = type == EntryType.income;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                income ? 'Income' : 'Expense',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: income
                      ? Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.shade300
                            : Colors.green.shade700
                      : Theme.of(context).brightness == Brightness.dark
                      ? Colors.red.shade300
                      : Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final action in TransactionCreation.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FilledButton.tonal(
                  key: ValueKey('create-${type.name}-${action.name}'),
                  onPressed: () =>
                      Navigator.pop(context, (type: type, action: action)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 60),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(switch (action) {
                        TransactionCreation.manual => Icons.edit_note_outlined,
                        TransactionCreation.scan =>
                          Icons.document_scanner_outlined,
                        TransactionCreation.upload =>
                          Icons.upload_file_outlined,
                      }, size: 22),
                      const SizedBox(height: 6),
                      Text(switch (action) {
                        TransactionCreation.manual => 'Add manually',
                        TransactionCreation.scan =>
                          income ? 'Scan income' : 'Scan invoice',
                        TransactionCreation.upload => 'Upload file',
                      }, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
