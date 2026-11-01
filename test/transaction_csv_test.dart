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

Future<void> selectCsvCard(
  WidgetTester tester,
  String prefix,
  String value,
) async {
  if (prefix == 'csv-type') {
    if (value == 'all') return; // Legacy fixture assigns its one type in one apply.
    await tester.tap(find.byKey(const ValueKey('csv-type-picker')));
    await tester.pumpAndSettle();
    if (find.text('All types').evaluate().isNotEmpty &&
        tester.widget<ListTile>(find.byKey(const ValueKey('entry-type-all'))).selected && value == 'expense') {
      await tester.tap(find.byKey(const ValueKey('entry-type-all')));
    }
    await tester.tap(find.byKey(ValueKey('entry-type-$value')));
    await tester.tap(find.text('Apply types'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pumpAndSettle();
    return;
  }
  final row = find.byKey(ValueKey('$prefix-options'));
  final scrollable = find.descendant(
    of: row,
    matching: find.byType(Scrollable),
  );
  final card = find.byKey(ValueKey('$prefix-$value'));
  // Return to the start to support toggling cards in either direction.
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(card, 120, scrollable: scrollable);
  await tester.tap(card);
  await tester.pump();
  for (
    var i = 0;
    i < 100 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    i++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> legacyDefaults(WidgetTester tester) async {
  await selectCsvCard(tester, 'csv-account', 'all');
  await selectCsvCard(tester, 'csv-account', 'unassigned');
  await selectCsvCard(tester, 'csv-type', 'all');
  await selectCsvCard(tester, 'csv-type', 'expense');
}

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

  test('account-aware files validate names, types, currency and both transfer accounts', () {
    final accounts = [
      Account(
        id: 1,
        name: 'Cash',
        currency: Currency.eur,
        opening: 0,
        asOf: DateTime(2026),
      ),
      Account(
        id: 2,
        name: 'Bank',
        currency: Currency.eur,
        opening: 0,
        asOf: DateTime(2026),
      ),
    ];
    final columns = '${TransactionCsv.accountHeaders.join(',')}\n';
    CsvPreview parse(String row, {List<Account>? choices}) =>
        TransactionCsv.decode(
          utf8.encode('$columns$row'),
          null,
          null,
          accounts: choices ?? accounts,
        );
    final valid = parse('1.10.26,Move,,1.00,, cash ,TRANSFER,Bank,eur');
    expect(valid.errors, isEmpty);
    expect(valid.rows.single.entry.destinationId, 2);
    expect(valid.rows.single.entry.category, 'Transfer');
    for (final data in [
      ('Missing,expense,,EUR', 'not found'),
      ('Cash,other,,EUR', 'Type must'),
      ('Cash,expense,,USD', 'Currency must be EUR'),
      ('Cash,transfer,Cash,EUR', 'two different accounts'),
      ('Cash,transfer,,EUR', 'two different accounts'),
      ('Cash,expense,Bank,EUR', 'Only transfers'),
    ]) {
      final invalid = parse('1.10.26,Fee,Service,1.00,,${data.$1}');
      expect(invalid.rows, isEmpty);
      expect(
        invalid.errors.single,
        allOf(startsWith('Row 2:'), contains(data.$2)),
      );
    }
    final duplicate = [
      ...accounts,
      Account(
        id: 3,
        name: 'cash',
        currency: Currency.eur,
        opening: 0,
        asOf: DateTime(2026),
      ),
    ];
    expect(
      parse(
        '1.10.26,Fee,Service,1.00,,Cash,expense,,EUR',
        choices: duplicate,
      ).errors.single,
      contains('ambiguous'),
    );
    expect(
      () =>
          TransactionCsv.encode([valid.rows.single.entry], accounts: duplicate),
      throwsFormatException,
    );
    expect(
      () => TransactionCsv.decode(
        utf8.encode(columns.replaceFirst('Currency', 'Type')),
        null,
        null,
        accounts: accounts,
      ),
      throwsFormatException,
    );
  });

  test('account-aware exports retain currency precision, names and notes', () {
    for (final currency in Currency.values) {
      final account = Account(
        id: 7,
        name: 'Bank, savings',
        currency: currency,
        opening: 0,
        asOf: DateTime(2026),
      );
      final original = LedgerEntry(
        type: EntryType.income,
        amount: currency.parse(currency == Currency.iqd ? '1.234' : '1.23'),
        currency: currency,
        date: DateTime(2026, 10, 1),
        description: 'Pay',
        category: 'Salary',
        accountId: 7,
        notes: 'Line 1\nLine 2',
      );
      final preview = TransactionCsv.decode(
        utf8.encode(TransactionCsv.encode([original], accounts: [account])),
        null,
        null,
        accounts: [account],
        currency: currency,
      );
      expect(preview.errors, isEmpty);
      expect(preview.rows.single.entry.toMap(), original.toMap());
    }
  });

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

    Future<List<LedgerEntry>> mixedEntries() async {
      await store.addAccount(
        Account(
          name: 'Bank',
          currency: Currency.eur,
          opening: 0,
          asOf: DateTime(2026, 1, 1),
          includeOnAsOf: true,
        ),
      );
      final bank = store.accounts.firstWhere((a) => a.name == 'Bank').id;
      LedgerEntry row(
        EntryType type,
        int amount,
        String description,
        int? id, {
        int? destination,
      }) => LedgerEntry(
        type: type,
        amount: amount,
        currency: Currency.eur,
        date: DateTime(2026, 10, 1),
        description: description,
        category: type == EntryType.transfer ? 'Transfer' : 'CSV category',
        accountId: id,
        destinationId: destination,
      );
      return [
        row(EntryType.expense, 2500, 'Purchase', account),
        row(EntryType.transfer, 400, 'Move funds', account, destination: bank),
        row(EntryType.income, 2000, 'Salary', account),
        row(EntryType.refund, 100, 'Return', account),
        row(EntryType.expense, 30, 'Old history', null),
        row(EntryType.expense, 100, 'Bank fee', bank),
      ];
    }

    test(
      'one CSV round-trips accounts, all types, transfers and repeated imports',
      () async {
        final entries = await mixedEntries();
        final csv = TransactionCsv.encode(entries, accounts: store.accounts);
        final preview = TransactionCsv.decode(
          utf8.encode(csv),
          null,
          null,
          accounts: store.accounts,
        );
        expect(preview.hasAssignments, isTrue);
        expect(preview.errors, isEmpty);
        expect(
          preview.rows.map((r) => r.entry.toMap()),
          entries.map((e) => e.toMap()),
        );
        final result = await store.importCsv(preview.rows);
        expect(result.imported, 6);
        expect(store.currentBalances.byAccount[account], 200);
        final bank = store.accounts.firstWhere((a) => a.name == 'Bank');
        expect(store.currentBalances.byAccount[bank.id], 300);
        expect(
          store.entries.where((e) => e.type == EntryType.transfer),
          hasLength(1),
        );
        expect(
          store
              .categoriesFor(EntryType.expense)
              .any((c) => c.name == 'Transfer'),
          isFalse,
        );
        final repeated = await store.importCsv(preview.rows);
        expect(repeated.imported, 0);
        expect(repeated.skipped, 6);
        expect(store.entries, hasLength(6));
      },
    );

    test(
      'a later income cannot cover an earlier deficit in a mixed batch',
      () async {
        final entries = await mixedEntries();
        final expense = entries.first;
        final rows = [
          CsvTransactionRow(number: 2, entry: expense),
          CsvTransactionRow(
            number: 3,
            entry: LedgerEntry(
              type: EntryType.income,
              amount: 3000,
              currency: Currency.eur,
              date: DateTime(2026, 10, 2),
              description: 'Later salary',
              category: 'New salary',
              accountId: account,
            ),
          ),
        ];
        await expectLater(store.importCsv(rows), throwsFormatException);
        expect(store.entries, isEmpty);
        expect(await store.db.query('transactions'), isEmpty);
        expect(
          store.categories.any(
            (c) => c.name == expense.category || c.name == 'New salary',
          ),
          isFalse,
        );
        expect(store.currentBalances.byAccount[account], 1000);
      },
    );

    test(
      'mixed imports reject blocked outgoing transfers atomically',
      () async {
        await store.addAccount(
          Account(
            name: 'Blocked',
            currency: Currency.eur,
            opening: 5000,
            asOf: DateTime(2026, 1, 1),
            includeOnAsOf: true,
            available: false,
          ),
        );
        final blocked = store.accounts
            .firstWhere((a) => a.name == 'Blocked')
            .id;
        final rows = [
          CsvTransactionRow(
            number: 2,
            entry: LedgerEntry(
              type: EntryType.income,
              amount: 1000,
              currency: Currency.eur,
              date: DateTime(2026, 10, 1),
              description: 'Credit',
              category: 'CSV credit',
              accountId: account,
            ),
          ),
          CsvTransactionRow(
            number: 3,
            entry: LedgerEntry(
              type: EntryType.transfer,
              amount: 100,
              currency: Currency.eur,
              date: DateTime(2026, 10, 1),
              description: 'Blocked transfer',
              category: 'Transfer',
              accountId: blocked,
              destinationId: account,
            ),
          ),
        ];
        await expectLater(
          store.importCsv(rows),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Row 3: This account is blocked'),
            ),
          ),
        );
        expect(store.entries, isEmpty);
        expect(store.categories.any((c) => c.name == 'CSV credit'), isFalse);
      },
    );

    testWidgets(
      'multiple account/type buttons export and filter a single CSV',
      (tester) async {
        await tester.runAsync(() async {
          final entries = await mixedEntries();
          await store.importCsv([
            for (var i = 0; i < entries.length; i++)
              CsvTransactionRow(number: i + 2, entry: entries[i]),
          ]);
        });
        Uint8List? exported;
        Uint8List? importBytes;
        await tester.pumpWidget(
          MaterialApp(
            home: CsvScreen(
              store: store,
              saveFile: (name, bytes) async {
                exported = bytes;
                return true;
              },
              pickFile: () async => (name: 'mixed.csv', bytes: importBytes!),
            ),
          ),
        );
        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        await selectCsvCard(tester, 'csv-account', 'unassigned');
        await selectCsvCard(tester, 'csv-type', 'refund');
        await tester.runAsync(
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Export CSV'),
                  )
                  .onPressed!
              as Future<void> Function(),
        );
        await tester.pumpAndSettle();
        importBytes = exported;
        final output = TransactionCsv.decode(
          exported!,
          null,
          null,
          accounts: store.accounts,
        );
        expect(output.errors, isEmpty);
        expect(output.rows, hasLength(4));
        expect(output.rows.map((r) => r.entry.type).toSet(), {
          EntryType.expense,
          EntryType.income,
          EntryType.transfer,
        });
        final bank = store.accounts.firstWhere((a) => a.name == 'Bank').id!;
        await selectCsvCard(tester, 'csv-account', '$account');
        await tester.runAsync(
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Export CSV'),
                  )
                  .onPressed!
              as Future<void> Function(),
        );
        await tester.pumpAndSettle();
        final bankOnly = TransactionCsv.decode(
          exported!,
          null,
          null,
          accounts: store.accounts,
        );
        expect(bankOnly.rows.map((r) => r.entry.description).toSet(), {
          'Bank fee',
          'Move funds',
        });
        await selectCsvCard(tester, 'csv-account', '$account');
        expect(output.rows.map((r) => r.entry.accountId).toSet(), {
          account,
          bank,
        });
        // Filtering out Bank excludes its expense, but keeps Cash's transfer intact.
        await selectCsvCard(tester, 'csv-account', '$bank');
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose CSV'));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('3 valid rows'), findsOneWidget);
        await selectCsvCard(tester, 'csv-type', 'expense');
        expect(find.textContaining('2 valid rows'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Import transactions'));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(
          find.text('Imported 0 transactions. Skipped 2 existing matches.'),
          findsOneWidget,
        );
        expect(store.entries, hasLength(6));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'older files require one explicit account and type assignment',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: CsvScreen(
              store: store,
              pickFile: () async => (
                name: 'older.csv',
                bytes: Uint8List.fromList(
                  utf8.encode('${header}1.10.26,Fee,Service,1.00,'),
                ),
              ),
            ),
          ),
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('Choose CSV'));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(
          find.textContaining('This older CSV has no account or type columns.'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Import transactions'),
              )
              .onPressed,
          isNull,
        );
        await legacyDefaults(tester);
        expect(find.textContaining('1 valid rows'), findsOneWidget);
        expect(
          find.textContaining('This older CSV has no account or type columns.'),
          findsNothing,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Import transactions'),
              )
              .onPressed,
          isNotNull,
        );
        expect(store.entries, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

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
        await legacyDefaults(tester);
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
        await legacyDefaults(tester);
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
        await tester.runAsync(
          tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Export CSV'),
                  )
                  .onPressed!
              as Future<void> Function(),
        );
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
