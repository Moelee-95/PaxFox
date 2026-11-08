import 'helpers/sheet_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/account_balance_card.dart';
import 'package:moneva/core/presentation/metric_card.dart';
import 'package:moneva/main.dart';
import 'package:moneva/screens/accounts_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 100000,
        asOf: dateOnly(DateTime.now()),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  testWidgets(
    'inline category transactions edit and bulk-select only the displayed category',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        for (final row in [
          ('Bread', 'Groceries'),
          ('Milk', 'Groceries'),
          ('Shoes', 'Shopping'),
        ]) {
          await store.saveEntry(
            LedgerEntry(
              type: EntryType.expense,
              amount: 100,
              currency: Currency.eur,
              date: dateOnly(DateTime.now()),
              description: row.$1,
              category: row.$2,
              accountId: store.accounts.single.id,
            ),
          );
        }
      });
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Monthly overview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byTooltip('Back to categories'), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Shoes'), findsNothing);
      await tester.tap(find.text('Bread'));
      await tester.pumpAndSettle();
      expect(find.text('Save transaction'), findsOneWidget);
      expect(find.text('Currency: EUR'), findsNothing);
      await closeTopPage(tester);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all visible'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Transaction actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete selected'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.description, 'Shoes');
      await tester.tap(find.byTooltip('Back to categories'));
      await tester.pumpAndSettle();
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.byTooltip('Cancel selection'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('system Back returns from category spending to categories', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.saveEntry(
        LedgerEntry(
          type: EntryType.expense,
          amount: 100,
          currency: Currency.eur,
          date: dateOnly(DateTime.now()),
          description: 'Bread',
          category: 'Groceries',
          accountId: store.accounts.single.id,
        ),
      ),
    );
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Monthly overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Bread'));
    await tester.pumpAndSettle();

    // Selection closes first, then Back navigates out of the category.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel selection'), findsNothing);
    expect(find.byTooltip('Back to categories'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back to categories'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
    expect(find.text('Tap back again to exit'), findsNothing);

    await tester.tap(find.text('Groceries'));
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to categories'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Bread'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'overview cards grow for long labels, expose account edit and highlight debts',
    (tester) async {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longName =
          'Joint household account with a long descriptive bank name';
      await tester.runAsync(() async {
        await store.addAccount(
          Account(
            name: longName,
            currency: Currency.eur,
            opening: 2000,
            asOf: dateOnly(DateTime.now()),
            includeOnAsOf: true,
          ),
        );
        await store.saveDebt(
          const Debt(name: 'Family loan', amount: 500, currency: Currency.eur),
        );
      });
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountBalanceCard), findsNWidgets(2));
      expect(
        tester
            .widgetList<ListView>(find.byType(ListView))
            .every((list) => list.scrollDirection == Axis.vertical),
        isTrue,
      );
      final cash = find.ancestor(
        of: find.byTooltip('Edit Cash'),
        matching: find.byType(AccountBalanceCard),
      );
      final bank = find.ancestor(
        of: find.byTooltip('Edit $longName'),
        matching: find.byType(AccountBalanceCard),
      );
      expect(
        tester.getSize(bank).height,
        greaterThan(tester.getSize(cash).height),
      );
      final metrics = find.byType(MetricCard);
      expect(
        find.descendant(
          of: metrics.first,
          matching: find.text('Account wealth'),
        ),
        findsOneWidget,
      );
      expect(find.text('Family loan'), findsOneWidget);
      final debtCard = find.ancestor(
        of: find.text('Family loan'),
        matching: find.byType(Card),
      );
      expect(
        tester.widget<Card>(debtCard).color,
        const Color(0xffce3541).withValues(alpha: .035),
      );
      await tester.tap(find.byTooltip('Edit $longName'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountForm), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
