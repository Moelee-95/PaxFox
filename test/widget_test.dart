import 'helpers/sheet_helpers.dart';

import 'package:flutter/material.dart';

import 'helpers/wait_for_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/main.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/screens/cashflow_screen.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/presentation/category_icons.dart';
import 'package:moneva/core/presentation/transaction_tile.dart';
import 'package:moneva/screens/more_screen.dart';
import 'package:moneva/core/presentation/account_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Future<void> selectMainTab(WidgetTester tester, String label) async {
    if (find.byType(NavigationBar).evaluate().isEmpty) {
      await closeTopPage(tester);
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await selectMainTab(tester, 'More');
    final option = find.widgetWithText(ListTile, label);
    final scrollable = find
        .descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(option, 200, scrollable: scrollable);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Future<void> openManualTransaction(WidgetTester tester) async {
    if (tester
            .widget<NavigationBar>(find.byType(NavigationBar))
            .selectedIndex ==
        3) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Add transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-expense-manual')));
    await tester.pumpAndSettle();
  }

  Future<void> selectAccount(WidgetTester tester, String name) async {
    final card = find
        .descendant(of: find.byType(AccountPicker), matching: find.text(name))
        .first;
    await tester.ensureVisible(card);
    await tester.tap(card);
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
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await openManualTransaction(tester);
      expect(
        tester.getBottomLeft(find.text('Save transaction')).dy,
        lessThan(1552),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Return home payment',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '2');
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Groceries');
      await tester.pumpAndSettle();
      await selectAccount(tester, 'Cash');
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

  testWidgets('month selector swipes change months without switching screens', (
    tester,
  ) async {
    await tester.runAsync(prepareAccounts);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('month-selector'));
    final context = tester.element(selector);
    final labels = MaterialLocalizations.of(context);
    final now = DateTime.now();
    expect(find.text(labels.formatMonthYear(now)), findsOneWidget);
    final currentLabel = find.text(labels.formatMonthYear(now));
    final initialX = tester.getCenter(currentLabel).dx;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('month-pages'))),
    );
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    expect(tester.getCenter(currentLabel).dx, lessThan(initialX));
    await gesture.cancel();
    await tester.pumpAndSettle();
    await tester.fling(selector, const Offset(-220, 0), 700);
    await tester.pumpAndSettle();
    expect(
      find.text(labels.formatMonthYear(DateTime(now.year, now.month + 1))),
      findsOneWidget,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await tester.fling(selector, const Offset(220, 0), 700);
    await tester.pumpAndSettle();
    expect(find.text(labels.formatMonthYear(now)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('horizontal swipes and navigation taps stay synchronized', (
    tester,
  ) async {
    await tester.runAsync(prepareAccounts);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    for (var index = 2; index < 3; index++) {
      await tester.drag(
        find.byKey(const ValueKey('main-pages')),
        const Offset(-650, 0),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        index,
      );
    }
    await tester.drag(
      find.byKey(const ValueKey('main-pages')),
      const Offset(650, 0),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    await openMenuItem(tester, 'All transactions');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('All transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction filters survive switching between lazy pages', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await prepareAccounts();
      for (final item in [
        (description: 'Bread', type: EntryType.expense),
        (description: 'Bread return', type: EntryType.refund),
        (description: 'Milk', type: EntryType.expense),
      ]) {
        await store.saveEntry(
          LedgerEntry(
            type: item.type,
            amount: 100,
            currency: Currency.eur,
            date: dateOnly(DateTime.now()),
            description: item.description,
            category: 'Groceries',
            accountId: store.accounts.first.id,
          ),
        );
      }
    });
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await openMenuItem(tester, 'All transactions');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bread');
    await tester.pumpAndSettle();
    await chooseEntryType(tester, 'expense');
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Bread return'), findsNothing);
    expect(find.text('Milk'), findsNothing);

    await selectMainTab(tester, 'Home');
    await openMenuItem(tester, 'All transactions');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'bread',
    );
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Bread return'), findsNothing);
    expect(find.text('Milk'), findsNothing);

    await tester.longPress(find.text('Bread'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cancel selection'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Home navigation restores the pager; More omits Home and Reports',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Account balances today'), findsOneWidget);
      expect(find.text('Monthly overview'), findsNothing);
      expect(find.textContaining('Spending after refunds:'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Reports'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Home'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('month-selector')), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
    },
  );

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
      await chooseEntryType(tester, 'income');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        'Monthly salary',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (€)'),
        '20',
      );
      await openCategoryPicker(tester);
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
      await tester.tap(find.byTooltip('Pause'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'More contains management; transaction icons use category and type colors',
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
      await openMenuItem(tester, 'All transactions');
      await tester.pumpAndSettle();
      for (final type in EntryType.values) {
        final row = find.widgetWithText(TransactionTile, 'Icon ${type.name}');
        final icon = tester.widget<Icon>(
          find
              .descendant(
                of: find.descendant(
                  of: row,
                  matching: find.byKey(
                    const ValueKey('transaction-category-badge'),
                  ),
                ),
                matching: find.byType(Icon),
              )
              .first,
        );
        final price = tester.widget<Text>(
          find.descendant(
            of: row,
            matching: find.byKey(const ValueKey('transaction-price')),
          ),
        );
        expect(price.style!.color, switch (type) {
          EntryType.expense => Colors.red.shade700,
          EntryType.income || EntryType.refund => Colors.green.shade700,
          EntryType.transfer => Colors.blue.shade700,
        });
        expect(
          icon.icon,
          type == EntryType.transfer
              ? Icons.swap_horiz
              : categoryIconData(
                  type == EntryType.income
                      ? CategoryIcon.salary
                      : CategoryIcon.pets,
                ),
        );
      }
      expect(find.byType(NavigationDestination), findsNothing);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Accounts'), findsNothing);
      await selectMainTab(tester, 'Home');
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
      await openMenuItem(tester, 'Categories');
      await tester.tap(find.byTooltip('Edit Groceries'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextField, 'Search icons'),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Search icons'),
        'home',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-icon-home')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await closeTopPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      final changed = tester.widget<TransactionTile>(
        find.widgetWithText(TransactionTile, 'Icon expense'),
      );
      expect(
        categoryIconData(changed.categoryIcon),
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
      await tester.pump();
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.length == 1),
      );
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
      await openManualTransaction(tester);
      await chooseEntryType(tester, 'income');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Salary deposit',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '75',
      );
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Salary');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transaction'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select where this income is received.'),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);

      await selectAccount(tester, 'Main bank');
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
      expect(find.text('Account wealth'), findsOneWidget);
      expect(find.text('Available to spend'), findsOneWidget);
      expect(find.text('Excludes blocked accounts: €75.00'), findsOneWidget);
      await openManualTransaction(tester);
      expect(
        find.descendant(
          of: find.byType(AccountPicker),
          matching: find.text('Main bank'),
        ),
        findsNothing,
      );
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
        find.widgetWithText(TextFormField, 'Amount (€)'),
        '10',
      );
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Rent & utilities');
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
      await tester.tap(find.byTooltip('Pause'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isFalse);
      await tester.tap(find.byTooltip('Resume'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.active, isTrue);
      await tester.tap(find.text('Monthly rent').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (€)'),
        '12',
      );
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.amount, 1200);
      expect(store.entries.single.amount, 1000);
      await tester.tap(find.byTooltip('Delete recurring rule'));
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
        find.widgetWithText(TextFormField, 'Current balance (€)'),
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
      await closeTopPage(tester);
      await tester.pumpAndSettle();
      await openManualTransaction(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Too much',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '30',
      );
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Other');
      await tester.pumpAndSettle();
      await selectAccount(tester, 'Debit bank');
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
      find.widgetWithText(TextFormField, 'Cash balance (€)'),
      '50',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bank account 1 name'),
      'My bank',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Bank balance (€)'),
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
    expect(find.text('Welcome to PaxFox'), findsNothing);
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
      await tester.tap(find.byTooltip('Add expense category'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Pet care',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await waitForStore(
          store,
          () => store.categories.any((category) => category.name == 'Pet care'),
        );
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
        await waitForStore(
          store,
          () => store.categories.any((category) => category.name == 'Pets'),
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('Pets'), findsOneWidget);
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('Pets'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Salary'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Salary'), findsOneWidget);
      expect(find.byTooltip('Add income category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cashflow remains an empty navigation destination', (
    tester,
  ) async {
    await tester.runAsync(prepareAccounts);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cashflow'));
    await tester.pumpAndSettle();
    expect(find.byType(CashflowScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CashflowScreen),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('month-selector')), findsOneWidget);
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
      expect(find.textContaining('No expenses or refunds'), findsOneWidget);
      await openManualTransaction(tester);
      expect(find.text('Currency: EUR'), findsNothing);
      expect(find.text(Currency.eur.symbol.trim()), findsWidgets);
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
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Groceries');
      await tester.pumpAndSettle();
      await selectAccount(tester, 'Cash');
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
      expect(find.text('€87.66').first, findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '15',
      );
      await selectAccount(tester, 'Main bank');
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
  testWidgets(
    'short slow swipes settle to the adjacent main destination in either direction',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      final pages = find.byKey(const ValueKey('main-pages'));
      Future<void> slowSwipe(double dx) async {
        final gesture = await tester.startGesture(tester.getCenter(pages));
        for (var i = 1; i <= 5; i++) {
          await gesture.moveBy(
            Offset(dx / 5, 0),
            timeStamp: Duration(milliseconds: i * 100),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 600));
        await gesture.up(timeStamp: const Duration(milliseconds: 1100));
        await tester.pumpAndSettle();
      }

      await slowSwipe(-100);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await slowSwipe(100);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      // A long slow drag must not snap backwards after crossing halfway.
      await slowSwipe(-550);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'More swipes settle on Cashflow and navigation interrupts partial drags',
    (tester) async {
      await tester.runAsync(prepareAccounts);
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      final pages = find.byKey(const ValueKey('main-pages'));
      for (var attempt = 0; attempt < 6; attempt++) {
        await selectMainTab(tester, 'More');
        final gesture = await tester.startGesture(tester.getCenter(pages));
        await gesture.moveBy(const Offset(80, 0));
        await tester.pump(const Duration(milliseconds: 250));
        await gesture.moveBy(const Offset(400, 0));
        await tester.pump(const Duration(milliseconds: 250));
        await gesture.up();
        await tester.pumpAndSettle(
          const Duration(milliseconds: 16),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 3),
        );
        final pager = tester.widget<PageView>(pages).controller!;
        expect(pager.page, closeTo(2, .001));
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        // A tap while a new swipe is in progress must stop the old scroll.
        final interrupted = await tester.startGesture(tester.getCenter(pages));
        await interrupted.moveBy(const Offset(-120, 0));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Home'),
          ),
        );
        await interrupted.up();
        await tester.pumpAndSettle();
        expect(pager.page, closeTo(0, .001));
        expect(tester.takeException(), isNull);
      }
    },
  );
}
