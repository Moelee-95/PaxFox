import 'helpers/sheet_helpers.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/screens/recurring_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  final start = dateOnly(DateTime.now());
  final next = DateTime(start.year, start.month + 1, 1);
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: ':memory:',
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Bank',
        currency: Currency.eur,
        opening: 10000,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  RecurringRule rule({
    int? id,
    EntryType type = EntryType.expense,
    bool asset = false,
    bool liability = false,
  }) => RecurringRule(
    id: id,
    description: 'Monthly entry',
    amount: 100,
    category: type == EntryType.income ? 'Salary' : 'Groceries',
    accountId: store.accounts.single.id!,
    day: 1,
    nextDate: next,
    type: type,
    isAsset: asset,
    isLiability: liability,
  );

  test(
    'classification persists through editing, pause, resume and refresh',
    () async {
      await store.saveRecurring(rule(liability: true));
      var saved = store.recurringRules.single;
      expect(saved.isLiability, isTrue);
      expect(saved.isAsset, isFalse);
      await store.setRecurringActive(saved.id!, false);
      await store.setRecurringActive(saved.id!, true);
      await store.refresh();
      expect(store.recurringRules.single.isLiability, isTrue);
      await store.saveRecurring(
        rule(id: saved.id, type: EntryType.income, asset: true),
      );
      saved = store.recurringRules.single;
      expect(saved.isAsset, isTrue);
      expect(saved.isLiability, isFalse);
      expect(store.entries, isEmpty);
      expect(store.currentBalances.wealth, 10000);
    },
  );

  test(
    'classification cannot be assigned to the wrong transaction type',
    () async {
      await expectLater(
        store.saveRecurring(rule(asset: true)),
        throwsArgumentError,
      );
      await expectLater(
        store.saveRecurring(rule(type: EntryType.income, liability: true)),
        throwsArgumentError,
      );
      expect(store.recurringRules, isEmpty);
    },
  );

  testWidgets(
    'form switches between liability and asset and keeps guidance behind info',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: RecurringForm(store: store)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Expenses and income repeat monthly'),
        findsNothing,
      );
      expect(find.text('Liability'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Liability'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is SwitchListTile &&
              (w.title is Text) &&
              ['Liability', 'Asset'].contains((w.title as Text).data),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byWidgetPredicate(
                (w) =>
                    w is SwitchListTile &&
                    (w.title is Text) &&
                    ['Liability', 'Asset'].contains((w.title as Text).data),
              ),
            )
            .value,
        isTrue,
      );
      await chooseEntryType(tester, 'income');
      await tester.pumpAndSettle();
      expect(find.text('Asset'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byWidgetPredicate(
                (w) =>
                    w is SwitchListTile &&
                    (w.title is Text) &&
                    ['Liability', 'Asset'].contains((w.title as Text).data),
              ),
            )
            .value,
        isFalse,
      );
      await tester.ensureVisible(find.text('Asset'));
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is SwitchListTile &&
              (w.title is Text) &&
              ['Liability', 'Asset'].contains((w.title as Text).data),
        ),
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        'Salary',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (€)'),
        '10',
      );
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Salary');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save recurring payment'));
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(store.recurringRules.single.isAsset, isTrue);
      expect(store.recurringRules.single.isLiability, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  test('version 10 migration retains existing rules and ledger and defaults labels off', () async {
    final directory = await Directory.systemTemp.createTemp(
      'moneva_recurring_classification_',
    );
    final path = '${directory.path}/migration.sqlite';
    final original = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    await original.addAccount(
      Account(
        name: 'Existing bank',
        currency: Currency.eur,
        opening: 5000,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
    await original.saveRecurring(
      RecurringRule(
        description: 'Existing schedule',
        amount: 100,
        category: 'Groceries',
        accountId: original.accounts.single.id!,
        day: 1,
        nextDate: next,
      ),
    );
    await original.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 100,
        currency: Currency.eur,
        date: start,
        description: 'Existing purchase',
        category: 'Groceries',
        accountId: original.accounts.single.id,
      ),
    );
    await original.db.execute(
      'ALTER TABLE recurring_rules DROP COLUMN is_asset',
    );
    await original.db.execute(
      'ALTER TABLE recurring_rules DROP COLUMN is_liability',
    );
    await original.db.execute('ALTER TABLE categories DROP COLUMN color');
    await original.db.setVersion(10);
    await original.db.close();
    original.dispose();

    final migrated = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await migrated.db.getVersion(), 15);
      expect(migrated.recurringRules.single.description, 'Existing schedule');
      expect(migrated.recurringRules.single.isAsset, isFalse);
      expect(migrated.recurringRules.single.isLiability, isFalse);
      expect(migrated.entries.single.description, 'Existing purchase');
      expect(migrated.entries.single.createdAt, isNotNull);
      expect(migrated.currentBalances.wealth, 4900);
    } finally {
      await migrated.db.close();
      migrated.dispose();
      await databaseFactoryFfi.deleteDatabase(path);
      await directory.delete();
    }
  });
}
