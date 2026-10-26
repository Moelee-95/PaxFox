import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/presentation/category_icon_picker.dart';
import 'package:moneva/core/presentation/category_icons.dart';

void main() {
  test('curated icons have stable unique IDs and legacy IDs still decode', () {
    expect(CategoryIcon.values.length, inInclusiveRange(80, 100));
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
      expect(categoryIconData(icon).fontFamily, 'MaterialIcons');
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

  testWidgets(
    'picker filters, searches, selects and closes without changing on dismissal',
    (tester) async {
      CategoryIcon value = CategoryIcon.general;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => CategoryIconPicker(
                value: value,
                onChanged: (icon) => setState(() => value = icon),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(TextFormField, 'Category icon'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-icon-language')), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Food'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search icons'),
        'coffee',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-icon-coffee')), findsOneWidget);
      expect(find.byKey(const ValueKey('pick-icon-groceries')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('pick-icon-coffee')));
      await tester.pumpAndSettle();
      expect(value, CategoryIcon.coffee);
      expect(find.text('Choose an icon'), findsNothing);
      expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
      await tester.tap(find.widgetWithText(TextFormField, 'Category icon'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search icons'),
        'no-such-icon',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching icons.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close icon picker'));
      await tester.pumpAndSettle();
      expect(value, CategoryIcon.coffee);
      expect(tester.takeException(), isNull);
    },
  );
}
