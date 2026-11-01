import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/domain/ledger.dart';
import '../core/domain/number_format.dart';
import '../core/presentation/confirmation_dialog.dart';
import '../core/presentation/category_picker.dart';

enum TransactionBulkAction { category, account, delete }

class TransactionBulkEditor {
  const TransactionBulkEditor(this.store);
  final LedgerStore store;

  Future<bool> apply(
    BuildContext context,
    TransactionBulkAction action,
    Set<int> ids, {
    required VoidCallback onSaving,
  }) async {
    final entries = store.entries
        .where((entry) => ids.contains(entry.id))
        .toList();
    if (entries.isEmpty) return false;
    if (action == TransactionBulkAction.delete) {
      final confirmed = await confirmAction(
        context,
        title: 'Delete ${formatInteger(ids.length)} transactions?',
        message:
            'This updates spending reports and any linked account balances.',
      );
      if (!confirmed || !context.mounted) return false;
      onSaving();
      await store.deleteEntries(ids);
      return true;
    }

    if (entries.any((entry) => entry.type == EntryType.transfer)) {
      throw ArgumentError(
        'Edit transfers individually to choose both accounts.',
      );
    }
    if (action == TransactionBulkAction.category) {
      if (entries.map((entry) => categoryKind(entry.type)).toSet().length !=
          1) {
        throw ArgumentError(
          'Select income separately from expenses and refunds to change categories.',
        );
      }
      final category = await showCategoryPicker(
        context,
        store: store,
        type: entries.first.type,
      );
      if (category == null || !context.mounted) return false;
      onSaving();
      await store.updateEntries(ids, category: category.name!);
      return true;
    }

    final spending = entries.any((entry) => entry.type == EntryType.expense);
    final choice = await showDialog<({int? id})>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Change account'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (id: null)),
            child: const Text('Unassigned (payment unknown)'),
          ),
          for (final account in store.accounts.where(
            (account) => !spending || account.available,
          ))
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, (id: account.id)),
              child: Text(account.name),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return false;
    onSaving();
    await store.updateEntries(ids, accountId: choice.id, changeAccount: true);
    return true;
  }
}
