import 'ledger.dart';

enum CategoryKind { expense, income }

enum CategoryIcon {
  general,
  groceries,
  dining,
  transport,
  home,
  health,
  shopping,
  entertainment,
  education,
  insurance,
  subscriptions,
  travel,
  salary,
  freelance,
  investments,
  gifts,
  pets,
  savings,
}

CategoryKind categoryKind(EntryType type) =>
    type == EntryType.income ? CategoryKind.income : CategoryKind.expense;

class LedgerCategory {
  const LedgerCategory({
    required this.id,
    required this.name,
    required this.kind,
    this.icon = CategoryIcon.general,
  });
  final int id;
  final String name;
  final CategoryKind kind;
  final CategoryIcon icon;
  factory LedgerCategory.fromMap(Map<String, Object?> row) => LedgerCategory(
    id: row['id'] as int,
    name: row['name'] as String,
    kind: CategoryKind.values.byName(row['kind'] as String),
    icon:
        CategoryIcon.values
            .where((icon) => icon.name == row['icon'])
            .firstOrNull ??
        CategoryIcon.general,
  );
}
