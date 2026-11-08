import 'package:flutter/material.dart';

import '../core/presentation/busy_label.dart';
import '../core/presentation/entry_type_picker.dart';
import '../core/domain/ledger.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/category.dart';
import '../core/presentation/async_action.dart';
import '../core/presentation/category_colors.dart';
import '../core/presentation/category_icon_catalog.dart';
import '../core/presentation/category_icons.dart';

class CategoryForm extends StatefulWidget {
  const CategoryForm({
    super.key,
    required this.store,
    required this.kind,
    this.category,
    this.lockKind = false,
  });
  final LedgerStore store;
  final CategoryKind kind;
  final LedgerCategory? category;
  final bool lockKind;

  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  static final _iconSearchText = {
    for (final icon in CategoryIcon.values)
      icon: '${categoryIconLabel(icon)} ${categoryIconGroup(icon)} ${icon.name}'
          .toLowerCase(),
  };
  static final _allIconsByGroup = _filterIcons('');

  static Map<String, List<CategoryIcon>> _filterIcons(String query) {
    final groups = <String, List<CategoryIcon>>{};
    for (final icon in CategoryIcon.values) {
      if (_iconSearchText[icon]!.contains(query)) {
        (groups[categoryIconGroup(icon)] ??= []).add(icon);
      }
    }
    return groups;
  }

  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  final _search = TextEditingController();
  late final _action = AsyncAction()..addListener(() => setState(() {}));
  late CategoryKind _kind = widget.category?.kind ?? widget.kind;
  late CategoryIcon _icon =
      widget.category?.icon ??
      (_kind == CategoryKind.income ? CategoryIcon.cash : CategoryIcon.dining);
  late int _color = widget.category?.color ?? defaultCategoryColor(_kind);
  String _query = '';
  Map<String, List<CategoryIcon>> _iconsByGroup = _allIconsByGroup;

