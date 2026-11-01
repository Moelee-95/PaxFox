import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import 'category_form.dart';
import '../core/presentation/category_colors.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/info_button.dart';
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
                          leading: CircleAvatar(
                            backgroundColor: Color(
                              category.color ??
                                  defaultCategoryColor(category.kind),
                            ),
                            foregroundColor: categoryForeground(
                              Color(
                                category.color ??
                                    defaultCategoryColor(category.kind),
                              ),
                            ),
                            child: categoryGlyph(
                              categoryIconData(category.icon),
                            ),
                          ),
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
  ]) => Navigator.push<void>(
    context,
    MaterialPageRoute<void>(
      builder: (_) =>
          CategoryForm(store: store, kind: kind, category: category),
    ),
  );
}
