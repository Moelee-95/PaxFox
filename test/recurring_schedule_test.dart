import 'package:flutter/material.dart';
import 'package:moneva/screens/recurring_screen.dart';

import 'helpers/wait_for_store.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
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

  test(
    'weekly alignment and daily/weekly intervals use calendar arithmetic',
    () {
      expect(
        firstRecurringDate(
          DateTime(2026, 11, 7),
          RecurrenceFrequency.week,
          DateTime.monday,
          1,
        ),
        DateTime(2026, 11, 9),
      );
      expect(
        nextRecurringDate(
          DateTime(2026, 12, 31),
          RecurrenceFrequency.day,
          2,
          1,
          1,
        ),
        DateTime(2027, 1, 2),
      );
      expect(
        nextRecurringDate(
          DateTime(2026, 11, 9),
          RecurrenceFrequency.week,
          3,
          1,
          1,
        ),
        DateTime(2026, 11, 30),
      );
    },
  );
  test('month/year schedules clamp short months and recover leap days', () {
    expect(
      nextRecurringDate(
        DateTime(2026, 1, 31),
        RecurrenceFrequency.month,
        1,
        31,
        1,
      ),
      DateTime(2026, 2, 28),
    );
    expect(
      nextRecurringDate(
        DateTime(2026, 2, 28),
        RecurrenceFrequency.month,
        1,
        31,
        1,
      ),
      DateTime(2026, 3, 31),
    );
    expect(
      firstRecurringDate(DateTime(2026, 3), RecurrenceFrequency.year, 29, 2),
      DateTime(2027, 2, 28),
    );
    expect(
      nextRecurringDate(
        DateTime(2027, 2, 28),
        RecurrenceFrequency.year,
        1,
        29,
        2,
      ),
      DateTime(2028, 2, 29),
    );
  });
  test(
    'manual daily occurrences stay separate and do not post until confirmation',
    () async {
      final start = DateTime(2026, 11, 1);
      await store.saveRecurring(
        RecurringRule(
          description: 'Confirm rent',
          amount: 1000,
          category: store.categoriesFor(EntryType.expense).first.name,
          accountId: store.accounts.single.id!,
          day: 1,
          nextDate: start,
          frequency: RecurrenceFrequency.day,
          automatic: false,
          reminderMinutes: 18 * 60 + 15,
        ),
        today: start,
      );
      await store.processRecurring(today: DateTime(2026, 11, 3));
      expect(store.recurringOccurrences.length, 3);
      expect(
        store.recurringOccurrences.every(
          (o) => o.manual && o.status == 'failed',
        ),
        isTrue,
      );
      expect(store.entries, isEmpty);
      expect(store.currentBalances.wealth, 100000);
      final id = store.recurringOccurrences.last.id;
      await store.skipRecurring(id);
      expect(
        store.recurringOccurrences.firstWhere((o) => o.id == id).status,
        'failed',
      );
      await store.retryRecurring(id, paidOn: DateTime(2026, 11, 7));
      expect(store.entries.single.date, DateTime(2026, 11, 7));
      expect(store.currentBalances.wealth, 99000);
      await store.retryRecurring(id, paidOn: DateTime(2026, 11, 8));
      expect(store.entries.length, 1);
      await store.refresh();
      expect(store.recurringRules.single.reminderMinutes, 1095);
      expect(store.recurringRules.single.automatic, isFalse);
      expect(store.recurringRules.single.frequency, RecurrenceFrequency.day);
    },
  );
  test(
    'automatic weekly income posts each interval once and respects end date',
    () async {
      final start = DateTime(2026, 11, 2);
      await store.saveRecurring(
        RecurringRule(
          description: 'Weekly income',
          type: EntryType.income,
          amount: 1000,
          category: store.categoriesFor(EntryType.income).first.name,
          accountId: store.accounts.single.id!,
          day: DateTime.monday,
          frequency: RecurrenceFrequency.week,
          interval: 2,
          nextDate: start,
          endDate: DateTime(2026, 11, 30),
        ),
        today: start,
      );
      await store.processRecurring(today: DateTime(2026, 12, 20));
      expect(store.entries.map((e) => e.date).toSet(), {
        DateTime(2026, 11, 2),
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 30),
      });
      expect(store.recurringRules.single.active, isFalse);
      await store.processRecurring(today: DateTime(2026, 12, 20));
      expect(store.entries.length, 3);
    },
  );
  test('creation timestamp may be edited explicitly without changing financial date', () async {
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 100,
        currency: Currency.eur,
        date: DateTime(2026, 11, 1),
        description: 'Entry',
        category: store.categoriesFor(EntryType.expense).first.name,
        accountId: store.accounts.single.id,
      ),
    );
    final entry = store.entries.single;
    final creation = DateTime.utc(2026, 10, 5, 14, 42);
    await store.saveEntry(entry, createdAt: creation);
    expect(store.entries.single.createdAt, creation);
    expect(store.entries.single.date, DateTime(2026, 11, 1));
    expect(store.currentBalances.wealth, 99900);
    await store.saveEntry(store.entries.single);
    expect(store.entries.single.createdAt, creation);
  });
  test(
    'shared invoice labels persist for items and survive individual item edits',
    () async {
      final category = store.categoriesFor(EntryType.expense).first.name;
      await store.saveInvoiceBatch(
        draft: InvoiceDraft(
          merchant: 'Synthetic store',
          currency: 'EUR',
          date: DateTime(2026, 11, 1),
          total: 300,
          category: category,
          items: [
            InvoiceItem(
              description: 'A',
              quantity: '1',
              total: 100,
              category: category,
              date: DateTime(2026, 11, 1),
            ),
            InvoiceItem(
              description: 'B',
              quantity: '1',
              total: 200,
              category: category,
              date: DateTime(2026, 11, 1),
            ),
          ],
        ),
        accountId: store.accounts.single.id!,
        imagePaths: [],
      );
      expect(store.invoiceGroups.length, 2);
      expect(store.invoiceGroups.values.map((v) => v.id).toSet().length, 1);
      expect(
        store.invoiceGroups.values.every(
          (v) => v.label.contains('Synthetic store'),
        ),
        isTrue,
      );
      await store.saveEntry(
        LedgerEntry.fromMap({
          ...store.entries.first.toMap(),
          'id': store.entries.first.id,
          'description': 'Edited A',
        }),
      );
      expect(store.invoiceGroups.length, 2);
      await store.deleteEntry(store.entries.first.id!);
      expect(store.invoiceGroups.length, 1);
      await store.db.update('scanned_invoices', {'draft': 'damaged json'});
      await store.refresh();
      expect(store.entries.length, 1);
      expect(store.invoiceGroups.values.single.label, startsWith('Invoice #'));
    },
  );
  testWidgets(
    'weekly manual editor saves weekday, interval and reminder mode',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final start = dateOnly(DateTime.now()).add(const Duration(days: 7));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecurringForm(
              store: store,
              rule: RecurringRule(
                description: 'Weekly manual rent',
                amount: 100,
                category: store.categoriesFor(EntryType.expense).first.name,
                accountId: store.accounts.single.id!,
                day: start.day,
                nextDate: start,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      final frequency = find.byType(
        DropdownButtonFormField<RecurrenceFrequency>,
      );
      await tester.scrollUntilVisible(frequency, 200, scrollable: scrollable);
      await tester.tap(frequency);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Week').last);
      await tester.pumpAndSettle();
      final weekday = find.widgetWithText(
        DropdownButtonFormField<int>,
        'Day of week',
      );
      await tester.ensureVisible(weekday);
      await tester.tap(weekday);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friday').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Every N weeks'),
        '2',
      );
      final automatic = find.widgetWithText(
        SwitchListTile,
        'Post automatically',
      );
      await tester.scrollUntilVisible(automatic, 150, scrollable: scrollable);
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(find.textContaining('Reminder time:'), findsOneWidget);
      await tester.tap(find.text('Save recurring payment'));
      await tester.runAsync(
        () => waitForStore(store, () => store.recurringRules.isNotEmpty),
      );
      await tester.pumpAndSettle();
      final saved = store.recurringRules.single;
      expect(saved.frequency, RecurrenceFrequency.week);
      expect(saved.day, DateTime.friday);
      expect(saved.interval, 2);
      expect(saved.automatic, isFalse);
      expect(saved.reminderMinutes, 540);
      expect(saved.nextDate.weekday, DateTime.friday);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
