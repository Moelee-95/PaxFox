import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/transaction_csv.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/screens/csv_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const header = 'Date,Details,Category,Cost,Notes more info\r\n';
CsvPreview decode(
  String text, {
  EntryType type = EntryType.expense,
  int account = 1,
}) => TransactionCsv.decode(utf8.encode(text), type, account);

void main() {
  test('requested format, euro amounts, reordered headers and German CSV', () {
    final row = decode('${header}1.10.26,Bank Fee,Service,€4.95,').rows.single;
    expect(row.number, 2);
    expect(row.entry.date, DateTime(2026, 10, 1));
    expect(row.entry.amount, 495);
    expect(row.entry.description, 'Bank Fee');
    expect(row.entry.notes, '');
    final german = decode(
      'Cost;Details;Date;Category;Notes more info\n'
      '€1.234,56;Bank Fee;1.10.2026;Service;Some notes',
    );
    expect(german.errors, isEmpty);
    expect(german.rows.single.entry.amount, 123456);
    expect(TransactionCsv.parseCost('EUR 1,234.56'), 123456);
    expect(TransactionCsv.parseCost('4,95 EUR'), 495);
  });

  test('UTF-8 BOM, quotes, commas and multiline notes survive export and import', () {
    final original = decode(
      '${header}1.10.26,"Bank, Fee",Service,€4.95,"First line\nSecond ""quoted"" line"',
    ).rows.single.entry;
    final output = TransactionCsv.encode([original]);
    expect(
      output,
      startsWith('\uFEFFDate,Details,Category,Cost,Notes more info'),
    );
    expect(output, contains('1.10.26'));
    final roundTrip = decode(output).rows.single.entry;
    expect(roundTrip.toMap(), original.toMap());
  });

  test(
    'field errors identify rows and reject ambiguous or malformed input',
    () {
      final preview = decode(
        '${header}31.2.26,Fee,Service,4.95,\n'
        '1.10.26,,Service,4.95,\n1.10.26,Fee,,4.95,\n'
        '1.10.26,Fee,Service,-4.95,\n1.10.26,Fee,Service,0,',
      );
      expect(preview.rows, isEmpty);
      expect(preview.errors, hasLength(5));
      expect(preview.errors[0], startsWith('Row 2: Date'));
      expect(preview.errors[1], 'Row 3: Details are required.');
      expect(preview.errors[2], 'Row 4: Category is required.');
      expect(
        () => decode('${header}1.10.26,"not closed,Service,4.95,'),
        throwsFormatException,
      );
      expect(() => decode('Date,Amount\n1.10.26,4.95'), throwsFormatException);
      expect(
        () => TransactionCsv.decode([0xff], EntryType.expense, 1),
        throwsFormatException,
      );
      expect(() => TransactionCsv.parseCost('1.234'), throwsFormatException);
      expect(
        () => decode(header, type: EntryType.transfer),
        throwsFormatException,
      );
    },
  );

  group('database and screen', () {
    late LedgerStore store;
    late int account;
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
          opening: 1000,
          asOf: DateTime(2026, 1, 1),
          kind: AccountKind.cash,
          includeOnAsOf: true,
        ),
      ]);
      account = store.accounts.single.id!;
    });
    tearDown(() async {
      await store.db.close();
      store.dispose();
    });

    testWidgets(
      'import success is visible after scrolling through a long preview',
      (tester) async {
        final text =
            header +
            List.generate(
              30,
              (i) => '1.10.26,Expense $i,Service,1.00,',
            ).join('\n');
        await tester.pumpWidget(
          MaterialApp(
            home: CsvScreen(
              store: store,
              pickFile: () async => (
                name: 'history.csv',
                bytes: Uint8List.fromList(utf8.encode(text)),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose CSV'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -700));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await tester.tap(find.text('Import transactions'));
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pumpAndSettle();
        expect(
          find.text('CSV import complete: 30 added, 0 skipped.'),
          findsOneWidget,
        );
        expect(
          find.text('Imported 30 transactions. Skipped 0 existing matches.'),
          findsOneWidget,
        );
        expect(find.text('Choose CSV').hitTestable(), findsOneWidget);
        expect(store.entries, hasLength(30));
        expect(tester.takeException(), isNull);
      },
    );

    test('unassigned history counts in spending without affecting balances and remains editable', () async {
      final rows = TransactionCsv.decode(
        utf8.encode('${header}1.10.26,Rent,Service,550.00,'),
        null,
        null,
      ).rows;
      await store.importCsv(rows);
      final e = store.entries.single;
      expect(e.type, EntryType.expense);
      expect(e.accountId, isNull);
      final totals = Totals()..add(e);
      expect(totals.spending, 55000);
      expect(
        accountBalance(
          store.accounts.single,
          store.entries,
          DateTime(2026, 12),
        ),
        1000,
      );
      await store.saveEntry(
        LedgerEntry(
          id: e.id,
          type: e.type,
          amount: 55100,
          currency: e.currency,
          date: e.date,
          description: 'Edited rent',
          category: e.category,
        ),
      );
      expect(store.entries.single.amount, 55100);
      expect(store.entries.single.accountId, isNull);
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: e.date,
            description: 'New expense',
            category: e.category,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('atomic import creates categories and repeated import skips matching occurrences', () async {
      final rows = decode(
        '${header}1.10.26,Bank Fee,Service,€4.95,\n'
        '1.10.26,Bank Fee,Service,€4.95,',
        account: account,
      ).rows;
      final saved = await store.importCsv(rows);
      expect(saved.imported, 2);
      expect(
        store
            .categoriesFor(EntryType.expense)
            .where((c) => c.name == 'Service'),
        hasLength(1),
      );
      expect(
        accountBalance(
          store.accounts.single,
          store.entries,
          DateTime(2026, 12),
        ),
        10,
      );
      final repeated = await store.importCsv(rows);
      expect(repeated.imported, 0);
      expect(repeated.skipped, 2);
      expect(store.entries, hasLength(2));
    });

    test('failure reports original CSV row and rolls back transactions and new categories', () async {
      final rows = decode(
        '${header}1.10.26,Fee,New category,4.95,\n'
        '2.10.26,Purchase,Other new category,6.00,',
        account: account,
      ).rows;
      await expectLater(
        store.importCsv(rows),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Row 3: Insufficient funds in Cash'),
          ),
        ),
      );
      expect(store.entries, isEmpty);
      expect((await store.db.query('transactions')), isEmpty);
      expect(
        (await store.db.query(
          'categories',
          where: 'name = ?',
          whereArgs: ['New category'],
        )),
        isEmpty,
      );
    });

    test('income is credited, categories are canonicalized and overdrafts stay prohibited', () async {
      final income = decode(
        '${header}1.10.26,Salary,Custom income,20.00,',
        type: EntryType.income,
        account: account,
      );
      await store.importCsv(income.rows);
      expect(
        accountBalance(
          store.accounts.single,
          store.entries,
          DateTime(2026, 12),
        ),
        3000,
      );
      final expenses = decode(
        '${header}2.10.26,Fee,Service,4.95,\n'
        '2.10.26,Fee2,service,4.95,',
        account: account,
      );
      await store.importCsv(expenses.rows);
      expect(
        store.entries
            .where((e) => e.type == EntryType.expense)
            .map((e) => e.category)
            .toSet(),
        {'Service'},
      );
      await expectLater(
        store.importCsv(
          decode('${header}3.10.26,Fee,Service,25.00,', account: account).rows,
        ),
        throwsFormatException,
      );
    });

    testWidgets(
      'file selection previews, imports and exports the chosen account/type',
      (tester) async {
        Uint8List? exported;
        await tester.pumpWidget(
          MaterialApp(
            home: CsvScreen(
              store: store,
              pickFile: () async => (
                name: 'fees.csv',
                bytes: Uint8List.fromList(
                  utf8.encode('${header}1.10.26,Bank Fee,Service,€4.95,Notes'),
                ),
              ),
              saveFile: (name, bytes) async {
                exported = bytes;
                return true;
              },
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose CSV'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(find.text('fees.csv'), findsOneWidget);
        expect(find.text('1 valid rows · €4.95'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Import transactions'));
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await tester.pumpAndSettle();
        expect(store.entries.single.description, 'Bank Fee');
        expect(store.entries.single.accountId, isNull);
        expect(
          accountBalance(
            store.accounts.single,
            store.entries,
            DateTime(2026, 12),
          ),
          1000,
        );
        expect(
          find.text('Imported 1 transactions. Skipped 0 existing matches.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Export CSV'));
        await tester.pumpAndSettle();
        expect(
          decode(utf8.decode(exported!)).rows.single.entry.description,
          'Bank Fee',
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}
