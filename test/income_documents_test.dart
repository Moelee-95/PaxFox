import 'helpers/sheet_helpers.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/invoice_image_preparation.dart';
import 'package:moneva/features/receipts/invoice_images.dart';
import 'package:moneva/features/receipts/invoice_scan_screen.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

InvoiceDraft incomeDraft({int amount = 225000}) => InvoiceDraft(
  type: EntryType.income,
  merchant: 'Employer',
  currency: 'EUR',
  date: DateTime(2026, 10, 31),
  total: amount,
  category: 'Salary',
  items: [
    InvoiceItem(
      description: 'Net salary',
      quantity: '1',
      total: amount,
      category: 'Salary',
      date: DateTime(2026, 10, 31),
    ),
  ],
);

class IncomeExtractor implements InvoiceExtractor {
  Set<String>? categories;
  @override
  Future<InvoiceDraft> extract(List<File> files, Set<String> categories) async {
    this.categories = categories;
    return incomeDraft();
  }
}

void main() {
  test('income parser keeps qualified income only and never repeats net pay by quantity', () {
    final draft = parseInvoice(
      jsonEncode({
        'merchant': 'Employer',
        'currency': 'EUR',
        'total': '2250.00',
        'date': '2026-10-31',
        'category': 'Salary',
        'adjustment': '0',
        'items': [
          {
            'entry_kind': 'income',
            'description': 'Net pay',
            'line_total': '2250.00',
            'quantity': '12',
            'category': 'Salary',
          },
          {
            'entry_kind': 'expense',
            'description': 'Tax',
            'line_total': '-750.00',
          },
          {
            'entry_kind': 'transfer',
            'description': 'Own account',
            'line_total': '100.00',
          },
          {'description': 'Unclassified credit', 'line_total': '50.00'},
        ],
      }),
      {'Salary'},
      type: EntryType.income,
    );
    expect(draft.type, EntryType.income);
    expect(draft.items, hasLength(1));
    expect(draft.items.single.total, 225000);
    expect(draft.items.single.quantity, '1');
    validateInvoice(draft, {'Salary'});
    final stored = InvoiceDraft.fromMap(draft.toMap());
    expect(stored.type, EntryType.income);
    final legacy = draft.toMap()..remove('entry_type');
    expect(InvoiceDraft.fromMap(legacy).type, EntryType.expense);
  });

  test(
    'PDF preparation, Gemini MIME and retained source preserve original bytes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'paxfox_income_pdf_',
      );
      final source = File('${directory.path}/statement.pdf');
      final bytes = utf8.encode('%PDF-1.4\nSynthetic document fixture\n%%EOF');
      await source.writeAsBytes(bytes);
      final preparation = InvoiceImagePreparation(
        temporaryDirectory: () async => directory,
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      try {
        final file = await preparation.prepare(source);
        expect(isInvoicePdf(file), isTrue);
        expect(await file.readAsBytes(), bytes);
        final client = MockClient((request) async {
          final body = jsonDecode(request.body);
          final parts = body['contents'].single['parts'] as List;
          final prompt = parts.first['text'] as String;
          expect(prompt, contains('NET PAY'));
          expect(prompt, contains('transfers between'));
          expect(prompt, contains('unpaid invoice'));
          expect(prompt, contains('Salary'));
          expect(prompt, isNot(contains('GERMAN RECEIPT RULES')));
          expect(parts.last['inline_data']['mime_type'], 'application/pdf');
          expect(
            base64Decode(parts.last['inline_data']['data'] as String),
            bytes,
          );
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'merchant': 'Employer',
                          'currency': 'EUR',
                          'date': '2026-10-31',
                          'total': '2250.00',
                          'category': 'Salary',
                          'items': [
                            {
                              'entry_kind': 'income',
                              'description': 'Net salary',
                              'quantity': '1',
                              'line_total': '2250.00',
                              'category': 'Salary',
                            },
                          ],
                        }),
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });
        final draft = await GeminiInvoiceExtractor(
          client: client,
          keyLoader: () async => 'synthetic-test-key',
          type: EntryType.income,
        ).extract([file], {'Salary'});
        expect(draft.type, EntryType.income);
        expect(draft.items.single.total, 225000);
        final saved = await InvoiceImages().retain([file]);
        expect(saved.single, endsWith('.pdf'));
        expect(
          await (await InvoiceImages().resolve(saved.single)).readAsBytes(),
          bytes,
        );
        await InvoiceImages().remove(saved);
        await preparation.dispose();
        expect(await source.readAsBytes(), bytes);
        final bad = File('${directory.path}/not-pdf.pdf');
        await bad.writeAsString('Not a PDF');
        await expectLater(
          InvoiceImagePreparation.bytesFor(bad),
          throwsFormatException,
        );
      } finally {
        await preparation.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );

  group('income flow', () {
    late LedgerStore store;
    late int blockedId;
    setUp(() async {
      sqfliteFfiInit();
      store = await LedgerStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      await store.completeSetup([
        Account(
          name: 'Cash',
          kind: AccountKind.cash,
          currency: Currency.eur,
          opening: 10000,
          asOf: DateTime(2026),
          includeOnAsOf: true,
        ),
        Account(
          name: 'Blocked savings',
          currency: Currency.eur,
          available: false,
          opening: 0,
          asOf: DateTime(2026),
          includeOnAsOf: true,
        ),
      ]);
      blockedId = store.accounts.firstWhere((a) => !a.available).id!;
    });
    tearDown(() async {
      store.dispose();
      await store.db.close();
    });

    test('income batch credits a blocked receiver, retains source and edits independently', () async {
      await store.saveInvoiceBatch(
        draft: incomeDraft(),
        accountId: blockedId,
        imagePaths: [],
      );
      expect(store.entries, hasLength(1));
      final entry = store.entries.single;
      expect(entry.type, EntryType.income);
      expect(entry.amount, 225000);
      expect(store.currentBalances.byAccount[blockedId], 225000);
      final source = await store.scannedInvoiceFor(entry.id!);
      expect(
        InvoiceDraft.fromMap(jsonDecode(source!['draft'] as String)).type,
        EntryType.income,
      );
      await store.saveEntry(
        LedgerEntry(
          id: entry.id,
          type: EntryType.income,
          amount: 226000,
          currency: Currency.eur,
          date: entry.date,
          description: 'Corrected net salary',
          category: 'Salary',
          accountId: blockedId,
        ),
      );
      expect((await store.db.query('receipt_items')).single['total'], 226000);
      expect(store.currentBalances.byAccount[blockedId], 226000);
      await store.deleteEntry(entry.id!);
      expect(store.entries, isEmpty);
      expect(await store.db.query('scanned_invoices'), isEmpty);
      expect(store.currentBalances.byAccount[blockedId], 0);
    });

    test('invalid income cannot become expense or refund or enter legacy invoice storage', () async {
      await expectLater(
        store.saveInvoiceBatch(
          draft: incomeDraft(amount: -100),
          accountId: blockedId,
          imagePaths: [],
        ),
        throwsArgumentError,
      );
      await expectLater(
        store.saveInvoice(
          draft: incomeDraft(),
          accountId: blockedId,
          imagePaths: [],
        ),
        throwsArgumentError,
      );
      expect(store.entries, isEmpty);
      expect(await store.db.query('scanned_invoices'), isEmpty);
      expect(await store.db.query('receipt_items'), isEmpty);
    });

    testWidgets(
      'income scanner uses income categories and saves after receiving-account review',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory = await tester.runAsync(
          () => Directory.systemTemp.createTemp('paxfox_income_review_'),
        );
        final source = File('${directory!.path}/payslip.pdf');
        await tester.runAsync(
          () => source.writeAsString('%PDF-1.4\nFixture\n%%EOF'),
        );
        const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          pathChannel,
          (_) async => directory.path,
        );
        addTearDown(() async {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            pathChannel,
            null,
          );
          await directory.delete(recursive: true);
        });
        final extractor = IncomeExtractor();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InvoiceScanScreen(
                        store: store,
                        type: EntryType.income,
                        autoCapture: false,
                        extractor: extractor,
                        initialImages: [source],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Extract'));
        await tester.pumpAndSettle();
        expect(extractor.categories, contains('Salary'));
        expect(extractor.categories, isNot(contains('Groceries')));
        expect(find.text('Review income'), findsOneWidget);
        expect(find.text('Net salary'), findsOneWidget);
        expect(find.text('Expense category'), findsNothing);
        await tester.tap(find.byKey(ValueKey('account-card-$blockedId')));
        await tester.runAsync(() async {
          await tester.tap(find.text('Save income'));
          await waitForStore(store, () => store.entries.isNotEmpty);
        });
        await tester.pumpAndSettle();
        expect(store.entries.single.type, EntryType.income);
        expect(store.currentBalances.byAccount[blockedId], 225000);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'income manual shortcut preselects income and returns to its Home tab',
      (tester) async {
        await tester.pumpWidget(MyApp(store: store));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add transaction'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('create-income-manual')));
        await tester.pumpAndSettle();
        expect(find.text('Income'), findsWidgets);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Description / merchant'),
          'Manual salary',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Amount'),
          '20',
        );
        await openCategoryPicker(tester);
        await tester.pumpAndSettle();
        await chooseCategory(tester, 'Salary');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('account-card-$blockedId')));
        await tester.runAsync(() async {
          await tester.tap(find.text('Save transaction'));
          await waitForStore(store, () => store.entries.isNotEmpty);
        });
        await tester.pumpAndSettle();
        expect(find.text('Manual salary'), findsOneWidget);
        expect(store.entries.single.type, EntryType.income);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
