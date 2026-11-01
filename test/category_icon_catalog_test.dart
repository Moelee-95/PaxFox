import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/presentation/category_icons.dart';

void main() {
  test('curated icons have stable unique IDs and legacy IDs still decode', () {
    expect(CategoryIcon.values.length, inInclusiveRange(110, 140));
    expect(
      CategoryIcon.values.map((icon) => icon.name).toSet().length,
      CategoryIcon.values.length,
    );
    for (final icon in CategoryIcon.values) {
      final category = LedgerCategory.fromMap({
        'id': 1,
        'name': 'Test',
        'kind': 'expense',
        'icon': icon.name,
      });
      expect(category.icon, icon);
      expect(categoryIconData(icon).fontFamily, isNotEmpty);
    }
    expect(
      LedgerCategory.fromMap({
        'id': 1,
        'name': 'Old',
        'kind': 'expense',
        'icon': 'groceries',
      }).icon,
      CategoryIcon.groceries,
    );
    expect(
      LedgerCategory.fromMap({
        'id': 1,
        'name': 'Unknown',
        'kind': 'expense',
        'icon': 'unknown',
      }).icon,
      CategoryIcon.general,
    );
  });
}
