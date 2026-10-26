import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/account_picker.dart';
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/invoice_review_screen.dart';
import 'package:moneva/features/receipts/invoice_scan_screen.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class PendingExtractor implements InvoiceExtractor {
  final request = Completer<InvoiceDraft>();
  int calls = 0;
  @override
  Future<InvoiceDraft> extract(List<File> images, Set<String> categories) {
    calls++;
    return request.future;
  }
}

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: ':memory:',
      factory: databaseFactoryFfi,
    );
    await store.completeSetup([
      Account(
        name: 'Wallet',
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

  InvoiceDraft draft({String? currency = 'EUR', int adjustment = 0}) =>
      InvoiceDraft(
        merchant: 'Shop',
        date: dateOnly(DateTime.now()),
        currency: currency,
        total: 1000 + adjustment,
        adjustment: adjustment,
        adjustmentNote: 'Discount',
        category: 'Groceries',
        raw: 'Original extraction',
        items: const [
          InvoiceItem(
            description: 'Milk',
            quantity: '1',
            total: 1000,
            category: 'Groceries',
          ),
        ],
      );

  testWidgets(
    'EUR review hides confirmation and removed fields; help is available on demand',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(store: store, draft: draft()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.textContaining('Charged total'), findsNothing);
      expect(find.textContaining('Adjustment explanation'), findsNothing);
      expect(find.textContaining('Review the extracted items.'), findsNothing);
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Review the extracted items.'),
        findsOneWidget,
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Review the extracted items.'), findsNothing);
    },
  );

  for (final currency in <String?>[null, 'USD']) {
    testWidgets('$currency currency requires confirmation before saving', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(
            store: store,
            draft: draft(currency: currency),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.text('Save transactions'));
      await tester.pumpAndSettle();
      expect(
        find.text('Confirm that the original invoice is in EUR.'),
        findsOneWidget,
      );
      expect(store.entries, isEmpty);
    });
  }

  testWidgets(
    'an extracted adjustment becomes a visible refund item and saves once',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceReviewScreen(
            store: store,
            draft: draft(adjustment: -200),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text('Items total: €8.00'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AccountPicker),
          matching: find.text('Wallet'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.text('Save transactions'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      expect(store.entries, hasLength(2));
      expect(
        store.entries
            .singleWhere((entry) => entry.type == EntryType.refund)
            .amount,
        200,
      );
      expect(
        store.currentBalances.byAccount[store.accounts
            .singleWhere((account) => account.name == 'Wallet')
            .id],
        9200,
      );
      final saved = jsonDecode(
        (await tester.runAsync(() => store.db.query('scanned_invoices')))!
                .single['draft']
            as String,
      ) as Map<String, dynamic>;
      expect(saved['total'], 800);
      expect(saved['adjustment'], 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Extract and cancellation remain above the safe area with ten images',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final extractor = PendingExtractor();
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceScanScreen(
            store: store,
            extractor: extractor,
            autoCapture: false,
            initialImages: List.generate(
              10,
              (index) => File('missing-preview-$index.jpg'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Capture all pages'), findsNothing);
      expect(find.byTooltip('Scan more pages'), findsOneWidget);
      expect(find.byTooltip('Gallery'), findsOneWidget);
      expect(tester.getBottomRight(find.text('Extract')).dy, lessThan(652));
      await tester.tap(find.text('Extract'));
      await tester.pump();
      expect(extractor.calls, 1);
      expect(
        tester.getBottomRight(find.text('Cancel extraction')).dy,
        lessThan(652),
      );
      await tester.tap(find.text('Cancel extraction'));
      await tester.pumpAndSettle();
      extractor.request.complete(const InvoiceDraft());
      await tester.pumpAndSettle();
      expect(find.text('Review invoice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pull refresh reloads a changed ledger and displays the creation time',
    (tester) async {
      await tester.runAsync(
        () => store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: dateOnly(DateTime.now()),
            description: 'Original name',
            category: 'Groceries',
            accountId: store.accounts.first.id,
          ),
        ),
      );
      final created = store.entries.single.createdAt!;
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      expect(find.textContaining('Added '), findsOneWidget);
      await tester.runAsync(
        () =>
            store.db.update('transactions', {'description': 'Refreshed name'}),
      );
      expect(find.text('Original name'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 350));
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      expect(store.entries.single.description, 'Refreshed name');
      await tester.pumpAndSettle();
      expect(find.text('Refreshed name'), findsOneWidget);
      expect(store.entries.single.createdAt, created);
      await tester.runAsync(
        () => store.saveEntry(
          LedgerEntry(
            id: store.entries.single.id,
            type: EntryType.expense,
            amount: 200,
            currency: Currency.eur,
            date: dateOnly(DateTime.now()),
            description: 'Edited',
            category: 'Groceries',
            accountId: store.accounts.first.id,
          ),
        ),
      );
      expect(store.entries.single.createdAt, created);
      expect(tester.takeException(), isNull);
    },
  );
}
