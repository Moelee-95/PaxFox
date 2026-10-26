import 'package:flutter/material.dart';

enum TransactionCreation { manual, scan, gallery }

Future<TransactionCreation?> showTransactionMenu(
  BuildContext context, {
  required Rect anchor,
}) => showGeneralDialog<TransactionCreation>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Cancel adding transaction',
  barrierColor: Colors.white.withValues(alpha: 0.9),
  transitionDuration: const Duration(milliseconds: 180),
  transitionBuilder: (context, animation, secondary, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, animation, secondary) => Material(
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
                  constraints: BoxConstraints(maxHeight: availableHeight),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      spacing: 12,
                      children: [
                        for (final option in const [
                          (
                            action: TransactionCreation.manual,
                            label: 'Add manually',
                            icon: Icons.edit_note_outlined,
                          ),
                          (
                            action: TransactionCreation.scan,
                            label: 'Scan invoice',
                            icon: Icons.document_scanner_outlined,
                          ),
                          (
                            action: TransactionCreation.gallery,
                            label: 'From gallery',
                            icon: Icons.photo_library_outlined,
                          ),
                        ])
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                Navigator.pop(context, option.action),
                            icon: Icon(option.icon, size: 24),
                            label: Text(option.label),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: const StadiumBorder(),
                              textStyle: Theme.of(context)
                                  .textTheme
                                  .titleMedium,
                            ),
                          ),
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
