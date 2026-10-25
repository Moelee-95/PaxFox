import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/invoice_review_screen.dart';
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
        name: 'Cash',
        currency: Currency.eur,
        opening: 2000,
        asOf: DateTime(2026, 1, 1),
        includeOnAsOf: true,
        kind: AccountKind.cash,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  testWidgets(
    'missing date and currency have individual field errors instead of a combined message',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(
            store: store,
            draft: const InvoiceDraft(
              merchant: 'Shop',
              total: 100,
              category: 'Groceries',
              items: [
                InvoiceItem(
                  description: 'Milk',
                  quantity: '1',
                  total: 100,
                  category: 'Groceries',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transactions'));
      await tester.pumpAndSettle();
      expect(
        find.text('Confirm that the original invoice is in EUR.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Choose the invoice date. It could not be determined from the scan.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Choose the cash or bank account used to pay this invoice.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Confirm the invoice date, EUR currency and payment account.',
        ),
        findsNothing,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        find.text('Confirm that the original invoice is in EUR.'),
        findsNothing,
      );
      expect(
        find.text(
          'Choose the invoice date. It could not be determined from the scan.',
        ),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'bad items show inline errors and Save sits above the device navigation inset',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final draft = InvoiceDraft(
        merchant: 'Shop',
        date: DateTime(2026, 10, 25),
        currency: 'EUR',
        total: 300,
        category: 'Groceries',
        adjustment: 0,
        items: [
          const InvoiceItem(
            description: 'Good item',
            quantity: '1',
            total: 100,
            category: 'Groceries',
          ),
          const InvoiceItem(
            description: '',
            quantity: '1',
            total: null,
            category: null,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(store: store, draft: draft),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Save transactions')).dy,
        lessThan(1752),
      );
      await tester.tap(find.text('Save transactions'));
      await tester.pumpAndSettle();
      final invalid = find.byKey(const ValueKey('invoice-item-1'));
      expect(
        find.descendant(
          of: invalid,
          matching: find.textContaining('Enter an item name.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: invalid,
          matching: find.textContaining('Enter a valid price in EUR.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: invalid,
          matching: find.textContaining(
            'Select an available expense category.',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Card>(invalid).shape, isNotNull);
      expect(
        tester.widget<Card>(find.byKey(const ValueKey('invoice-item-0'))).shape,
        isNull,
      );
      await tester.tap(find.text('Missing item name'));
      await tester.pumpAndSettle();
      expect(find.text('Price (EUR)'), findsOneWidget);
      expect(find.text('Quantity'), findsNothing);
      expect(find.text('Unit price (optional EUR)'), findsNothing);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'review is required and editing an item persists it with a single expense',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final draft = InvoiceDraft(
        merchant: 'Synthetic shop',
        date: DateTime(2026, 10, 25),
        currency: 'EUR',
        total: 1000,
        category: 'Groceries',
        adjustment: 0,
        raw: 'original output',
        items: [
          const InvoiceItem(
            description: 'Milk',
            quantity: '1',
            total: 1000,
            category: 'Groceries',
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(store: store, draft: draft),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Milk'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Item name'),
        'Reviewed milk',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Price (EUR)'),
        '12',
      );
      await tester.tap(find.text('Apply item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transactions'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(
        find.textContaining('Item totals plus adjustment'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Charged total (EUR)'),
        '12',
      );
      await tester.tap(find.text('Save transactions'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(1));
      expect(store.entries.single.amount, 1200);
      expect(
        (await tester.runAsync(() => store.db.query('receipt_items')))!
            .single['description'],
        'Reviewed milk',
      );
      expect(
        (await tester.runAsync(() => store.db.query('receipt_items')))!
            .single['edited'],
        1,
      );
      expect(
        accountBalance(
          store.accounts.single,
          store.entries,
          DateTime(2026, 10, 25),
        ),
        800,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
