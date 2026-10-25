import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const fixture =
    '{"merchant":"Market","date":"2026-10-25","currency":"EUR","total":"4.50","category":"Groceries","adjustment":"0.00","adjustment_note":"","items":[{"description":"Milk","quantity":"2","unit_price":"2.50","line_total":"5.00","category":"Groceries"},{"description":"Discount","quantity":"1","line_total":"-0.50","category":"Groceries"}]}';
void main() {
  test('unknown quantities never prevent saving and weighted lines stay single charged items', () {
    const raw =
        '{"merchant":"Synthetic store","date":"2026-10-01","currency":"EUR","total":"6.14","category":"Groceries","adjustment":"0.00","items":[{"description":"Milk","quantity":null,"line_total":"2.10","category":"Groceries"},{"description":"Milk","quantity":null,"line_total":"2.10","category":"Groceries"},{"description":"Weighted produce","quantity":"0.500","unit_price":"3.98","line_total":"1.99","category":"Groceries"},{"description":"Pfand","quantity":null,"line_total":"0.25","category":"Groceries"},{"description":"Pfand return","quantity":null,"line_total":"-0.30","category":"Groceries"}]}';
    final parsed = parseInvoice(raw, {'Groceries'});
    final items = expandInvoiceItems(parsed.items);
    expect(items, hasLength(5));
    expect(items.every((item) => item.quantity == '1'), isTrue);
    expect(items[2].total, 199);
    expect(items.last.total, -30);
    validateInvoice(
      InvoiceDraft(
        merchant: parsed.merchant,
        date: parsed.date,
        currency: parsed.currency,
        total: parsed.total,
        category: parsed.category,
        adjustment: 0,
        items: items,
      ),
      {'Groceries'},
    );
  });
  test('quantities expand to repeated items of one, preserving every cent', () {
    final items = expandInvoiceItems([
      const InvoiceItem(
        description: 'Apple',
        quantity: '3',
        total: 1000,
        unitPrice: 333,
        category: 'Groceries',
      ),
    ]);
    expect(items, hasLength(3));
    expect(
      items.every((item) => item.quantity == '1' && item.unitPrice == null),
      isTrue,
    );
    expect(items.map((item) => item.total), [334, 333, 333]);
    expect(items.fold<int>(0, (sum, item) => sum + item.total!), 1000);
    expect(
      expandInvoiceItems([
        const InvoiceItem(
          description: 'Unknown quantity',
          quantity: '',
          total: 100,
        ),
      ]).single.quantity,
      '1',
    );
  });
  test(
    'parses exact prices, quantity and discount without counting summaries',
    () {
      final draft = parseInvoice(fixture, {'Groceries'});
      expect(draft.items, hasLength(2));
      expect(draft.items.first.total, 500);
      expect(draft.items.last.total, -50);
      expect(draft.total, 450);
      validateInvoice(draft, {'Groceries'});
    },
  );
  test(
    'invalid category, dates, precision and absent values require correction',
    () {
      final draft = parseInvoice(
        fixture
            .replaceAll('Groceries', 'Invented')
            .replaceAll('2026-10-25', '2026-02-30')
            .replaceAll('4.50', '4.501'),
        {'Groceries'},
      );
      expect(draft.date, isNull);
      expect(draft.total, isNull);
      expect(draft.category, isNull);
      expect(() => validateInvoice(draft, {'Groceries'}), throwsArgumentError);
      expect(extractedMoney(1.2), isNull);
    },
  );
  test('mismatch is rejected rather than inventing a balancing amount', () {
    final draft = parseInvoice(fixture.replaceAll('4.50', '9.00'), {
      'Groceries',
    });
    expect(() => validateInvoice(draft, {'Groceries'}), throwsArgumentError);
  });
  test('Gemini request sends all pages and exact categories, parses JSON, and hides error bodies', () async {
    final directory = await Directory.systemTemp.createTemp(
      'moneva_invoice_test_',
    );
    final file = File('${directory.path}/synthetic.jpg');
    await file.writeAsBytes(img.encodeJpg(img.Image(width: 10, height: 10)));
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      final body = jsonDecode(request.body) as Map;
      final parts = ((body['contents'] as List).single as Map)['parts'] as List;
      expect(parts, hasLength(3));
      expect(parts.first['text'], contains('Groceries'));
      expect(parts.first['text'], contains('Deduplicate'));
      expect(request.url.query, isEmpty);
      expect(request.headers['x-goog-api-key'], 'test-only-key');
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'finishReason': 'STOP',
              'content': {
                'parts': [
                  {'text': fixture},
                ],
              },
            },
          ],
        }),
        200,
      );
    });
    final service = GeminiInvoiceExtractor(
      client: client,
      keyLoader: () async => 'test-only-key',
    );
    final draft = await service.extract([file, file], {'Groceries'});
    expect(calls, 1);
    expect(draft.total, 450);
    final failure = GeminiInvoiceExtractor(
      client: MockClient(
        (_) async => http.Response('private body or key', 403),
      ),
      keyLoader: () async => 'test-only-key',
    );
    await expectLater(
      failure.extract([file], {'Groceries'}),
      throwsA(
        isA<InvoiceExtractionException>().having(
          (e) => e.message,
          'safe message',
          isNot(contains('private body')),
        ),
      ),
    );
    await file.delete();
    await directory.delete();
  });
  group('invoice persistence', () {
    late LedgerStore store;
    late int accountId;
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
          opening: 1000,
          asOf: DateTime(2026, 10, 25),
          includeOnAsOf: true,
          kind: AccountKind.cash,
        ),
      );
      accountId = store.accounts.single.id!;
    });
    tearDown(() async {
      await store.db.close();
      store.dispose();
    });
    test('stores one expense plus related items, supports review edits and cascade deletion', () async {
      final draft = parseInvoice(fixture, {'Groceries'});
      await store.saveInvoice(
        draft: draft,
        accountId: accountId,
        imagePaths: ['receipts/synthetic.jpg'],
      );
      expect(store.entries, hasLength(1));
      expect((await store.db.query('receipt_items')), hasLength(2));
      expect(
        accountBalance(
          store.accounts.single,
          store.entries,
          DateTime(2026, 10, 25),
        ),
        550,
      );
      final id = store.entries.single.id!;
      final changed = parseInvoice(
        fixture.replaceAll('4.50', '5.50').replaceAll('5.00', '6.00'),
        {'Groceries'},
      );
      await store.saveInvoice(
        draft: changed,
        accountId: accountId,
        imagePaths: ['receipts/synthetic.jpg'],
        transactionId: id,
      );
      expect(store.entries, hasLength(1));
      expect(store.entries.single.amount, 550);
      expect((await store.receiptFor(id))!['raw_response'], fixture);
      await store.deleteEntry(id);
      expect(await store.db.query('receipt_items'), isEmpty);
      expect(await store.db.query('receipts'), isEmpty);
    });
    test(
      'insufficient funds rolls back parent, receipt, items and edits',
      () async {
        final draft = parseInvoice(fixture, {'Groceries'});
        await store.saveInvoice(
          draft: draft,
          accountId: accountId,
          imagePaths: [],
        );
        final id = store.entries.single.id!;
        final large = parseInvoice(
          fixture.replaceAll('4.50', '14.50').replaceAll('5.00', '15.00'),
          {'Groceries'},
        );
        await expectLater(
          store.saveInvoice(
            draft: large,
            accountId: accountId,
            imagePaths: [],
            transactionId: id,
          ),
          throwsArgumentError,
        );
        expect(store.entries.single.amount, 450);
        expect((await store.receiptFor(id))!['total'], 450);
        expect((await store.db.query('receipt_items')).first['total'], 500);
        await expectLater(
          store.saveInvoice(draft: large, accountId: accountId, imagePaths: []),
          throwsArgumentError,
        );
        expect(await store.db.query('receipts'), hasLength(1));
      },
    );
    test('category renames update receipt item labels while retaining original AI response', () async {
      await store.saveInvoice(
        draft: parseInvoice(fixture, {'Groceries'}),
        accountId: accountId,
        imagePaths: [],
      );
      final category = store.categories.singleWhere(
        (c) => c.name == 'Groceries',
      );
      await store.saveCategory(
        id: category.id,
        kind: CategoryKind.expense,
        name: 'Food',
      );
      expect(
        (await store.db.query('receipt_items'))
            .every((i) => i['category'] == 'Food'),
        isTrue,
      );
      final receipt = (await store.receiptFor(store.entries.single.id!))!;
      expect(
        InvoiceDraft.fromMap(
          jsonDecode(receipt['draft'] as String) as Map<String, dynamic>,
        ).items.first.category,
        'Food',
      );
      expect(receipt['raw_response'], fixture);
    });
  });
}
