import 'package:flutter/material.dart';

import '../domain/category.dart';
import 'category_icon_catalog.dart';
import 'category_icons.dart';

class CategoryIconPicker extends StatelessWidget {
  const CategoryIconPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final CategoryIcon value;
  final ValueChanged<CategoryIcon> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey(value),
    initialValue: categoryIconLabel(value),
    readOnly: true,
    enabled: enabled,
    decoration: InputDecoration(
      labelText: 'Category icon',
      prefixIcon: Icon(categoryIconData(value)),
      suffixIcon: const Icon(Icons.expand_more),
    ),
    onTap: () async {
      final selected = await showModalBottomSheet<CategoryIcon>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => _IconSheet(selected: value),
      );
      if (selected != null && context.mounted) onChanged(selected);
    },
  );
}

class _IconSheet extends StatefulWidget {
  const _IconSheet({required this.selected});
  final CategoryIcon selected;
  @override
  State<_IconSheet> createState() => _IconSheetState();
}

class _IconSheetState extends State<_IconSheet> {
  String query = '';
  String group = 'All';
  final scroll = ScrollController();
  static final groups = [
    'All',
    ...CategoryIcon.values.map(categoryIconGroup).toSet(),
  ];
  void filter(VoidCallback update) {
    setState(update);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icons = CategoryIcon.values
        .where(
          (icon) =>
              (group == 'All' || categoryIconGroup(icon) == group) &&
              '${categoryIconLabel(icon)} ${categoryIconGroup(icon)} ${icon.name}'
                  .toLowerCase()
                  .contains(query.toLowerCase().trim()),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Choose an icon',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close icon picker',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search icons',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => filter(() => query = value),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final item in groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(item),
                        selected: group == item,
                        onSelected: (_) => filter(() => group = item),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (icons.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No matching icons.'),
              ),
            Expanded(
              child: GridView.builder(
                controller: scroll,
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 110,
                  mainAxisExtent:
                      90 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.8),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: icons.length,
                itemBuilder: (context, index) {
                  final icon = icons[index];
                  final selected = icon == widget.selected;
                  return Semantics(
                    selected: selected,
                    button: true,
                    child: Material(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('pick-icon-${icon.name}'),
                        onTap: () => Navigator.pop(context, icon),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(categoryIconData(icon), size: 28),
                              const SizedBox(height: 6),
                              Text(
                                categoryIconLabel(icon),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
