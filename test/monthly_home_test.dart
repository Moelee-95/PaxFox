import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/ledger_queries.dart';
import 'package:moneva/core/presentation/entry_type_picker.dart';
import 'package:moneva/screens/home_screen.dart';

void main() {
  testWidgets('month changes defer hidden tab rows until they are needed', (
    tester,
  ) async {
    var month = DateTime(2026, 10);
    var tab = 0;
    final ledger = LedgerIndex.prepared([
      for (final m in [10, 11])
        for (final type in [EntryType.expense, EntryType.income])
          for (var i = 0; i < 30; i++)
            LedgerEntry(
              type: type,
              amount: 100,
              currency: Currency.eur,
              date: DateTime(2026, m),
              description: '$m ${type.name} $i',
              category: 'Test',
            ),
    ]);
    var rowsBuilt = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => HomeScreen(
              month: month,
              summary: ledger.forMonth(month),
              tab: tab,
              onTabChanged: (value) => update(() => tab = value),
              onMonthChanged: (value) => update(() => month = value),
              onCategoryChanged: (_) {},
              tileBuilder: (entry) {
                rowsBuilt++;
                return ListTile(title: Text(entry.description));
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Monthly overview'));
    await tester.pumpAndSettle();
    rowsBuilt = 0;
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(
      rowsBuilt,
      0,
      reason: 'Hidden transaction tabs must not lay out new months.',
    );
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('11 expense 0'), findsOneWidget);
    expect(rowsBuilt, greaterThan(0));
    await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(find.text('11 income 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'three visible Home tabs follow the month and support normal tab taps and swipes',
    (tester) async {
      var month = DateTime(2026, 10);
      var tab = 0;
      String? selectedCategory;
      final entries = [
        LedgerEntry(
          type: EntryType.income,
          amount: 10099,
          currency: Currency.eur,
          date: month,
          description: 'Salary',
          category: 'Salary',
        ),
        LedgerEntry(
          type: EntryType.expense,
          amount: 3099,
          currency: Currency.eur,
          date: month,
          description: 'Food',
          category: 'Groceries',
        ),
        LedgerEntry(
          type: EntryType.refund,
          amount: 500,
          currency: Currency.eur,
          date: month,
          description: 'Return',
          category: 'Groceries',
        ),
        LedgerEntry(
          type: EntryType.transfer,
          amount: 1000,
          currency: Currency.eur,
          date: month,
          description: 'Move',
          category: 'Transfer',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => HomeScreen(
                month: month,
                summary: MonthlyLedger(
                  entries.where((e) => e.date.month == month.month),
                ),
                tab: tab,
                selectedCategory: selectedCategory,
                onCategoryChanged: (value) =>
                    setState(() => selectedCategory = value),
                onTabChanged: (value) => setState(() => tab = value),
                onMonthChanged: (value) => setState(() => month = value),
                categoryIcon: (_) => Icons.shopping_basket_outlined,
                tileBuilder: (entry) =>
                    ListTile(title: Text(entry.description)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Monthly overview'), findsOneWidget);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Monthly overview'));
      await tester.pumpAndSettle();
      expect(tab, 2);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Income'), findsOneWidget);
      expect(find.text('Net cashflow: €75.00'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('€25.99'), findsOneWidget);
      expect(find.text('€25'), findsOneWidget);
      expect(find.text('€100'), findsOneWidget);
      expect(
        tester.getCenter(find.text('Expenses')).dy,
        tester.getCenter(find.text('€25')).dy,
      );
      expect(
        tester.getSize(find.byType(Tab).first).width,
        greaterThan(tester.getSize(find.byType(Tab).last).width),
      );
      expect(find.byIcon(Icons.shopping_basket_outlined), findsOneWidget);
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      expect(find.text('Move'), findsNothing);
      await tester.tap(find.byTooltip('Back to categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Net cashflow: €0.00'), findsOneWidget);
      expect(find.text('Groceries'), findsNothing);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(tab, 1);
      expect(find.text('Income'), findsOneWidget);
      // Standard leftward swipes advance; rightward swipes return.
      await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(tab, 2);
      expect(find.text('Net cashflow: €0.00'), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(tab, 1);
      await tester.drag(find.byType(TabBarView), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(tab, 0);
      expect(find.byTooltip('Show monthly overview'), findsNothing);
      expect(find.byTooltip('Back to expenses and income'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transaction type field opens a reusable selection sheet', (tester) async {
    EntryType? value = EntryType.expense;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, update) => EntryTypePicker(value: value,
        onChanged: (type) => update(() => value = type)),
    ))));
    await tester.tap(find.byKey(const ValueKey('type-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('entry-type-transfer')));
    await tester.pumpAndSettle();
    expect(value, EntryType.transfer);
    expect(tester.takeException(), isNull);
  });
}
