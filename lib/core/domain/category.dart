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
  wallet,
  bank,
  cash,
  creditCard,
  receipt,
  tax,
  loan,
  refund,
  transfer,
  budget,
  coins,
  business,
  coffee,
  bakery,
  fastFood,
  pizza,
  bar,
  iceCream,
  fruit,
  breakfast,
  clothing,
  electronics,
  phone,
  computer,
  furniture,
  beauty,
  jewelry,
  store,
  car,
  fuel,
  train,
  bike,
  taxi,
  parking,
  boat,
  scooter,
  rent,
  electricity,
  water,
  heating,
  internet,
  phoneBill,
  repairs,
  cleaning,
  garden,
  laundry,
  medical,
  pharmacy,
  dentist,
  fitness,
  spa,
  vision,
  hospital,
  wellbeing,
  music,
  gaming,
  books,
  sports,
  camera,
  art,
  concert,
  hotel,
  beach,
  camping,
  family,
  childcare,
  charity,
  celebration,
  wedding,
  security,
  mail,
  time,
  workTools,
  language,
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
