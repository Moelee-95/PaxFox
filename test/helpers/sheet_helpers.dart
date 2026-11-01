import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> openCategoryPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('category-picker')).last);
  await tester.pumpAndSettle();
}

Future<void> chooseCategory(WidgetTester tester, String name) async {
  final grid = find.byType(GridView).last;
  final target = find.descendant(of: grid, matching: find.text(name));
  final scroll = find.descendant(of: grid, matching: find.byType(Scrollable));
  await tester.scrollUntilVisible(target, 100, scrollable: scroll);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> chooseEntryType(WidgetTester tester, String type) async {
  final picker = find.byKey(const ValueKey('type-picker'));
  if (picker.evaluate().isNotEmpty) {
    await tester.ensureVisible(picker.last);
    await tester.tap(picker.last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('entry-type-$type')));
  } else {
    await openCategoryPicker(tester);
    if (type == 'transfer' || type == 'refund') {
      await tester.tap(
        find.byTooltip(type == 'transfer' ? 'Transfer' : 'Refund').last,
      );
    } else {
      await tester.tap(find.byKey(ValueKey('category-type-$type')));
    }
    if (type != 'transfer') {
      final first = find
          .descendant(
            of: find.byType(GridView).last,
            matching: find.byType(InkWell),
          )
          .first;
      await tester.tap(first);
    }
  }
  await tester.pumpAndSettle();
}

Future<void> closeTopPage(WidgetTester tester) async {
  final close = find.byTooltip('Close editor');
  if (close.evaluate().isNotEmpty) {
    await tester.tap(close.last);
  } else {
    await tester.pageBack();
  }
}
