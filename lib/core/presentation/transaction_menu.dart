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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
              ),
            ),
            Positioned(
              left: 16,
              right: right,
              bottom: constraints.maxHeight - menuAnchor.top + 12,
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 300,
                    maxHeight: availableHeight,
                  ),
                  child: SingleChildScrollView(child: const _CreationMenu()),
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

/// Only one set of entry methods is mounted at a time.
class _CreationMenu extends StatefulWidget {
  const _CreationMenu();
  @override
  State<_CreationMenu> createState() => _CreationMenuState();
}

class _CreationMenuState extends State<_CreationMenu> {
  EntryType? selected;
  Color accent(EntryType type) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (type) {
      EntryType.expense =>
        dark ? const Color(0xffff8790) : const Color(0xffce3541),
      EntryType.income =>
        dark ? const Color(0xff67c596) : const Color(0xff218759),
      _ => dark ? const Color(0xff8ab4f8) : const Color(0xff2867bf),
    };
  }

  String label(EntryType type) => switch (type) {
    EntryType.expense => 'Expense',
    EntryType.income => 'Income',
    _ => 'Transfer',
  };
  void choose(EntryType type) {
    if (type == EntryType.transfer) {
      Navigator.pop(context, (type: type, action: TransactionCreation.manual));
    } else {
      setState(() => selected = type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = Duration(
      milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 170,
    );
    return PopScope(
      canPop: selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && selected != null) setState(() => selected = null);
      },
      child: Material(
        color: theme.colorScheme.surface,
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: AnimatedSize(
          duration: duration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(.035, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: selected == null
                ? Padding(
                    key: const ValueKey('creation-choices'),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                          child: Text(
                            'New transaction',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        for (final type in [
                          EntryType.expense,
                          EntryType.income,
                          EntryType.transfer,
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Material(
                              color: accent(type).withValues(alpha: .055),
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                key: ValueKey('create-type-${type.name}'),
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => choose(type),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(switch (type) {
                                        EntryType.expense =>
                                          Icons.north_east_rounded,
                                        EntryType.income =>
                                          Icons.south_west_rounded,
                                        _ => Icons.swap_horiz_rounded,
                                      }, color: accent(type)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          label(type),
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                color: accent(type),
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                      Icon(
                                        type == EntryType.transfer
                                            ? Icons.arrow_forward_rounded
                                            : Icons.chevron_right_rounded,
                                        size: 20,
                                        color: accent(type),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : Padding(
                    key: ValueKey(selected),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Back to transaction choices',
                              onPressed: () => setState(() => selected = null),
                              icon: const Icon(Icons.arrow_back_rounded),
                            ),
                            Expanded(
                              child: Text(
                                label(selected!),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: accent(selected!),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final action in TransactionCreation.values)
                                SizedBox(
                                  width: (constraints.maxWidth - 8) / 2,
                                  child: TextButton(
                                    key: ValueKey(
                                      'create-${selected!.name}-${action.name}',
                                    ),
                                    onPressed: () => Navigator.pop(context, (
                                      type: selected!,
                                      action: action,
                                    )),
                                    style: TextButton.styleFrom(
                                      foregroundColor: accent(selected!),
                                      backgroundColor: accent(selected!)
                                          .withValues(alpha: .055),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
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
                                        const SizedBox(height: 6),
                                        Text(switch (action) {
                                          TransactionCreation.manual =>
                                            'Manual',
                                          TransactionCreation.scan => 'Scan',
                                          TransactionCreation.gallery =>
                                            'Gallery',
                                          TransactionCreation.upload => 'File',
                                        }, textAlign: TextAlign.center),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
