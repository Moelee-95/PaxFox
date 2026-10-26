import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  late Account cash;
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
        opening: 450,
        asOf: DateTime(2026, 1, 1),
        includeOnAsOf: true,
        kind: AccountKind.cash,
      ),
    );
    cash = store.accounts.single;
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  InvoiceDraft draft({int total = 450}) => InvoiceDraft(
    merchant: 'Market',
    date: DateTime(2026, 1, 2),
    currency: 'EUR',
    category: 'Groceries',
    total: total,
    adjustment: 0,
    raw: 'Original',
    items: [
      InvoiceItem(
        description: 'Milk',
        quantity: '1',
        total: total == 450 ? 300 : total - 150,
        category: 'Groceries',
      ),
      const InvoiceItem(
        description: 'Soap',
        quantity: '1',
        total: 200,
        category: 'Shopping',
      ),
      const InvoiceItem(
        description: 'Discount',
        quantity: '1',
        total: -50,
        category: 'Groceries',
      ),
    ],
  );
  test('scan saves independent transactions with item categories and only net invoice spending', () async {
    await store.saveInvoiceBatch(
      draft: draft(),
      accountId: cash.id!,
      imagePaths: [],
    );
    expect(store.entries, hasLength(3));
    expect(
      store.entries.singleWhere((e) => e.description == 'Milk').amount,
      300,
    );
    expect(
      store.entries.singleWhere((e) => e.description == 'Soap').category,
      'Shopping',
    );
    expect(
      store.entries.singleWhere((e) => e.description == 'Discount').type,
      EntryType.refund,
    );
    final totals = Totals();
    for (final e in store.entries) {
      totals.add(e);
    }
    expect(totals.spending, 450);
    expect(totals.income, 0);
    expect(accountBalance(cash, store.entries, DateTime(2026, 1, 2)), 0);
    expect(await store.db.query('receipts'), isEmpty);
    expect(await store.db.query('scanned_invoices'), hasLength(1));
    final soap = store.entries.singleWhere((e) => e.description == 'Soap');
    await store.saveEntry(
      LedgerEntry(
        id: soap.id,
        type: EntryType.expense,
        amount: 100,
        currency: Currency.eur,
        date: soap.date,
        description: 'Edited soap',
        category: 'Shopping',
        accountId: cash.id,
      ),
    );
    expect(store.entries, hasLength(3));
    expect(accountBalance(cash, store.entries, DateTime(2026, 1, 2)), 100);
    expect(
      (await store.scannedInvoiceFor(soap.id!))!['raw_response'],
      'Original',
    );
    await store.deleteEntry(soap.id!);
    expect(await store.db.query('scanned_invoices'), hasLength(1));
    for (final e in List.of(
      store.entries,
    ).where((e) => e.type == EntryType.expense)) {
      await store.deleteEntry(e.id!);
    }
    for (final e in List.of(store.entries)) {
      await store.deleteEntry(e.id!);
    }
    expect(await store.db.query('scanned_invoices'), isEmpty);
  });
  test(
    'one unaffordable item rolls back every transaction, item and batch',
    () async {
      await expectLater(
        store.saveInvoiceBatch(
          draft: draft(total: 550),
          accountId: cash.id!,
          imagePaths: [],
        ),
        throwsArgumentError,
      );
      expect(store.entries, isEmpty);
      for (final table in [
        'transactions',
        'receipt_items',
        'scanned_invoices',
        'scanned_invoice_entries',
      ]) {
        expect(await store.db.query(table), isEmpty);
      }
      expect(accountBalance(cash, store.entries, DateTime(2026, 1, 2)), 450);
    },
  );
  test('multiple invoices preserve item dates and validate historical funds as one batch', () async {
    final early = DateTime(2026, 1, 2), late = DateTime(2026, 2, 2);
    final batch = InvoiceDraft(
      merchant: 'Two shops',
      multipleInvoices: true,
      currency: 'EUR',
      total: 400,
      category: 'Groceries',
      items: [
        InvoiceItem(
          description: 'Early purchase',
          quantity: '2',
          total: 500,
          category: 'Groceries',
          date: early,
        ),
        InvoiceItem(
          description: 'Early discount',
          quantity: '1',
          total: -100,
          category: 'Groceries',
          date: early,
        ),
        InvoiceItem(
          description: 'Later purchase',
          quantity: '1',
          total: 50,
          category: 'Groceries',
          date: late,
        ),
        InvoiceItem(
          description: 'Later return',
          quantity: '1',
          total: -50,
          category: 'Groceries',
          date: late,
        ),
      ],
    );
    final before = DateTime.now().toUtc();
    await store.saveInvoiceBatch(
      draft: batch,
      accountId: cash.id!,
      imagePaths: [],
    );
    expect(store.entries, hasLength(5));
    expect(store.entries.where((entry) => entry.date == early), hasLength(3));
    expect(store.entries.where((entry) => entry.date == late), hasLength(2));
    expect(store.currentBalances.wealth, 50);
    for (final entry in store.entries) {
      expect(entry.createdAt!.isUtc, isTrue);
      expect(entry.createdAt!.isBefore(before), isFalse);
    }
    final source = await store.scannedInvoiceFor(store.entries.first.id!);
    final restored = InvoiceDraft.fromMap(
      jsonDecode(source!['draft'] as String) as Map<String, dynamic>,
    );
    expect(restored.multipleInvoices, isTrue);
    expect(restored.items.last.date, late);
  });

  test(
    'a later invoice refund cannot cover an earlier historical deficit',
    () async {
      final batch = InvoiceDraft(
        merchant: 'Two shops',
        multipleInvoices: true,
        currency: 'EUR',
        total: 400,
        category: 'Groceries',
        items: [
          InvoiceItem(
            description: 'Purchase',
            quantity: '1',
            total: 500,
            category: 'Groceries',
            date: DateTime(2026, 1, 2),
          ),
          InvoiceItem(
            description: 'Later return',
            quantity: '1',
            total: -100,
            category: 'Groceries',
            date: DateTime(2026, 2, 2),
          ),
        ],
      );
      await expectLater(
        store.saveInvoiceBatch(
          draft: batch,
          accountId: cash.id!,
          imagePaths: [],
        ),
        throwsArgumentError,
      );
      expect(store.entries, isEmpty);
      expect(await store.db.query('scanned_invoices'), isEmpty);
      expect(await store.db.query('receipt_items'), isEmpty);
    },
  );

  test('multi-invoice parser does not fill an unreadable date from another invoice', () {
    final batch = parseInvoice(
      jsonEncode({
        'multiple_invoices': true,
        'merchant': 'Two shops',
        'date': '2026-01-02',
        'currency': 'EUR',
        'total': '3.00',
        'category': 'Groceries',
        'items': [
          {
            'description': 'First',
            'quantity': '1',
            'line_total': '1.00',
            'category': 'Groceries',
            'date': '2026-01-02',
          },
          {
            'description': 'Second',
            'quantity': '1',
            'line_total': '2.00',
            'category': 'Groceries',
            'date': null,
          },
        ],
      }),
      {'Groceries'},
    );
    expect(batch.items.first.date, DateTime(2026, 1, 2));
    expect(batch.items.last.date, isNull);
    expect(() => validateInvoice(batch, {'Groceries'}), throwsArgumentError);
  });
}
