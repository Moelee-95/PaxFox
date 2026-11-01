import 'package:flutter/material.dart';

import '../data/ledger_store.dart';
import '../domain/category.dart';
import '../domain/ledger.dart';
import '../../screens/category_form.dart';
import '../../screens/categories_screen.dart';
import 'app_sheet.dart';
import 'category_colors.dart';
import 'category_icons.dart';
import 'entry_type_picker.dart';

typedef CategorySelection = ({EntryType type, String? name});
Future<CategorySelection?> showCategoryPicker(
  BuildContext context, {
  required LedgerStore store,
  required EntryType type,
  String? selected,
  List<EntryType>? types,
}) async {
  final original = store.categoryFor(selected ?? '', type);
  final result = await showAppSheet<CategorySelection>(
    context,
    builder: (_) => _CategorySheet(
      store: store,
      type: type,
      selected: selected,
      types: types ?? [type],
    ),
  );
  // A category rename is already saved independently. Keep an open editor's
  // selection attached to that category's stable ID even if the picker closes.
  if (result == null && original != null) {
    final renamed = store.categories
        .where((c) => c.id == original.id)
        .firstOrNull;
    if (renamed != null && renamed.name != original.name) {
      return (type: type, name: renamed.name);
    }
  }
  return result;
}

class _CategorySheet extends StatefulWidget {
  const _CategorySheet({
    required this.store,
    required this.type,
    required this.selected,
    required this.types,
  });
  final LedgerStore store;
  final EntryType type;
  final String? selected;
  final List<EntryType> types;
  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  late EntryType type =
      widget.type == EntryType.transfer &&
          widget.types.contains(EntryType.expense)
      ? EntryType.expense
      : widget.type;
  Future<void> edit([LedgerCategory? category]) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CategoryForm(
          store: widget.store,
          kind: categoryKind(type),
          category: category,
          lockKind: widget.types.map(categoryKind).toSet().length == 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final categories = widget.store.categoriesFor(type);
      final colors = Theme.of(context).colorScheme;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      return SelectionSheet(
        title: 'Select Category',
        toolbar: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Row(
                children: [
                  for (final option in widget.types.where(
                    (t) => t == EntryType.expense || t == EntryType.income,
                  ))
                    Expanded(
                      child: TextButton(
                        key: ValueKey('category-type-${option.name}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          foregroundColor: type == option
                              ? Colors.white
                              : colors.onSurface,
                          backgroundColor: type == option
                              ? entryTypeColor(option)
                              : Colors.transparent,
                        ),
                        onPressed: () => setState(() => type = option),
                        child: Text(entryTypeLabel(option)),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final option in widget.types.where(
                  (t) => t == EntryType.refund || t == EntryType.transfer,
                ))
                  IconButton.filledTonal(
                    tooltip: entryTypeLabel(option),
                    isSelected: type == option,
                    icon: Icon(entryTypeIcon(option)),
                    onPressed: () {
                      if (option == EntryType.transfer) {
                        Navigator.pop(context, (type: option, name: null));
                      } else {
                        setState(() => type = option);
                      }
                    },
                  ),
                IconButton.filledTonal(
                  tooltip: 'Edit categories',
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CategoriesScreen(
                        store: widget.store,
                        initialKind: categoryKind(type),
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xff7c4dff),
                    foregroundColor: Colors.white,
                  ),
                  tooltip: 'Add category',
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        child: categories.isEmpty
            ? const Center(child: Text('No categories. Tap + to add one.'))
            : LayoutBuilder(
                builder: (context, constraints) => GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: scale > 1.4
                        ? 2
                        : constraints.maxWidth >= 360
                        ? 4
                        : 3,
                    mainAxisExtent: 76 + 40 * scale,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final color = Color(
                      category.color ?? defaultCategoryColor(category.kind),
                    );
                    final selected =
                        category.name == widget.selected && type == widget.type;
                    return Semantics(
                      selected: selected,
                      button: true,
                      child: InkWell(
                        key: ValueKey('pick-category-${category.id}'),
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, (
                          type: type,
                          name: category.name,
                        )),
                        child: Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                CircleAvatar(
                                  radius: 27,
                                  backgroundColor: color,
                                  foregroundColor: categoryForeground(color),
                                  child: categoryGlyph(
                                    categoryIconData(category.icon),
                                    size: 26,
                                  ),
                                ),
                                if (selected)
                                  Positioned(
                                    right: -4,
                                    bottom: -2,
                                    child: Icon(
                                      Icons.check_circle,
                                      color: colors.primary,
                                      size: 22,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              category.name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      );
    },
  );
}

class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.store,
    required this.type,
    required this.value,
    required this.onChanged,
    this.types,
    this.label = 'Category',
    this.header = false,
    this.enabled = true,
  });
  final LedgerStore store;
  final EntryType type;
  final String? value;
  final ValueChanged<CategorySelection> onChanged;
  final List<EntryType>? types;
  final String label;
  final bool header, enabled;
  @override
  Widget build(BuildContext context) {
    final category = store.categoryFor(value ?? '', type);
    return FormField<String>(
      key: ValueKey('category-field-$type-$value'),
      initialValue: category?.name,
      validator: (_) => type != EntryType.transfer && category == null
          ? 'Select a category.'
          : null,
      builder: (field) => InkWell(
        key: const ValueKey('category-picker'),
        borderRadius: BorderRadius.circular(16),
        onTap: !enabled
            ? null
            : () async {
                final result = await showCategoryPicker(
                  context,
                  store: store,
                  type: type,
                  selected: value,
                  types: types,
                );
                if (result != null && context.mounted) {
                  field.didChange(result.name);
                  onChanged(result);
                }
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: header ? null : label,
            border: header ? InputBorder.none : null,
            enabledBorder: header ? InputBorder.none : null,
            errorText: field.errorText,
            errorStyle: header ? const TextStyle(color: Colors.white) : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: category?.color == null
                    ? (header
                          ? Colors.white24
                          : Theme.of(context).colorScheme.secondaryContainer)
                    : Color(category!.color!),
                child: categoryGlyph(
                  categoryIconData(category?.icon ?? CategoryIcon.general),
                  color: category?.color != null
                      ? categoryForeground(Color(category!.color!))
                      : header
                      ? Colors.white
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type == EntryType.transfer
                          ? 'Transfer'
                          : category?.name ?? 'Select category',
                      maxLines: header ? 1 : null,
                      overflow: header ? TextOverflow.ellipsis : null,
                      style: TextStyle(
                        color: header ? Colors.white : null,
                        fontSize:
                            header &&
                                MediaQuery.viewInsetsOf(context).bottom == 0
                            ? 20
                            : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (header && MediaQuery.viewInsetsOf(context).bottom == 0)
                      Text(
                        entryTypeLabel(type),
                        style: const TextStyle(color: Colors.white70),
                      ),
                  ],
                ),
              ),
              Icon(Icons.expand_more, color: header ? Colors.white : null),
            ],
          ),
        ),
      ),
    );
  }
}