  void _searchIcons(String value) {
    final query = value.trim().toLowerCase();
    if (query == _query) return;
    setState(() {
      _query = query;
      _iconsByGroup = query.isEmpty ? _allIconsByGroup : _filterIcons(query);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    _scroll.dispose();
    _action.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    final saved = await _action.run(
      () => widget.store.saveCategory(
        id: widget.category?.id,
        kind: _kind,
        name: _name.text,
        icon: _icon,
        color: _color,
      ),
      failureMessage: 'Could not save category. Please retry.',
    );
    if (saved && mounted) Navigator.pop(context);
  }

  Widget _heading(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _nameAndPreview(BuildContext context, Color color) {
    final preview = CircleAvatar(
      key: const ValueKey('category-preview'),
      radius: 28,
      backgroundColor: color,
      foregroundColor: categoryForeground(color),
      child: categoryGlyph(categoryIconData(_icon), size: 28),
    );
    final field = TextFormField(
      controller: _name,
      enabled: !_action.busy && widget.category?.isSystemDebt != true,
      maxLength: 80,
      textCapitalization: TextCapitalization.words,
      decoration: InputDecoration(
        labelText: 'Category name',
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Enter a category name.'
          : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [preview, const SizedBox(height: 16), field],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 4), child: preview),
            const SizedBox(width: 16),
            Expanded(child: field),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedColor = Color(_color);
    final groups = [
      if (_kind == CategoryKind.income) 'Finance',
      ...categoryIconGroups.where(
        (group) =>
            group != 'Finance' &&
            group != 'Brands and Streaming' &&
            group != 'Misc',
      ),
      if (_kind == CategoryKind.expense) 'Finance',
      'Brands and Streaming',
      'Misc',
    ];
    return PopScope(
      canPop: !_action.busy,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            widget.category == null ? 'Add Category' : 'Edit Category',
          ),
          leading: BackButton(
            onPressed: _action.busy ? () {} : () => Navigator.pop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filled(
                tooltip: 'Save category',
                onPressed: _action.busy ? null : _save,
                icon: const Icon(Icons.check),
              ),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _form,
              child: CustomScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          EntryTypePicker(
                            value: _kind == CategoryKind.expense
                                ? EntryType.expense
                                : EntryType.income,
                            types: const [EntryType.expense, EntryType.income],
                            label: 'Category type',
                            onChanged:
                                _action.busy ||
                                    widget.category != null ||
                                    widget.lockKind
                                ? null
                                : (value) => setState(
                                    () => _kind = categoryKind(value!),
                                  ),
                          ),
                          if (widget.category != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Category type stays fixed to preserve existing transactions.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          _nameAndPreview(context, selectedColor),
                          _heading(Icons.palette_outlined, 'Color Selection'),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final columns = constraints.maxWidth >= 340
                                  ? 7
                                  : 6;
                              final size =
                                  ((constraints.maxWidth - (columns - 1) * 10) /
                                          columns)
                                      .clamp(36.0, 52.0);
                              return Wrap(
                                spacing: 10,
                                runSpacing: 12,
                                children: [
                                  for (final swatch in categoryColors)
                                    Semantics(
                                      selected: _color == swatch.$2,
                                      button: true,
                                      label: '${swatch.$1} category color',
                                      child: Tooltip(
                                        message: swatch.$1,
                                        child: InkResponse(
                                          key: ValueKey(
                                            'category-color-${swatch.$1.toLowerCase()}',
                                          ),
                                          onTap: _action.busy
                                              ? null
                                              : () => setState(
                                                  () => _color = swatch.$2,
                                                ),
                                          child: Container(
                                            width: size,
                                            height: size,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(swatch.$2),
                                              border: Border.all(
                                                color: _color == swatch.$2
                                                    ? colors.onSurface
                                                    : Colors.transparent,
                                                width: 2.5,
                                              ),
                                            ),
                                            child: _color == swatch.$2
                                                ? Icon(
                                                    Icons.check,
                                                    size: 20,
                                                    color: categoryForeground(
                                                      Color(swatch.$2),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          _heading(Icons.grid_view, 'Category Icon'),
                          TextField(
                            controller: _search,
                            enabled: !_action.busy,
                            decoration: InputDecoration(
                              labelText: 'Search icons',
                              hintText: 'Search icons...',
                              prefixIcon: const Icon(Icons.search),
                              filled: true,
                              fillColor: colors.surfaceContainerLowest,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Clear icon search',
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _search.clear();
                                        _searchIcons('');
                                      },
                                    ),
                            ),
                            onChanged: _searchIcons,
                          ),
                          if (_iconsByGroup.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Text('No matching icons.'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  for (final group in groups)
                    if (_iconsByGroup.containsKey(group)) ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            group,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 64,
                                mainAxisExtent: 64,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemCount: _iconsByGroup[group]!.length,
                          itemBuilder: (context, index) {
                            final icon = _iconsByGroup[group]![index];
                            final selected = _icon == icon;
                            return Semantics(
                              selected: selected,
                              button: true,
                              label: categoryIconLabel(icon),
                              child: Tooltip(
                                message: categoryIconLabel(icon),
                                child: Material(
                                  color: selected
                                      ? selectedColor
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  clipBehavior: Clip.antiAlias,
                                  child: InkWell(
                                    key: ValueKey('pick-icon-${icon.name}'),
                                    onTap: _action.busy
                                        ? null
                                        : () => setState(() => _icon = icon),
                                    child: Center(
                                      child: categoryGlyph(
                                        categoryIconData(icon),
                                        size: 26,
                                        color: selected
                                            ? categoryForeground(selectedColor)
                                            : colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: Material(
          color: colors.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_action.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _action.error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                FilledButton(
                  onPressed: _action.busy ? null : _save,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: BusyLabel(
                    busy: _action.busy,
                    label: _action.busy ? 'Saving...' : 'Save category',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
