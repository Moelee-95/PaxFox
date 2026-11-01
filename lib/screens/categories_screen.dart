import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/category_colors.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/info_button.dart';
import '../core/presentation/ledger_refresh.dart';
import 'category_form.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    super.key,
    required this.store,
    this.initialKind = CategoryKind.expense,
  });
  final LedgerStore store;
  final CategoryKind initialKind;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final tabs = TabController(
    length: 2,
    initialIndex: widget.initialKind.index,
    vsync: this,
  );

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  void edit(CategoryKind kind, [LedgerCategory? category]) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            CategoryForm(store: widget.store, kind: kind, category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Categories'),
      centerTitle: true,
      actions: [
        const InfoButton(
          title: 'About categories',
          message: 'Choose from these categories when adding transactions. Renaming a category also updates its existing transactions. Refunds use expense categories.',
        ),
        AnimatedBuilder(
          animation: tabs,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(right: 16),
            child: IconButton.filled(
              tooltip: tabs.index == 0
                  ? 'Add expense category'
                  : 'Add income category',
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xff7c4dff),
                foregroundColor: Colors.white,
              ),
              onPressed: () => edit(CategoryKind.values[tabs.index]),
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ],
    ),
    body: LedgerRefresh(
      store: widget.store,
      child: Column(
        children: [
          AnimatedBuilder(
            animation: tabs,
            builder: (context, _) {
              final color = tabs.index == 0
                  ? const Color(0xffdf373f)
                  : const Color(0xff249b6a);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: TabBar(
                  controller: tabs,
                  dividerHeight: 0,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: color,
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                  indicator: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: color, width: 2),
                  ),
                  tabs: const [
                    Tab(text: 'Expenses', height: 52),
                    Tab(text: 'Income', height: 52),
                  ],
                ),
              );
            },
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.store,
              builder: (context, _) => TabBarView(
                controller: tabs,
                children: [
                  for (final kind in CategoryKind.values)
                    _CategoryList(
                      categories: widget.store.categoriesFor(
                        kind == CategoryKind.expense
                            ? EntryType.expense
                            : EntryType.income,
                      ),
                      kind: kind,
                      onEdit: (category) => edit(kind, category),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.categories,
    required this.kind,
    required this.onEdit,
  });
  final List<LedgerCategory> categories;
  final CategoryKind kind;
  final ValueChanged<LedgerCategory> onEdit;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return const Center(child: Text('No categories. Tap + to add one.'));
    }
    return ListView.separated(
      key: PageStorageKey(kind),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _CategoryCard(
        category: categories[index],
        number: index + 1,
        onTap: () => onEdit(categories[index]),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.number,
    required this.onTap,
  });
  final LedgerCategory category;
  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = Color(category.color ?? defaultCategoryColor(category.kind));
    return Tooltip(
      message: 'Edit ${category.name}',
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: ValueKey('category-card-${category.id}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          minVerticalPadding: 12,
          horizontalTitleGap: 16,
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: color,
            foregroundColor: categoryForeground(color),
            child: categoryGlyph(categoryIconData(category.icon), size: 26),
          ),
          title: Text(
            category.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          subtitle: Text(
            category.kind == CategoryKind.expense
                ? 'Expense Category'
                : 'Income Category',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (MediaQuery.sizeOf(context).width >= 360 ||
                  MediaQuery.textScalerOf(context).scale(14) <= 20)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      '#$number',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
