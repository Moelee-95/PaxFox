import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/ledger_refresh.dart';

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, required this.store});
  final LedgerStore store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
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
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'Choose from these categories when adding transactions. Renaming a category also updates its existing transactions. Refunds use expense categories.',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _edit(context, kind),
                            icon: const Icon(Icons.add),
                            label: Text(
                              kind == CategoryKind.expense
                                  ? 'Add expense category'
                                  : 'Add income category',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: store.categories
                            .where((c) => c.kind == kind)
                            .length,
                        itemBuilder: (context, index) {
                          final category = store.categories
                              .where((c) => c.kind == kind)
                              .elementAt(index);
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
                      ),
                    ),
                  ],
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
      title: Text(widget.category == null ? 'Add category' : 'Edit category'),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.kind == CategoryKind.expense
                    ? 'Expense category'
                    : 'Income category',
              ),
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
              if (widget.category != null)
                const Text(
                  'Saving updates this category on existing transactions too.',
                ),
              DropdownButtonFormField<CategoryIcon>(
                initialValue: icon,
                decoration: const InputDecoration(labelText: 'Category icon'),
                items: CategoryIcon.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Row(
                          children: [
                            Icon(categoryIconData(value)),
                            const SizedBox(width: 12),
                            Text(value.name),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: saving
                    ? null
                    : (value) => setState(() => icon = value!),
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
