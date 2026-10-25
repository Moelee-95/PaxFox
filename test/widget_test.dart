import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/main.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/freedom.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/presentation/category_icons.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, label));
    await tester.pumpAndSettle();
  }

  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<void> prepareAccounts() => store.completeSetup([
    Account(
      name: 'Cash',
      currency: Currency.eur,
      opening: 10000,
      asOf: dateOnly(DateTime.now()),
      kind: AccountKind.cash,
      includeOnAsOf: true,
    ),
    Account(
      name: 'Main bank',
      allowOverdraft: true,
      currency: Currency.eur,
      opening: 0,
      asOf: dateOnly(DateTime.now()),
      kind: AccountKind.bank,
      includeOnAsOf: true,
    ),
  ]);

  testWidgets(
    'saving from Overview returns to Home above the system navigation area',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Save transaction')).dy,
        lessThan(1552),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Return home payment',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '2');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.text('Return home payment'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('horizontal swipes and navigation taps stay synchronized', (
    tester,
  ) async {
    await tester.runAsync(prepareAccounts);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    for (var index = 1; index < 4; index++) {
      await tester.drag(find.byType(PageView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );
    }
    await tester.drag(find.byType(PageView), const Offset(650, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.drag(find.byType(PageView), const Offset(-650, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recurring income form selects income categories and a blocked receiving account',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(prepareAccounts);
      final bank = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.bank,
      );
      await tester.runAsync(
        () => store.updateAccount(
          Account(
            id: bank.id,
            name: bank.name,
            currency: Currency.eur,
            opening: 0,
            asOf: bank.asOf,
            includeOnAsOf: true,
            available: false,
          ),
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await openMenuItem(tester, 'Recurring payments');
      await tester.tap(find.text('Add recurring payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<EntryType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Income').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        'Monthly salary',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (EUR)'),
        '20',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsNothing);
      await tester.tap(find.text('Salary').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.type, EntryType.income);
      expect(store.entries.single.type, EntryType.income);
      expect(store.entries.single.accountId, bank.id);
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.id == bank.id),
          store.entries,
          DateTime.now(),
        ),
        2000,
      );
      await tester.tap(find.text('Pause'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'drawer contains reports and management; transaction icons use category and type colors',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await prepareAccounts();
        final grocery = store.categories.singleWhere(
          (c) => c.name == 'Groceries',
        );
        await store.saveCategory(
          id: grocery.id,
          kind: grocery.kind,
          name: grocery.name,
          icon: CategoryIcon.pets,
        );
        final bank = store.accounts.singleWhere(
          (a) => a.kind == AccountKind.bank,
        );
        final cash = store.accounts.singleWhere(
          (a) => a.kind == AccountKind.cash,
        );
        for (final type in EntryType.values) {
          await store.saveEntry(
            LedgerEntry(
              type: type,
              amount: 100,
              currency: Currency.eur,
              date: dateOnly(DateTime.now()),
              description: 'Icon ${type.name}',
              category: type == EntryType.income
                  ? 'Salary'
                  : type == EntryType.transfer
                  ? 'Transfer'
                  : 'Groceries',
              accountId: bank.id,
              destinationId: type == EntryType.transfer ? cash.id : null,
            ),
          );
        }
      });
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      for (final type in EntryType.values) {
        final tile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Icon ${type.name}'),
        );
        final icon = tile.leading! as Icon;
        expect(icon.color, transactionColor(type));
        expect(
          icon.icon,
          type == EntryType.transfer
              ? Icons.account_balance_outlined
              : categoryIconData(
                  type == EntryType.income
                      ? CategoryIcon.salary
                      : CategoryIcon.pets,
                ),
        );
      }
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Accounts'), findsNothing);
      await openMenuItem(tester, 'Reports');
      expect(find.text('Spending by category'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      await openMenuItem(tester, 'Home');
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
      await openMenuItem(tester, 'Categories');
      await tester.tap(find.byTooltip('Edit Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<CategoryIcon>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('home').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      final changed = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Icon expense'),
      );
      expect(
        (changed.leading! as Icon).icon,
        categoryIconData(CategoryIcon.home),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'startup and repeated app resumes post a due recurring bill only once',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      final today = dateOnly(DateTime.now());
      final bank = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.bank,
      );
      await tester.runAsync(() async {
        await store.saveRecurring(
          RecurringRule(
            description: 'Due rent',
            amount: 1000,
            category: 'Rent & utilities',
            accountId: bank.id!,
            day: today.day,
            nextDate: today,
            active: false,
          ),
        );
        await store.db.update('recurring_rules', {'active': 1});
        await store.refresh();
      });
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1));
      for (var i = 0; i < 2; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
      }
      expect(store.entries, hasLength(1));
      expect(store.recurringOccurrences, hasLength(1));
      expect(store.entries.single.accountId, bank.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'income requires an account, increases blocked wealth, and blocked banks cannot fund expenses',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(prepareAccounts);
      final bank = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.bank,
      );
      await tester.runAsync(
        () => store.updateAccount(
          Account(
            id: bank.id,
            name: bank.name,
            currency: Currency.eur,
            opening: 0,
            asOf: bank.asOf,
            includeOnAsOf: true,
            available: false,
          ),
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<EntryType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('income').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Salary deposit',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '75',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salary').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select where this income is received.'),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.id == bank.id),
          store.entries,
          DateTime.now(),
        ),
        7500,
      );
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Account wealth: EUR 175.00'), findsOneWidget);
      expect(find.text('Available to spend: EUR 100.00'), findsOneWidget);
      expect(find.text('Excludes blocked accounts: EUR 75.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      expect(find.text('Main bank'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recurring section creates rent, edits future price, pauses, resumes and deletes rule',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await openMenuItem(tester, 'Recurring payments');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add recurring payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        'Monthly rent',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (EUR)'),
        '10',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rent & utilities').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules, hasLength(1));
      expect(store.entries.single.amount, 1000);
      await tester.tap(find.text('Pause'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isFalse);
      await tester.tap(find.text('Resume'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isTrue);
      await tester.tap(find.text('Monthly rent').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (EUR)'),
        '12',
      );
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.amount, 1200);
      expect(store.entries.single.amount, 1000);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules, isEmpty);
      expect(store.entries, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit bank balance and overdraft setting, then reject an unaffordable payment',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(prepareAccounts);
      final bank = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.bank,
      );
      await tester.runAsync(
        () => store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 1000,
            currency: Currency.eur,
            date: dateOnly(DateTime.now()),
            description: 'Previous payment',
            category: 'Other',
            accountId: bank.id,
          ),
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await openMenuItem(tester, 'Accounts');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main bank'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Account name'),
        'Debit bank',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Current balance (EUR)'),
        '20',
      );
      await tester.tap(find.widgetWithText(SwitchListTile, 'Allow overdraft'));
      await tester.tap(find.text('Save account'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final updated = store.accounts.singleWhere((a) => a.id == bank.id);
      expect(updated.name, 'Debit bank');
      expect(updated.canOverdraw, isFalse);
      expect(accountBalance(updated, store.entries, DateTime.now()), 2000);
      expect(store.entries.single.amount, 1000);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Too much',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '30',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Debit bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Insufficient funds in Debit bank'),
        findsOneWidget,
      );
      expect(store.entries, hasLength(1));
      expect(accountBalance(updated, store.entries, DateTime.now()), 2000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('first launch requires cash and bank setup and does not repeat', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Set up your cash'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(store.accounts, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cash balance (EUR)'),
      '50',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bank account 1 name'),
      'My bank',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bank balance (EUR)'),
      '-10',
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Allow overdraft'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Continue'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review your starting balances'), findsOneWidget);
    expect(store.accounts, isEmpty);
    await tester.tap(find.text('Finish setup'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.setupCompleted, isTrue);
    expect(store.accounts, hasLength(2));
    expect(
      store.accounts.singleWhere((a) => a.kind == AccountKind.cash).opening,
      5000,
    );
    expect(
      store.accounts.singleWhere((a) => a.kind == AccountKind.bank).opening,
      -1000,
    );
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(store.refresh);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Moneva'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'category section adds and renames categories and separates income',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await openMenuItem(tester, 'Categories');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add expense category'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Pet care',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byTooltip('Edit Pet care'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byTooltip('Edit Pet care'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Pets',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Pets'), findsOneWidget);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Pets'), findsNothing);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('Add income category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cashflow asks for missing inputs and shows a saved plan', (
    tester,
  ) async {
    await tester.runAsync(prepareAccounts);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashflow'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Insufficient data.'), findsOneWidget);
    await tester.runAsync(
      () => store.savePlan(
        FreedomPlan(
          currency: Currency.eur,
          start: DateTime(2026, 10),
          spending: 10000,
          passive: 0,
          portfolio: 3000000,
          contribution: 0,
          earned: 10000,
          cash: 60000,
          returnBps: 0,
          inflationBps: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current FI coverage: 100.00%'), findsOneWidget);
    expect(find.text('First modeled FI month: 2026-10-01'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
      find.text('Cash runway including contributions: 6 whole months'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'add, edit and delete updates the persisted ledger and dashboard',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      expect(find.textContaining('No transactions'), findsOneWidget);
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Currency: EUR (€)'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<Currency>), findsNothing);
      expect(find.textContaining('IQD'), findsNothing);
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a description.'), findsOneWidget);
      expect(store.entries, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Groceries',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '12.34',
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save transaction'));
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.amount, 1234);
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.kind == AccountKind.cash),
          store.entries,
          DateTime.now(),
        ),
        8766,
      );
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Spending after refunds: 12.34'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '15',
      );
      await tester.tap(find.byType(DropdownButtonFormField<AccountKind>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main bank').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save transaction'));
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1));
      expect(store.entries.single.amount, 1500);
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.kind == AccountKind.bank),
          store.entries,
          DateTime.now(),
        ),
        -1500,
      );
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.kind == AccountKind.cash),
          store.entries,
          DateTime.now(),
        ),
        10000,
      );
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(
        accountBalance(
          store.accounts.singleWhere((a) => a.kind == AccountKind.bank),
          store.entries,
          DateTime.now(),
        ),
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
