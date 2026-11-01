import 'package:flutter/material.dart';

import 'helpers/wait_for_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  late int cash, bank;
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
        opening: 0,
        asOf: DateTime(2026),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
      Account(
        name: 'Bank',
        currency: Currency.eur,
        opening: 100000,
        asOf: DateTime(2026),
        includeOnAsOf: true,
      ),
    ]);
    cash = store.accounts.firstWhere((a) => a.name == 'Cash').id!;
    bank = store.accounts.firstWhere((a) => a.name == 'Bank').id!;
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<void> add(String name, EntryType type, int amount, int account) =>
      store.saveEntry(
        LedgerEntry(
          type: type,
          amount: amount,
          currency: Currency.eur,
          date: dateOnly(DateTime.now()),
          description: name,
          category: type == EntryType.income ? 'Salary' : 'Groceries',
          accountId: account,
        ),
      );

  test(
    'bulk delete validates final balances instead of failing midway',
    () async {
      await add('Funding', EntryType.income, 1000, cash);
      await add('Purchase', EntryType.expense, 800, cash);
      final income = store.entries.singleWhere(
        (e) => e.type == EntryType.income,
      );
      await expectLater(store.deleteEntry(income.id!), throwsArgumentError);
      expect(store.entries, hasLength(2));
      await store.deleteEntries(store.entries.map((e) => e.id!).toSet());
      expect(store.entries, isEmpty);
      expect(
        accountBalance(
          store.accounts.firstWhere((a) => a.id == cash),
          store.entries,
          DateTime.now(),
        ),
        0,
      );
    },
  );

  test(
    'bulk category and account changes are atomic and preserve account rules',
    () async {
      await add('First', EntryType.expense, 500, bank);
      await add('Second', EntryType.expense, 600, bank);
      final ids = store.entries.map((e) => e.id!).toSet();
      await store.updateEntries(ids, category: 'Dining out');
      expect(store.entries.every((e) => e.category == 'Dining out'), isTrue);
      await expectLater(
        store.updateEntries(ids, accountId: cash, changeAccount: true),
        throwsArgumentError,
      );
      expect(store.entries.every((e) => e.accountId == bank), isTrue);
      await store.updateEntries(ids, changeAccount: true);
      expect(store.entries.every((e) => e.accountId == null), isTrue);
      await store.updateEntries(ids, accountId: bank, changeAccount: true);
      expect(store.entries.every((e) => e.accountId == bank), isTrue);
    },
  );

  testWidgets(
    'Home tabs filter rows and net refunds; long press enables bulk actions',
    (tester) async {
      await tester.runAsync(() async {
        await add('Bread', EntryType.expense, 1000, bank);
        await add('Milk', EntryType.expense, 500, bank);
        await add('Returned item', EntryType.refund, 200, bank);
        await add('Payday', EntryType.income, 3000, bank);
      });
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('€13'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('€13')).style?.color,
        Colors.red.shade700,
      );
      expect(
        tester.widget<Text>(find.text('€30')).style?.color,
        Colors.green.shade700,
      );
      expect(find.text('Bread'), findsOneWidget);
      expect(find.text('Returned item'), findsOneWidget);
      expect(find.text('Payday'), findsNothing);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Payday'), findsOneWidget);
      expect(find.text('Bread'), findsNothing);
      await tester.drag(find.byType(TabBarView), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(find.text('Bread'), findsOneWidget);
      await tester.ensureVisible(find.text('Bread'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Bread'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Transaction actions'));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Change category'));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Dining out'));
        await waitForStore(
          store,
          () =>
              store.entries
                  .where((entry) => entry.category == 'Dining out')
                  .length ==
              2,
        );
      });
      await tester.pumpAndSettle();
      expect(
        store.entries.where((e) => e.category == 'Dining out'),
        hasLength(2),
      );
      await tester.longPress(find.text('Bread'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all visible'));
      await tester.pumpAndSettle();
      expect(find.text('3 selected'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Transaction actions'));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Delete selected'));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Delete'));
        await waitForStore(store, () => store.entries.length == 1);
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.description, 'Payday');
      expect(tester.takeException(), isNull);
    },
  );
}
