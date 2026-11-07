import 'package:flutter/material.dart';

import '../domain/ledger.dart';

enum TransactionCreation { manual, scan, gallery, upload }

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
  barrierColor: Colors.black.withValues(alpha: .22),
  transitionDuration: const Duration(milliseconds: 180),
  transitionBuilder: (_, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => Material(
    type: MaterialType.transparency,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        // Keep the captured FAB anchor usable after rotation/window resizing.
        final menuAnchor = Rect.fromLTWH(
          anchor.left.clamp(
            16.0,
            (constraints.maxWidth - anchor.width - 16).clamp(
              16.0,
              double.infinity,
            ),
          ),
          anchor.top.clamp(
            padding.top + 16,
            (constraints.maxHeight - padding.bottom - 96 - anchor.height).clamp(
              padding.top + 16,
              double.infinity,
            ),
          ),
          anchor.width,
          anchor.height,
        );
        final right = (constraints.maxWidth - menuAnchor.right).clamp(
          16.0,
          constraints.maxWidth - 16,
        );
        final availableHeight = (menuAnchor.top - padding.top - 24).clamp(
          0.0,
          constraints.maxHeight,
        );
        return Stack(
          children: [
            Positioned(
              left: 16,
              right: right,
              bottom: constraints.maxHeight - menuAnchor.top + 12,
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 380,
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
              rect: menuAnchor,
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
    final showLabels = MediaQuery.textScalerOf(context).scale(14) <= 18;
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
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final action in TransactionCreation.values)
                    SizedBox(
                      width: (constraints.maxWidth - 4) / 2,
                      child: Tooltip(
                        message:
                            '${income ? 'Income' : 'Expense'}: ${switch (action) {
                              TransactionCreation.manual => 'Add manually',
                              TransactionCreation.scan => 'Scan invoice',
                              TransactionCreation.gallery => 'Select from gallery',
                              TransactionCreation.upload => 'Upload file',
                            }}',
                        child: TextButton(
                          key: ValueKey('create-${type.name}-${action.name}'),
                          onPressed: () => Navigator.pop(context, (
                            type: type,
                            action: action,
                          )),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(switch (action) {
                                TransactionCreation.manual =>
                                  Icons.edit_note_outlined,
                                TransactionCreation.scan =>
                                  Icons.document_scanner_outlined,
                                TransactionCreation.gallery =>
                                  Icons.photo_library_outlined,
                                TransactionCreation.upload =>
                                  Icons.upload_file_outlined,
                              }),
                              if (showLabels) const SizedBox(height: 4),
                              if (showLabels)
                                Text(switch (action) {
                                  TransactionCreation.manual => 'Manual',
                                  TransactionCreation.scan => 'Scan',
                                  TransactionCreation.gallery => 'Gallery',
                                  TransactionCreation.upload => 'File',
                                }, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
