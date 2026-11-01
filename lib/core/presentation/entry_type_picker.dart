import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'app_sheet.dart';

String entryTypeLabel(EntryType? type) => type == null
    ? 'All types'
    : '${type.name[0].toUpperCase()}${type.name.substring(1)}';
Color entryTypeColor(EntryType type) => switch (type) {
  EntryType.expense => const Color(0xffff4174),
  EntryType.income => const Color(0xff39bbcc),
  EntryType.refund => const Color(0xff3d9e79),
  EntryType.transfer => const Color(0xff6672cf),
};
IconData entryTypeIcon(EntryType? type) => switch (type) {
  EntryType.expense => Icons.shopping_bag_outlined,
  EntryType.income => Icons.trending_up,
  EntryType.refund => Icons.undo,
  EntryType.transfer => Icons.swap_horiz,
  null => Icons.list_alt,
};

Future<Set<EntryType>?> showEntryTypes(
  BuildContext context, {
  required Set<EntryType> selected,
  List<EntryType> types = EntryType.values,
  bool multiple = false,
  bool allowAll = false,
}) => showAppSheet<Set<EntryType>>(
  context,
  builder: (_) => _TypeSheet(
    selected: selected,
    types: types,
    multiple: multiple,
    allowAll: allowAll,
  ),
);

class _TypeSheet extends StatefulWidget {
  const _TypeSheet({
    required this.selected,
    required this.types,
    required this.multiple,
    required this.allowAll,
  });
  final Set<EntryType> selected;
  final List<EntryType> types;
  final bool multiple, allowAll;
  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  late final selected = {...widget.selected};
  @override
  Widget build(BuildContext context) => SelectionSheet(
    title: widget.multiple ? 'Select transaction types' : 'Select type',
    footer: widget.multiple
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, selected),
                child: const Text('Apply types'),
              ),
            ),
          )
        : null,
    child: ListView(
      children: [
        if (widget.allowAll || widget.multiple)
          ListTile(
            key: const ValueKey('entry-type-all'),
            leading: const Icon(Icons.list_alt),
            title: const Text('All types'),
            selected: selected.length == widget.types.length,
            onTap: () {
              if (!widget.multiple) {
                Navigator.pop(context, <EntryType>{});
                return;
              }
              setState(() {
                if (selected.length == widget.types.length) {
                  selected.clear();
                } else {
                  selected.addAll(widget.types);
                }
              });
            },
          ),
        for (final type in widget.types)
          ListTile(
            key: ValueKey('entry-type-${type.name}'),
            leading: CircleAvatar(
              backgroundColor: entryTypeColor(type),
              foregroundColor: Colors.white,
              child: Icon(entryTypeIcon(type)),
            ),
            title: Text(entryTypeLabel(type)),
            selected: selected.contains(type),
            trailing: selected.contains(type)
                ? const Icon(Icons.check_circle)
                : null,
            onTap: () {
              if (!widget.multiple) {
                Navigator.pop(context, {type});
                return;
              }
              setState(() {
                if (!selected.add(type)) selected.remove(type);
              });
            },
          ),
      ],
    ),
  );
}

class EntryTypePicker extends StatelessWidget {
  const EntryTypePicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.types = EntryType.values,
    this.allowAll = false,
    this.label = 'Transaction type',
  });
  final EntryType? value;
  final ValueChanged<EntryType?>? onChanged;
  final List<EntryType> types;
  final bool allowAll;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: ListTile(
      key: const ValueKey('type-picker'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      leading: Icon(
        entryTypeIcon(value),
        color: value == null ? null : entryTypeColor(value!),
      ),
      title: Text(label),
      subtitle: Text(entryTypeLabel(value)),
      trailing: const Icon(Icons.expand_more),
      enabled: onChanged != null,
      onTap: onChanged == null
          ? null
          : () async {
              final result = await showEntryTypes(
                context,
                selected: {?value},
                types: types,
                allowAll: allowAll,
              );
              if (result != null && context.mounted) {
                onChanged!(result.isEmpty ? null : result.single);
              }
            },
    ),
  );
}
