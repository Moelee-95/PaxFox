import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/transaction_csv.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final currency in Currency.values) {
    test(
      '${currency.code} setup, debt, invoice, CSV and recurrence use minor units',
      () async {
        final store = await LedgerStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        );
        addTearDown(() async {
          await store.db.close();
          store.dispose();
        });
        final today = dateOnly(DateTime.now());
        final starting = currency.parse('100');
        await store.completeSetup(
          [
            Account(
              name: 'Cash',
              currency: currency,
              opening: starting,
              asOf: today,
              kind: AccountKind.cash,
              includeOnAsOf: true,
            ),
          ],
          selectedCurrency: currency,
          initialDebts: [
            Debt(
              name: 'Bank loan',
              amount: currency.parse('20'),
              currency: currency,
            ),
          ],
        );
        expect(store.currency, currency);
        expect(store.netWealth, currency.parse('80'));
        expect(store.currentBalances.available, starting);
        await store.completeSetup([], selectedCurrency: currency);
        expect(store.debts, hasLength(1));
        final debt = store.debts.single;
        expect(debt.createdAt!.isUtc, isTrue);
        await store.saveDebt(
          Debt(id: debt.id, name: debt.name, amount: 0, currency: currency),
        );
        expect(store.debts.single.createdAt, debt.createdAt);
        expect(store.netWealth, starting);
        await store.deleteDebt(debt.id!);
        expect(store.debts, isEmpty);

        final price = currency == Currency.iqd ? '1.123' : '1.23';
        final draft = parseInvoice(
          jsonEncode({
            'merchant': 'Shop',
            'date': dayKey(today),
            'currency': currency.code,
            'total': price,
            'category': 'Groceries',
            'items': [
              {
                'description': 'Milk',
                'quantity': '1',
                'line_total': price,
                'category': 'Groceries',
              },
            ],
          }),
          {'Groceries'},
          currency: currency,
        );
        await store.saveInvoiceBatch(
          draft: draft,
          accountId: store.accounts.single.id!,
          imagePaths: [],
        );
        expect(store.entries.single.currency, currency);
        expect(store.entries.single.amount, currency.parse(price));
        final exported = TransactionCsv.encode(store.entries);
        final preview = TransactionCsv.decode(
          utf8.encode(exported),
          EntryType.expense,
          store.accounts.single.id,
          currency: currency,
        );
        expect(preview.errors, isEmpty);
        expect(preview.rows.single.entry.amount, currency.parse(price));
        expect(preview.rows.single.entry.currency, currency);
        final wrong = currency == Currency.eur ? Currency.usd : Currency.eur;
        expect(
          () =>
              TransactionCsv.parseCost(wrong.display(100), currency: currency),
          throwsFormatException,
        );

        await store.saveRecurring(
          RecurringRule(
            description: 'Salary',
            amount: currency.parse('10'),
            type: EntryType.income,
            category: 'Salary',
            accountId: store.accounts.single.id!,
            day: today.day,
            nextDate: today,
          ),
        );
        expect(
          store.entries
              .singleWhere((entry) => entry.description == 'Salary')
              .currency,
          currency,
        );
        expect(
          store.monthSummary(today).totalsFor(currency).income,
          currency.parse('10'),
        );
        await store.refresh();
        expect(store.currency, currency);
      },
    );
  }

  test(
    'invalid setup debt cannot leave accounts or currency partially committed',
    () async {
      final store = await LedgerStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(() async {
        await store.db.close();
        store.dispose();
      });
      await expectLater(
        store.completeSetup(
          [
            Account(
              name: 'Cash',
              currency: Currency.usd,
              opening: 0,
              asOf: DateTime(2026),
              kind: AccountKind.cash,
            ),
          ],
          selectedCurrency: Currency.usd,
          initialDebts: [
            const Debt(name: '', amount: 10, currency: Currency.usd),
          ],
        ),
        throwsArgumentError,
      );
      expect(store.accounts, isEmpty);
      expect(store.setupCompleted, isFalse);
      expect(
        await store.db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['app_currency'],
        ),
        isEmpty,
      );
    },
  );

  test('v11 upgrade retains receipt links, timestamps, policies and legacy currencies', () async {
    final dir = await Directory.systemTemp.createTemp('moneva_v11_');
    final path = '${dir.path}/test.sqlite';
    final old = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
    final day = DateTime(2026, 1, 1);
    await old.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 5000,
        asOf: day,
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
    await old.saveInvoiceBatch(
      draft: InvoiceDraft(
        merchant: 'Shop',
        date: day,
        currency: 'EUR',
        total: 100,
        category: 'Groceries',
        items: const [
          InvoiceItem(
            description: 'Milk',
            quantity: '1',
            total: 100,
            category: 'Groceries',
          ),
        ],
      ),
      accountId: old.accounts.single.id!,
      imagePaths: [],
    );
    final entry = old.entries.single;
    await old.db.insert(
      'accounts',
      Account(
        name: 'Legacy',
        currency: Currency.iqd,
        opening: 123456,
        asOf: day,
      ).toMap(),
    );
    // Reconstruct the v11 CHECK constraints and remove v12 additions.
    await old.db.execute('PRAGMA foreign_keys = OFF');
    for (final table in ['accounts', 'transactions']) {
      final sql =
          (await old.db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE name = ?",
                [table],
              )).single['sql']
              as String;
      await old.db.execute(
        sql
            .replaceFirst(
              RegExp('CREATE TABLE ["`]?$table["`]?'),
              'CREATE TABLE ${table}_old',
            )
            .replaceAll("'eur','iqd','usd','gbp'", "'eur','iqd'"),
      );
      await old.db.execute('INSERT INTO ${table}_old SELECT * FROM $table');
      await old.db.execute('DROP TABLE $table');
      await old.db.execute('ALTER TABLE ${table}_old RENAME TO $table');
    }
    await old.db.execute('ALTER TABLE receipt_items DROP COLUMN item_date');
    await old.db.execute('DROP TABLE debts');
    await old.db.execute('ALTER TABLE categories DROP COLUMN color');
    await old.db.setVersion(11);
    await old.db.close();
    old.dispose();
    final migrated = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await migrated.db.getVersion(), 13);
      expect(migrated.currency, Currency.eur);
      expect(migrated.entries.single.id, entry.id);
      expect(migrated.entries.single.createdAt, entry.createdAt);
      expect(await migrated.scannedInvoiceFor(entry.id!), isNotNull);
      expect(migrated.accounts.single.includeOnAsOf, isTrue);
      expect(migrated.currentBalances.wealth, 4900);
      expect(
        (await migrated.db.query(
          'accounts',
          where: 'currency = ?',
          whereArgs: ['iqd'],
        )).single['opening'],
        123456,
      );
      expect(await migrated.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await migrated.db.rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1,
      );
      await migrated.deleteEntry(entry.id!);
      expect(await migrated.db.query('scanned_invoice_entries'), isEmpty);
      expect(await migrated.db.query('receipt_items'), isEmpty);
    } finally {
      await migrated.db.close();
      migrated.dispose();
      await databaseFactoryFfi.deleteDatabase(path);
      await dir.delete();
    }
  });
}
