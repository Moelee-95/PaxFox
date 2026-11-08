import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/presentation/account_balance_card.dart';
import 'package:moneva/screens/transaction_form.dart';
import 'package:moneva/screens/overview_screen.dart';
import 'package:moneva/screens/accounts_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

void main() {
  late LedgerStore store;
  final today = dateOnly(DateTime.now());
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Bank',
        currency: Currency.eur,
        opening: 100000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  Future<int> debt({bool receivable = false, int amount = 10000}) async {
    await store.saveDebt(
      Debt(
        name: 'Rent',
        amount: amount,
        currency: Currency.eur,
        isReceivable: receivable,
      ),
    );
    return store.debts.single.id!;
  }

  LedgerEntry payment(int amount, {EntryType type = EntryType.expense}) =>
      LedgerEntry(
        type: type,
        amount: amount,
        currency: Currency.eur,
        date: today,
        description: 'Rent payment',
        category: store.debtCategory(type),
        accountId: store.accounts.single.id,
      );

  test('schema 15 migration preserves existing debts, seeds protected categories and supports settlements after reopen', () async {
    final dir = await Directory.systemTemp.createTemp('paxfox_debt_v15_');
    final path = '${dir.path}/ledger.sqlite';
    final original = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    await original.saveDebt(
      const Debt(name: 'Existing loan', amount: 5000, currency: Currency.eur),
    );
    for (final trigger in await original.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND (name LIKE 'debt_%' OR name LIKE 'protect_debt_%')",
    )) {
      await original.db.execute('DROP TRIGGER "${trigger['name']}"');
    }
    await original.db.execute('DROP TABLE debt_payments');
    await original.db.execute('DROP TABLE recurring_debts');
    await original.db.execute('ALTER TABLE debts DROP COLUMN is_receivable');
    await original.db.delete('categories', where: "lower(name) = 'debt'");
    await original.db.setVersion(15);
    await original.db.close();
    original.dispose();
    final migrated = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await migrated.db.getVersion(), 18);
      expect(migrated.debts.single.name, 'Existing loan');
      expect(migrated.debts.single.amount, 5000);
      expect(migrated.debts.single.isReceivable, isFalse);
      expect(migrated.categories.where((c) => c.isSystemDebt).length, 2);
      expect(await migrated.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await migrated.db.close();
      migrated.dispose();
      await dir.delete(recursive: true);
    }
  });

  test('Debt categories are built in, appearance editable, names and deletion protected', () async {
    for (final type in [EntryType.expense, EntryType.income]) {
      final category = store
          .categoriesFor(type)
          .singleWhere((c) => c.isSystemDebt);
      await store.saveCategory(
        id: category.id,
        kind: category.kind,
        name: category.name,
        icon: CategoryIcon.bank,
        color: 0xff123456,
      );
      expect(
        store.categoriesFor(type).singleWhere((c) => c.isSystemDebt).color,
        0xff123456,
      );
      await expectLater(
        store.saveCategory(
          id: category.id,
          kind: category.kind,
          name: 'Renamed',
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.db.delete(
          'categories',
          where: 'id = ?',
          whereArgs: [category.id],
        ),
        throwsA(isA<DatabaseException>()),
      );
    }
  });

  test('partial repayment changes account and debt atomically, editing and deletion restore differences', () async {
    final id = await debt();
    final wealth = store.netWealth;
    await store.payDebt(id, payment(4000));
    expect(store.debts.single.amount, 6000);
    expect(store.currentBalances.wealth, 96000);
    expect(store.netWealth, wealth);
    final entry = store.entries.single;
    await store.saveEntry(
      LedgerEntry.fromMap({
        ...entry.toMap(),
        'id': entry.id,
        'amount': 2500,
        'account_amount': null,
        'fx_snapshot': null,
      }),
    );
    expect(store.debts.single.amount, 7500);
    await expectLater(
      store.saveEntry(
        LedgerEntry.fromMap({
          ...store.entries.single.toMap(),
          'id': entry.id,
          'amount': 11000,
          'account_amount': null,
          'fx_snapshot': null,
        }),
      ),
      throwsArgumentError,
    );
    expect(store.debts.single.amount, 7500);
    expect(store.entries.single.amount, 2500);
    await store.deleteEntries({entry.id!});
    expect(store.debts.single.amount, 10000);
    expect(store.currentBalances.wealth, 100000);
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('receiving money reduces receivable and records income without double-counting wealth', () async {
    final id = await debt(receivable: true);
    expect(store.totalDebt, 0);
    expect(store.totalReceivable, 10000);
    final wealth = store.netWealth;
    await store.payDebt(id, payment(3000, type: EntryType.income));
    expect(store.debts.single.amount, 7000);
    expect(store.currentBalances.wealth, 103000);
    expect(store.netWealth, wealth);
    await store.deleteEntry(store.entries.single.id!);
    expect(store.debts.single.amount, 10000);
    await expectLater(store.payDebt(id, payment(1000)), throwsArgumentError);
  });

  test(
    'overpayment and insufficient funds roll back the entire settlement',
    () async {
      final id = await debt(amount: 200000);
      await expectLater(
        store.payDebt(id, payment(300000)),
        throwsArgumentError,
      );
      await expectLater(
        store.payDebt(id, payment(150000)),
        throwsArgumentError,
      );
      expect(store.debts.single.amount, 200000);
      expect(store.entries, isEmpty);
      expect(await store.db.query('debt_payments'), isEmpty);
    },
  );

  test('deleting a received settlement cannot create a deficit or partially restore a receivable', () async {
    final id = await debt(receivable: true, amount: 100000);
    await store.payDebt(id, payment(50000, type: EntryType.income));
    final income = store.entries.single;
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 140000,
        currency: Currency.eur,
        date: today,
        description: 'Spending received funds',
        category: store.categoriesFor(EntryType.expense).first.name,
        accountId: store.accounts.single.id,
      ),
    );
    await expectLater(store.deleteEntry(income.id!), throwsArgumentError);
    expect(store.debts.single.amount, 50000);
    expect(store.entries.length, 2);
    expect(store.currentBalances.wealth, 10000);
  });

  test('deleted debt leaves expenses intact and detaches further balance adjustments', () async {
    final id = await debt();
    await store.payDebt(id, payment(2000));
    await store.deleteDebt(id);
    expect(store.entries.length, 1);
    expect(store.debtPaymentLinks, isEmpty);
    await store.deleteEntry(store.entries.single.id!);
    expect(store.debts, isEmpty);
    expect(store.currentBalances.wealth, 100000);
  });

  test(
    'manual expense/income moves to debt/receivable once without posting money',
    () async {
      for (final type in [EntryType.expense, EntryType.income]) {
        await store.saveRecurring(
          RecurringRule(
            type: type,
            description: 'Pending ${type.name}',
            amount: 1200,
            currency: Currency.eur,
            category: store.categoriesFor(type).first.name,
            accountId: store.accounts.single.id!,
            day: today.day,
            nextDate: today,
            automatic: false,
          ),
          today: today,
        );
      }
      await store.processRecurring();
      for (final occurrence in List.of(store.recurringOccurrences)) {
        await store.moveRecurringToDebt(occurrence.id);
        await store.moveRecurringToDebt(occurrence.id);
        await store.retryRecurring(occurrence.id);
      }
      expect(store.debts.length, 2);
      expect(store.totalDebt, 1200);
      expect(store.totalReceivable, 1200);
      expect(store.entries, isEmpty);
      expect(
        store.recurringOccurrences.every((o) => o.status == 'skipped'),
        isTrue,
      );
      expect(store.currentBalances.wealth, 100000);
    },
  );

  test(
    'foreign manual reminder retains native debt and seeds its display rate',
    () async {
      await store.addAccount(
        Account(
          name: 'IQD',
          currency: Currency.iqd,
          baseCurrency: Currency.eur,
          exchangeRate: '1772',
          opening: 0,
          asOf: DateTime(2020),
          includeOnAsOf: true,
        ),
      );
      final account = store.accounts.singleWhere(
        (a) => a.currency == Currency.iqd,
      );
      await store.saveRecurring(
        RecurringRule(
          description: 'IQD rent',
          amount: Currency.iqd.parse('177200'),
          currency: Currency.iqd,
          category: store.categoriesFor(EntryType.expense).first.name,
          accountId: account.id!,
          day: today.day,
          nextDate: today,
          automatic: false,
        ),
        today: today,
      );
      await store.processRecurring();
      await store.moveRecurringToDebt(store.recurringOccurrences.single.id);
      expect(store.debts.single.amount, Currency.iqd.parse('177200'));
      expect(store.debts.single.currency, Currency.iqd);
      expect(store.debtMainAmount(store.debts.single), 10000);
      expect(store.entries, isEmpty);
    },
  );

  testWidgets(
    'settlement editor imports debt and locks the built-in category',
    (tester) async {
      await tester.runAsync(() => debt());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TransactionForm(store: store, debt: store.debts.single),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Rent'), findsOneWidget);
      expect(find.textContaining('Remaining:'), findsOneWidget);
      await tester.ensureVisible(find.text('Bank'));
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.isNotEmpty),
      );
      await tester.pumpAndSettle();
      expect(store.debts.single.amount, 0);
      expect(store.entries.single.category, 'Debt');
    },
  );

  testWidgets(
    'receivables have a separate section and their add action defaults to money owed to the user',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await store.saveDebt(
          const Debt(name: 'My loan', amount: 3000, currency: Currency.eur),
        );
        await store.saveDebt(
          const Debt(
            name: 'Rent owed to me',
            amount: 5000,
            currency: Currency.eur,
            isReceivable: true,
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(store: store, onOpenRecurring: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final receivable = find.text('Money owed to you');
      await tester.scrollUntilVisible(
        receivable,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.getTopLeft(find.text('My loan')).dy,
        lessThan(tester.getTopLeft(receivable).dy),
      );
      expect(find.text('Receive payment'), findsOneWidget);
      await tester.tap(find.byTooltip('Add receivable'));
      await tester.pumpAndSettle();
      expect(find.text('Add receivable'), findsOneWidget);
      expect(find.text('Owed to me'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(MaterialApp(home: AccountsScreen(store: store)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Money owed to you'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Money owed to you'), findsOneWidget);
      expect(find.text('Rent owed to me'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'foreign account card shows app value prominently and native value without rate',
    (tester) async {
      final account = Account(
        name: 'IQD',
        currency: Currency.iqd,
        baseCurrency: Currency.eur,
        exchangeRate: '1772',
        opening: 0,
        asOf: today,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountBalanceCard(
              account: account,
              balance: Currency.iqd.parse('177200'),
              onEdit: () {},
            ),
          ),
        ),
      );
      expect(find.text(Currency.eur.display(10000)), findsOneWidget);
      expect(find.textContaining('177,200'), findsOneWidget);
      expect(find.textContaining('1 EUR'), findsNothing);
      final primary = tester.widget<Text>(
        find.text(Currency.eur.display(10000)),
      );
      final native = tester.widget<Text>(find.textContaining('177,200'));
      expect(primary.style!.fontSize!, greaterThan(native.style!.fontSize!));
    },
  );
}
