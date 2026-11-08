import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/presentation/debt_editor.dart';
import 'package:moneva/screens/accounts_screen.dart';
import 'package:moneva/screens/recurring_screen.dart';
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
        opening: 10000,
        asOf: dateOnly(DateTime.now()),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
      Account(
        name: 'Bank',
        currency: Currency.eur,
        opening: 10000,
        asOf: dateOnly(DateTime.now()),
        includeOnAsOf: true,
      ),
    ]);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  Account getBank() =>
      store.accounts.singleWhere((a) => a.kind == AccountKind.bank);

  test('unused banks can be deleted but cash, transaction links and archived recurring links are protected', () async {
    final bank = getBank();
    expect(store.canDeleteBankAccount(bank.id!), isTrue);
    final cash = store.accounts.singleWhere((a) => a.kind == AccountKind.cash);
    await expectLater(store.deleteBankAccount(cash.id!), throwsArgumentError);
    // A transfer's destination link also makes the bank ineligible.
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.transfer,
        amount: 100,
        currency: Currency.eur,
        date: dateOnly(DateTime.now()),
        description: 'Transfer',
        category: 'Transfer',
        accountId: cash.id,
        destinationId: bank.id,
      ),
    );
    expect(store.canDeleteBankAccount(bank.id!), isFalse);
    await expectLater(store.deleteBankAccount(bank.id!), throwsArgumentError);
    await store.deleteEntry(store.entries.single.id!);
    final today = dateOnly(DateTime.now());
    await store.saveRecurring(
      RecurringRule(
        description: 'Future rent',
        amount: 100,
        category: 'Other',
        accountId: bank.id!,
        day: today.day,
        nextDate: DateTime(today.year + 1, today.month, today.day),
      ),
    );
    await store.archiveRecurring(store.recurringRules.single.id!);
    expect(store.canDeleteBankAccount(bank.id!), isFalse);
    await expectLater(store.deleteBankAccount(bank.id!), throwsArgumentError);
    await store.addAccount(
      Account(
        name: 'Unused',
        currency: Currency.eur,
        opening: 500,
        asOf: today,
      ),
    );
    final id = store.accounts.singleWhere((a) => a.name == 'Unused').id!;
    final before = store.netWealth;
    await store.deleteBankAccount(id);
    expect(store.accounts.any((a) => a.id == id), isFalse);
    expect(store.netWealth, before - 500);
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  testWidgets(
    'compact recurring fields share rows and save stays above the system inset',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.pumpWidget(MaterialApp(home: RecurringForm(store: store)));
      await tester.pumpAndSettle();
      final amount = find.widgetWithText(TextFormField, 'Amount (€)');
      final category = find.byKey(const ValueKey('category-picker'));
      expect(
        tester.getTopLeft(category).dy,
        lessThan(tester.getTopLeft(amount).dy),
      );
      final day = find.widgetWithText(
        DropdownButtonFormField<int>,
        'Day of month',
      );
      final interval = find.widgetWithText(TextFormField, 'Every N months');
      expect(tester.getTopLeft(day).dy, tester.getTopLeft(interval).dy);
      final end = find.widgetWithText(ListTile, 'End date: none');
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      final flag = find.widgetWithText(SwitchListTile, 'Liability');
      expect(tester.getTopLeft(end).dy, tester.getTopLeft(flag).dy);
      expect(
        tester.getBottomRight(find.text('Save recurring payment')).dy,
        lessThan(852),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'debt actions stay in one row and outside tap discards an unsaved change',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => store.saveDebt(
          const Debt(name: 'Loan', amount: 1000, currency: Currency.eur),
        ),
      );
      await tester.pumpWidget(MaterialApp(home: AccountsScreen(store: store)));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Bank accounts & cash'), findsOneWidget);
      await tester.ensureVisible(find.text('Loan'));
      await tester.tap(find.text('Loan'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Person / debt name'),
        'Unsaved',
      );
      expect(
        tester.getCenter(find.text('Delete')).dy,
        tester.getCenter(find.text('Cancel')).dy,
      );
      expect(
        tester.getCenter(find.text('Cancel')).dy,
        tester.getCenter(find.text('Save')).dy,
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(DebtEditor), findsNothing);
      expect(store.debts.single.name, 'Loan');
      await tester.ensureVisible(find.byTooltip('Cannot go below zero').first);
      await tester.tap(find.byTooltip('Cannot go below zero').first);
      await tester.pumpAndSettle();
      expect(find.text('Cannot go below zero'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unused bank editor offers confirmed deletion', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AccountsScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete bank account'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    for (
      var i = 0;
      i < 20 && store.accounts.any((a) => a.kind == AccountKind.bank);
      i++
    ) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
    }
    await tester.pumpAndSettle();
    expect(store.accounts.where((a) => a.kind == AccountKind.bank), isEmpty);
    expect(find.byType(AccountForm), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'recurring icon actions show orange paused and blue active schedules',
    (tester) async {
      final today = dateOnly(DateTime.now());
      await tester.runAsync(
        () => store.saveRecurring(
          RecurringRule(
            description: 'Rent',
            amount: 100,
            category: 'Other',
            accountId: getBank().id!,
            day: today.day,
            nextDate: DateTime(today.year + 1, today.month, today.day),
          ),
        ),
      );
      await tester.pumpWidget(MaterialApp(home: RecurringScreen(store: store)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('Next:')).style!.color,
        Colors.blue,
      );
      expect(find.text('Pause'), findsNothing);
      expect(find.byTooltip('Delete recurring rule'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Pause'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.textContaining('Paused; scheduled:'))
            .style!
            .color,
        Colors.orange,
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Resume'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('Next:')).style!.color,
        Colors.blue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
