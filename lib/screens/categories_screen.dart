import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/ledger_refresh.dart';
import '../core/presentation/info_button.dart';
import '../core/presentation/category_icon_picker.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.store});
  final LedgerStore store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: const [
          InfoButton(
            title: 'About categories',
            message: 'Choose from these categories when adding transactions. Renaming a category also updates its existing transactions. Refunds use expense categories.',
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Expenses'),
            Tab(text: 'Income'),
          ],
        ),
      ),
      body: LedgerRefresh(
        store: store,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) => TabBarView(
            children: [
              for (final kind in CategoryKind.values)
                Builder(
                  builder: (context) {
                    final categories = store.categories
                        .where((c) => c.kind == kind)
                        .toList();
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: categories.length + 1,
                      itemBuilder: (context, index) {
                        if (index == categories.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: FilledButton.icon(
                              onPressed: () => _edit(context, kind),
                              icon: const Icon(Icons.add),
                              label: Text(
                                kind == CategoryKind.expense
                                    ? 'Add expense category'
                                    : 'Add income category',
                              ),
                            ),
                          );
                        }
                        final category = categories[index];
                        return ListTile(
                          leading: Icon(categoryIconData(category.icon)),
                          title: Text(category.name),
                          trailing: IconButton(
                            tooltip: 'Edit ${category.name}',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, kind, category),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    ),
  );

  void _edit(
    BuildContext context,
    CategoryKind kind, [
    LedgerCategory? category,
  ]) => showDialog<void>(
    context: context,
    builder: (_) =>
        _CategoryDialog(store: store, kind: kind, category: category),
  );
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({
    required this.store,
    required this.kind,
    this.category,
  });
  final LedgerStore store;
  final CategoryKind kind;
  final LedgerCategory? category;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late CategoryIcon icon = widget.category?.icon ?? CategoryIcon.general;
  late final TextEditingController name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.store.saveCategory(
        id: widget.category?.id,
        kind: widget.kind,
        name: name.text,
        icon: icon,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e.message as String;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not save category. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.category == null ? 'Add category' : 'Edit category',
            ),
          ),
          InfoButton(
            title: 'Category information',
            message:
                '${widget.kind == CategoryKind.expense ? 'Expense category' : 'Income category'}. Saving updates this category on existing transactions too.',
          ),
        ],
      ),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                enabled: !saving,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Category name'),
                validator: (s) => s == null || s.trim().isEmpty
                    ? 'Enter a category name.'
                    : null,
                onFieldSubmitted: (_) {
                  if (!saving) {
                    save();
                  }
                },
              ),
              const SizedBox(height: 12),
              CategoryIconPicker(
                value: icon,
                enabled: !saving,
                onChanged: (value) => setState(() => icon = value),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving...' : 'Save category'),
        ),
      ],
    ),
  );
}
