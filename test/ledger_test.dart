import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'version 1 migrates without losing ledger data and survives reopening',
    () async {
      sqfliteFfiInit();
      final directory = await Directory.systemTemp.createTemp(
        'moneva_migration_',
      );
      final path = '${directory.path}/ledger.sqlite';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT, currency TEXT, opening INTEGER, as_of TEXT, available INTEGER)',
            );
            await db.execute(
              'CREATE TABLE transactions (id INTEGER PRIMARY KEY, type TEXT, amount INTEGER, currency TEXT, date TEXT, description TEXT, category TEXT, account_id INTEGER, destination_id INTEGER, notes TEXT, created_at TEXT, updated_at TEXT)',
            );
            await db.insert('transactions', {
              'type': 'income',
              'amount': 1234,
              'currency': 'eur',
              'date': '2026-01-01',
              'description': 'Historic',
              'category': 'Salary',
              'notes': '',
              'created_at': '2026-01-01',
              'updated_at': '2026-01-01',
            });
          },
        ),
      );
      await old.close();
      final migrated = await LedgerStore.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      expect(migrated.entries.single.amount, 1234);
      expect(await migrated.db.getVersion(), 15);
      expect(migrated.setupCompleted, isFalse);
      await migrated.completeSetup([
        Account(
          name: 'Cash',
          currency: Currency.eur,
          opening: 500,
          asOf: DateTime(2026),
          kind: AccountKind.cash,
          includeOnAsOf: true,
        ),
      ]);
      expect(
        migrated.categoriesFor(EntryType.income).any((c) => c.name == 'Salary'),
        isTrue,
      );
      await migrated.db.close();
      migrated.dispose();
      final reopened = await LedgerStore.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      expect(reopened.entries.single.description, 'Historic');
      expect(reopened.setupCompleted, isTrue);
      expect(reopened.accounts.single.opening, 500);
      await reopened.db.close();
      reopened.dispose();
      await databaseFactoryFfi.deleteDatabase(path);
      await directory.delete();
    },
  );
  test('money retains exact decimal precision and rejects invalid input', () {
    expect(Currency.eur.parse('0.01'), 1);
    expect(Currency.iqd.parse('12,345'), 12345);
    expect(Currency.iqd.format(12345), '12.345');
    expect(Currency.eur.format(-1001), '-10.01');
    for (final value in ['-1', '1.001', 'NaN', '1e8', '900000000000000000']) {
      expect(() => Currency.eur.parse(value), throwsFormatException);
    }
  });
  test('refund reduces spending, transfer is excluded from totals', () {
    final totals = Totals();
    for (final type in EntryType.values) {
      totals.add(
        LedgerEntry(
          type: type,
          amount: 100,
          currency: Currency.eur,
          date: DateTime(2026),
          description: 'Test',
          category: 'Other',
        ),
      );
    }
    expect(totals.spending, 0);
    expect(totals.income, 100);
  });
  group('SQLite ledger', () {
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
          opening: 10000,
          asOf: DateTime(2026, 1, 1),
        ),
      );
      await store.addAccount(
        Account(
          name: 'Bank',
          currency: Currency.eur,
          opening: 20000,
          asOf: DateTime(2026, 1, 1),
        ),
      );
    });
    tearDown(() async {
      await store.db.close();
      store.dispose();
    });
    test('setup commits atomically once, preserves existing accounts, and accepts cash-only', () async {
      await expectLater(
        store.completeSetup([
          Account(
            name: 'Extra bank',
            currency: Currency.eur,
            opening: 0,
            asOf: DateTime(2026),
          ),
        ]),
        throwsArgumentError,
      );
      expect(store.accounts, hasLength(2));
      expect(store.setupCompleted, isFalse);
      final cash = Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 1000,
        asOf: DateTime(2026, 1, 2),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      );
      await store.completeSetup([cash]);
      await store.completeSetup([cash]);
      expect(store.accounts, hasLength(3));
      expect(store.setupCompleted, isTrue);
      expect(
        store.accounts
            .where((a) => a.kind == AccountKind.bank)
            .map((a) => a.opening),
        containsAll([10000, 20000]),
      );
      final cashAccount = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.cash,
      );
      await store.saveEntry(
        LedgerEntry(
          type: EntryType.expense,
          amount: 800,
          currency: Currency.eur,
          date: DateTime(2026, 1, 2),
          description: 'Cash payment',
          category: 'Other',
          accountId: cashAccount.id,
        ),
      );
      expect(
        accountBalance(cashAccount, store.entries, DateTime(2026, 1, 2)),
        200,
      );
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: DateTime(2026, 1, 2),
            description: 'No payment source',
            category: 'Other',
          ),
        ),
        throwsArgumentError,
      );
      expect(store.entries, hasLength(1));
    });
    test('category lists are separate and renames atomically update expense and refund history', () async {
      await store.saveCategory(kind: CategoryKind.expense, name: 'Household');
      await store.saveCategory(kind: CategoryKind.income, name: 'Household');
      for (final type in [
        EntryType.expense,
        EntryType.refund,
        EntryType.income,
      ]) {
        await store.saveEntry(
          LedgerEntry(
            type: type,
            amount: 100,
            currency: Currency.eur,
            date: DateTime(2026),
            description: type.name,
            category: 'Household',
            accountId: store.accounts.first.id,
          ),
        );
      }
      final category = store.categories.singleWhere(
        (c) => c.kind == CategoryKind.expense && c.name == 'Household',
      );
      await store.saveCategory(
        id: category.id,
        kind: category.kind,
        name: ' Home supplies ',
      );
      expect(
        store.entries
            .where((e) => e.type != EntryType.income)
            .every((e) => e.category == 'Home supplies'),
        isTrue,
      );
      expect(
        store.entries.singleWhere((e) => e.type == EntryType.income).category,
        'Household',
      );
      await expectLater(
        store.saveCategory(kind: CategoryKind.expense, name: 'HOME SUPPLIES'),
        throwsArgumentError,
      );
      await expectLater(
        store.saveCategory(kind: CategoryKind.expense, name: '   '),
        throwsArgumentError,
      );
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: DateTime(2026),
            description: 'Invalid category',
            category: 'Salary',
          ),
        ),
        throwsArgumentError,
      );
      expect(store.entries, hasLength(3));
      await store.refresh();
      expect(
        store.categories.singleWhere((c) => c.id == category.id).name,
        'Home supplies',
      );
    });
    test(
      'Default EUR currency rejects foreign transactions and accounts',
      () async {
        await expectLater(
          store.saveEntry(
            LedgerEntry(
              type: EntryType.expense,
              amount: 1000,
              currency: Currency.iqd,
              date: DateTime(2026),
              description: 'Legacy currency',
              category: 'Other',
            ),
          ),
          throwsArgumentError,
        );
        await expectLater(
          store.addAccount(
            Account(
              name: 'Foreign account',
              currency: Currency.iqd,
              opening: 0,
              asOf: DateTime(2026),
            ),
          ),
          throwsArgumentError,
        );
        expect(store.entries, isEmpty);
        expect(store.accounts.every((a) => a.currency == Currency.eur), isTrue);
      },
    );
    test('legacy non-EUR data remains unchanged and is excluded from active EUR data', () async {
      await store.db.insert(
        'accounts',
        Account(
          name: 'Legacy',
          currency: Currency.iqd,
          opening: 123456,
          asOf: DateTime(2026),
        ).toMap(),
      );
      await store.db.insert('transactions', {
        ...LedgerEntry(
          type: EntryType.expense,
          amount: 123456,
          currency: Currency.iqd,
          date: DateTime(2026),
          description: 'Legacy',
          category: 'Other',
        ).toMap(),
        'created_at': '2026-01-01',
        'updated_at': '2026-01-01',
      });
      await store.refresh();
      expect(store.hasLegacyCurrencyData, isTrue);
      expect(store.entries, isEmpty);
      expect(store.accounts.every((a) => a.currency == Currency.eur), isTrue);
      final original = (await store.db.query('transactions')).single;
      expect(original['currency'], 'iqd');
      expect(original['amount'], 123456);
      expect(
        (await store.db.query(
          'accounts',
          where: "currency = 'iqd'",
        )).single['opening'],
        123456,
      );
    });
    test('transfer conserves balance, snapshot excludes same-day and future entries', () async {
      final source = store.accounts.first, destination = store.accounts.last;
      for (final date in [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2027),
      ]) {
        await store.saveEntry(
          LedgerEntry(
            type: EntryType.transfer,
            amount: 500,
            currency: Currency.eur,
            date: date,
            description: 'Transfer',
            category: 'Transfer',
            accountId: source.id,
            destinationId: destination.id,
          ),
        );
      }
      final first = accountBalance(source, store.entries, DateTime(2026, 1, 3));
      final second = accountBalance(
        destination,
        store.entries,
        DateTime(2026, 1, 3),
      );
      expect(first, source.opening - 500);
      expect(second, destination.opening + 500);
      expect(first + second, 30000);
    });
    test('rejects missing accounts, mixed currencies and same-account transfers atomically', () async {
      for (final entry in [
        LedgerEntry(
          type: EntryType.expense,
          amount: 100,
          currency: Currency.iqd,
          date: DateTime(2026),
          description: 'Test',
          category: 'Other',
          accountId: store.accounts.first.id,
        ),
        LedgerEntry(
          type: EntryType.transfer,
          amount: 100,
          currency: Currency.eur,
          date: DateTime(2026),
          description: 'Test',
          category: 'Other',
          accountId: store.accounts.first.id,
          destinationId: store.accounts.first.id,
        ),
        LedgerEntry(
          type: EntryType.expense,
          amount: 100,
          currency: Currency.eur,
          date: DateTime(2026),
          description: 'Test',
          category: 'Other',
          accountId: 999,
        ),
      ]) {
        await expectLater(store.saveEntry(entry), throwsArgumentError);
      }
      expect(await store.db.query('transactions'), isEmpty);
    });
    test(
      'updates keep identity and timestamps and deletion persists',
      () async {
        await store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: DateTime(2026),
            description: 'Test',
            category: 'Other',
            accountId: store.accounts.first.id,
          ),
        );
        final id = store.entries.single.id;
        final created = (await store.db.query('transactions'))
            .single['created_at'];
        await store.saveEntry(
          LedgerEntry(
            id: id,
            type: EntryType.refund,
            amount: 50,
            currency: Currency.eur,
            date: DateTime(2026),
            description: 'Return',
            category: 'Other',
          ),
        );
        expect(store.entries.single.id, id);
        expect(
          (await store.db.query('transactions')).single['created_at'],
          created,
        );
        await store.deleteEntry(id!);
        await store.refresh();
        expect(store.entries, isEmpty);
      },
    );
  });
}
