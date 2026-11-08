import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/transaction_csv.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  final day = DateTime(2026, 1, 2);
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Euro bank',
        currency: Currency.eur,
        opening: 10000,
        asOf: DateTime(2026),
        includeOnAsOf: true,
      ),
    );
    await store.addAccount(
      Account(
        name: 'IQD bank',
        currency: Currency.iqd,
        baseCurrency: Currency.eur,
        exchangeRate: '1772',
        opening: Currency.iqd.parse('177200'),
        asOf: DateTime(2026),
        includeOnAsOf: true,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Account getBank(String name) =>
      store.accounts.firstWhere((a) => a.name == name);
  LedgerEntry input({
    EntryType type = EntryType.expense,
    Currency currency = Currency.eur,
    String amount = '2',
    int? destination,
    int? received,
    String bank = 'IQD bank',
  }) => store.entryFromInput(
    type: type,
    inputAmount: currency.parse(amount),
    inputCurrency: currency,
    date: day,
    description: 'Synthetic FX entry',
    category: type == EntryType.income
        ? store.categoriesFor(type).first.name
        : type == EntryType.transfer
        ? 'Transfer'
        : store.categoriesFor(EntryType.expense).first.name,
    accountId: getBank(bank).id,
    destinationId: destination,
    receivedAmount: received,
  );
  Account revise(
    Account old, {
    Currency? currency,
    String? rate,
    int? opening,
  }) => Account(
    id: old.id,
    name: old.name,
    currency: currency ?? old.currency,
    baseCurrency: Currency.eur,
    exchangeRate: rate ?? old.exchangeRate,
    opening: opening ?? old.opening,
    asOf: old.asOf,
    available: old.available,
    kind: old.kind,
    includeOnAsOf: old.includeOnAsOf,
    allowOverdraft: old.allowOverdraft,
  );

  test('grouped rates and conversions use exact minor units and symmetric rounding', () {
    final rate = ExchangeRate.parse('1,772');
    expect(rate.value, '1772');
    expect(rate.fromBase(200, 100, 1000), 3544000);
    expect(rate.toBase(3544000, 1000, 100), 200);
    expect(ExchangeRate.parse('2').toBase(1, 100, 100), 1);
    expect(ExchangeRate.parse('2').toBase(-1, 100, 100), -1);
    for (final invalid in ['0', '-1', 'NaN', '1.0000000001', '1e3']) {
      expect(() => ExchangeRate.parse(invalid), throwsFormatException);
    }
  });

  test('euro expense deducts IQD and native income reports euros', () async {
    final bank = getBank('IQD bank');
    expect(store.currentBalances.wealth, 20000);
    await store.saveEntry(input());
    expect(
      store.currentBalances.byAccount[bank.id],
      Currency.iqd.parse('173656'),
    );
    expect(store.entries.single.amount, 200);
    expect(store.entries.single.accountAmount, Currency.iqd.parse('3544'));
    await store.saveEntry(
      input(type: EntryType.income, currency: Currency.iqd, amount: '1772'),
    );
    expect(
      store.currentBalances.byAccount[bank.id],
      Currency.iqd.parse('175428'),
    );
    expect(store.monthSummary(day).eurTotals.income, 100);
    expect(store.monthSummary(day).eurTotals.spending, 200);
  });

  test('new rate revalues current wealth but freezes posted values and native movements', () async {
    await store.saveEntry(input());
    final entry = store.entries.single;
    await store.updateAccount(revise(getBank('IQD bank'), rate: '1800'));
    expect(store.entries.single.amount, 200);
    expect(store.entries.single.fx!.sourceRate, '1772');
    expect(
      store.currentBalances.byAccount[entry.accountId],
      Currency.iqd.parse('173656'),
    );
    expect(store.currentBalances.wealth, 10000 + 9648);
    await store.saveEntry(
      LedgerEntry.fromMap({
        ...entry.toMap(),
        'id': entry.id,
        'description': 'Renamed',
      }),
    );
    expect(store.entries.single.accountAmount, Currency.iqd.parse('3544'));
    expect(store.entries.single.amount, 200);
    await store.saveEntry(input(amount: '1'));
    expect(
      store.entries.firstWhere((e) => e.id != entry.id).accountAmount,
      Currency.iqd.parse('1800'),
    );
    await store.refresh();
    expect(getBank('IQD bank').exchangeRate, '1800');
  });

  test('switching an existing account converts balance and effects, preserves reports, permits correction', () async {
    await store.saveEntry(input(bank: 'Euro bank'));
    final old = getBank('Euro bank');
    await store.updateAccount(
      revise(old, currency: Currency.iqd, rate: '1772'),
      currentBalance: Currency.iqd.parse('173656'),
    );
    expect(
      store.currentBalances.byAccount[old.id],
      Currency.iqd.parse('173656'),
    );
    expect(store.entries.single.amount, 200);
    await store.updateAccount(revise(getBank('Euro bank'), rate: '1800'));
    expect(
      store.currentBalances.byAccount[old.id],
      Currency.iqd.parse('173656'),
    );
    expect(store.entries.single.accountAmount, Currency.iqd.parse('3544'));
    await store.updateAccount(
      revise(getBank('Euro bank')),
      currentBalance: Currency.iqd.parse('180000'),
    );
    expect(
      store.currentBalances.byAccount[old.id],
      Currency.iqd.parse('180000'),
    );
    expect(store.entries.single.amount, 200);
    await store.updateAccount(
      revise(getBank('Euro bank'), currency: Currency.eur, rate: '1'),
      currentBalance: 10000,
    );
    expect(store.currentBalances.byAccount[old.id], 10000);
    expect(store.entries.single.amount, 200);
  });

  test('cross-currency transfer uses supplied pair and history retains its actual rate', () async {
    final euro = getBank('Euro bank');
    final entry = input(
      type: EntryType.transfer,
      currency: Currency.iqd,
      amount: '17720',
      destination: euro.id,
      received: 950,
    );
    await store.saveEntry(entry);
    expect(
      store.currentBalances.byAccount[getBank('IQD bank').id],
      Currency.iqd.parse('159480'),
    );
    expect(store.currentBalances.byAccount[euro.id], 10950);
    expect(store.entries.single.fx!.transferRate, '1 IQD = 0.000536117 EUR');
    expect(store.monthSummary(day).eurTotals.income, 0);
    expect(store.monthSummary(day).eurTotals.spending, 0);
    await store.updateAccount(revise(getBank('IQD bank'), rate: '1900'));
    expect(store.entries.single.fx!.targetAmount, 950);
    expect(store.entries.single.fx!.sourceAmount, Currency.iqd.parse('17720'));
    await store.deleteEntry(store.entries.single.id!);
    expect(store.currentBalances.byAccount[euro.id], 10000);
    expect(
      store.currentBalances.byAccount[getBank('IQD bank').id],
      Currency.iqd.parse('177200'),
    );
  });

  test('cross-currency transfers require explicit received amount', () {
    expect(
      () =>
          input(type: EntryType.transfer, destination: getBank('Euro bank').id),
      throwsArgumentError,
    );
  });

  test('native overdraw protection rolls back writes and updates', () async {
    await expectLater(
      store.saveEntry(input(currency: Currency.iqd, amount: '200000')),
      throwsArgumentError,
    );
    expect(store.entries, isEmpty);
    expect(
      store.currentBalances.byAccount[getBank('IQD bank').id],
      Currency.iqd.parse('177200'),
    );
    await store.saveEntry(input());
    final original = store.entries.single;
    final revised = store.entryFromInput(
      id: original.id,
      type: EntryType.expense,
      inputAmount: Currency.iqd.parse('200000'),
      inputCurrency: Currency.iqd,
      date: day,
      description: 'Too large',
      category: original.category,
      accountId: original.accountId,
    );
    await expectLater(store.saveEntry(revised), throwsArgumentError);
    expect(store.entries.single.amount, 200);
  });

  test(
    'blocked foreign accounts receive income but cannot fund expenses',
    () async {
      final old = getBank('IQD bank');
      await store.updateAccount(
        Account(
          id: old.id,
          name: old.name,
          currency: old.currency,
          baseCurrency: Currency.eur,
          exchangeRate: old.exchangeRate,
          opening: old.opening,
          asOf: old.asOf,
          includeOnAsOf: true,
          available: false,
        ),
      );
      await expectLater(store.saveEntry(input()), throwsArgumentError);
      await store.saveEntry(
        input(type: EntryType.income, currency: Currency.iqd, amount: '1772'),
      );
      expect(store.currentBalances.available, 10000);
      expect(store.currentBalances.wealth, 20100);
    },
  );

  test(
    'native recurring amounts use rate at each posting and do not repost',
    () async {
      final bank = getBank('IQD bank');
      await store.saveRecurring(
        RecurringRule(
          description: 'IQD income',
          type: EntryType.income,
          currency: Currency.iqd,
          amount: Currency.iqd.parse('1772'),
          category: store.categoriesFor(EntryType.income).first.name,
          accountId: bank.id!,
          day: 2,
          nextDate: day,
        ),
        today: day,
      );
      expect(store.entries.single.amount, 100);
      await store.updateAccount(revise(getBank('IQD bank'), rate: '1800'));
      await store.processRecurring(today: DateTime(2026, 2, 2));
      expect(store.entries.map((e) => e.amount).toSet(), {100, 98});
      expect(
        store.entries.every(
          (e) => e.accountAmount == Currency.iqd.parse('1772'),
        ),
        isTrue,
      );
      await store.processRecurring(today: DateTime(2026, 2, 2));
      expect(store.entries.length, 2);
    },
  );

  test(
    'euro recurring amounts debit native units at the current rate',
    () async {
      await store.saveRecurring(
        RecurringRule(
          description: 'Euro payment',
          amount: 200,
          currency: Currency.eur,
          category: store.categoriesFor(EntryType.expense).first.name,
          accountId: getBank('IQD bank').id!,
          day: 2,
          nextDate: day,
        ),
        today: day,
      );
      expect(store.entries.single.accountAmount, Currency.iqd.parse('3544'));
      await store.updateAccount(revise(getBank('IQD bank'), rate: '1800'));
      await store.processRecurring(today: DateTime(2026, 2, 2));
      expect(store.entries.map((e) => e.amount).toSet(), {200});
      expect(store.entries.map((e) => e.accountAmount).toSet(), {
        3544000,
        3600000,
      });
    },
  );

  test(
    'FX CSV round-trips snapshots and skips duplicates even after rate changes',
    () async {
      await store.saveEntry(input());
      await store.saveEntry(
        input(
          type: EntryType.transfer,
          currency: Currency.iqd,
          amount: '17720',
          destination: getBank('Euro bank').id,
          received: 950,
        ),
      );
      final csv = TransactionCsv.encode(
        store.entries,
        accounts: store.accounts,
      );
      expect(csv, contains('FX details'));
      await store.updateAccount(revise(getBank('IQD bank'), rate: '1800'));
      final preview = TransactionCsv.decode(
        utf8.encode(csv),
        null,
        null,
        accounts: store.accounts,
      );
      expect(preview.errors, isEmpty);
      final result = await store.importCsv(preview.rows);
      expect(result, (imported: 0, skipped: 2));
      final original = store.entries.map((e) => e.toMap()).toList();
      await store.deleteEntries(store.entries.map((e) => e.id!).toSet());
      await store.importCsv(preview.rows);
      expect(
        store.entries.map((e) => e.toMap()).toList(),
        unorderedEquals(original),
      );
    },
  );

  test(
    'unpaid native recurrence retries at the current rate exactly once',
    () async {
      final bank = getBank('IQD bank');
      await store.saveRecurring(
        RecurringRule(
          description: 'Large native payment',
          amount: Currency.iqd.parse('223000'),
          currency: Currency.iqd,
          category: store.categoriesFor(EntryType.expense).first.name,
          accountId: bank.id!,
          day: 2,
          nextDate: day,
        ),
        today: day,
      );
      expect(store.entries, isEmpty);
      final occurrence = store.recurringOccurrences.single;
      expect(occurrence.status, 'failed');
      expect(occurrence.currency, Currency.iqd);
      await store.updateAccount(
        revise(bank, rate: '2000'),
        currentBalance: Currency.iqd.parse('300000'),
      );
      await store.retryRecurring(occurrence.id, paidOn: DateTime(2026, 1, 3));
      expect(store.entries.single.amount, 11150);
      expect(store.entries.single.accountAmount, Currency.iqd.parse('223000'));
      expect(
        store.currentBalances.byAccount[bank.id],
        Currency.iqd.parse('77000'),
      );
      await store.retryRecurring(occurrence.id, paidOn: DateTime(2026, 1, 3));
      expect(store.entries.length, 1);
    },
  );

  test('bulk reassignment preserves reports and recomputes the new native movement', () async {
    await store.saveEntry(input());
    final id = store.entries.single.id!;
    await store.updateEntries(
      {id},
      accountId: getBank('Euro bank').id,
      changeAccount: true,
    );
    expect(store.entries.single.amount, 200);
    expect(store.entries.single.accountAmount, 200);
    expect(
      store.currentBalances.byAccount[getBank('IQD bank').id],
      Currency.iqd.parse('177200'),
    );
    await store.updateAccount(revise(getBank('IQD bank'), rate: '1800'));
    await store.updateEntries(
      {id},
      accountId: getBank('IQD bank').id,
      changeAccount: true,
    );
    expect(store.entries.single.amount, 200);
    expect(store.entries.single.accountAmount, Currency.iqd.parse('3600'));
  });

  test('v13 migration retains ledger, recurring, settings and excluded legacy currencies on reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paxfox_fx_migration_',
    );
    final path = '${directory.path}/ledger.sqlite';
    final old = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
    await old.addAccount(
      Account(
        name: 'Existing bank',
        currency: Currency.eur,
        opening: 10000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    final accountId = old.accounts.single.id!;
    await old.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 200,
        currency: Currency.eur,
        date: day,
        description: 'Before upgrade',
        category: old.categoriesFor(EntryType.expense).first.name,
        accountId: accountId,
      ),
    );
    await old.saveRecurring(
      RecurringRule(
        description: 'Existing schedule',
        amount: 100,
        category: old.categoriesFor(EntryType.expense).first.name,
        accountId: accountId,
        day: 2,
        nextDate: DateTime(2027, 1, 2),
      ),
      today: day,
    );
    await old.saveInvoiceTimeout(420);
    await old.db.insert(
      'accounts',
      Account(
        name: 'Legacy IQD',
        currency: Currency.iqd,
        opening: 1000,
        asOf: DateTime(2020),
      ).toMap(),
    );
    final timestamp = old.entries.single.createdAt;
    for (final column in [
      'account_amount',
      'destination_amount',
      'fx_snapshot',
    ]) {
      await old.db.execute('ALTER TABLE transactions DROP COLUMN $column');
    }
    for (final column in ['base_currency', 'exchange_rate']) {
      await old.db.execute('ALTER TABLE accounts DROP COLUMN $column');
    }
    for (final table in ['recurring_rules', 'recurring_occurrences']) {
      await old.db.execute('ALTER TABLE $table DROP COLUMN currency');
    }
    await old.db.setVersion(13);
    await old.db.close();
    old.dispose();
    try {
      for (var round = 0; round < 2; round++) {
        final migrated = await LedgerStore.open(
          path: path,
          factory: databaseFactoryFfi,
        );
        expect(await migrated.db.getVersion(), 18);
        expect(migrated.entries.single.amount, 200);
        expect(migrated.entries.single.createdAt, timestamp);
        expect(migrated.accounts.single.id, accountId);
        expect(migrated.accounts.single.exchangeRate, '1');
        expect(migrated.currentBalances.wealth, 9800);
        expect(migrated.invoiceTimeoutSeconds, 420);
        expect(migrated.recurringRules.single.amount, 100);
        expect(migrated.hasLegacyCurrencyData, isTrue);
        expect(await migrated.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        await migrated.db.close();
        migrated.dispose();
      }
    } finally {
      await databaseFactoryFfi.deleteDatabase(path);
      await directory.delete();
    }
  });
  test('legacy recurring rules adopt native currency when their bank changes currency', () async {
    final old = getBank('Euro bank');
    await store.saveRecurring(
      RecurringRule(
        description: 'Legacy schedule',
        amount: 200,
        category: store.categoriesFor(EntryType.expense).first.name,
        accountId: old.id!,
        day: 2,
        nextDate: day,
      ),
      today: day,
    );
    await store.updateAccount(
      revise(old, currency: Currency.iqd, rate: '1772'),
    );
    expect(store.recurringRules.single.currency, Currency.iqd);
    expect(store.recurringRules.single.amount, 3544000);
    await store.updateAccount(revise(getBank('Euro bank'), rate: '1800'));
    await store.processRecurring(today: DateTime(2026, 2, 2));
    expect(store.entries.map((e) => e.amount).toSet(), {200, 197});
    expect(store.entries.every((e) => e.accountAmount == 3544000), isTrue);
  });

  test('balance correction can remove a negative baseline and disable overdraft atomically', () async {
    final old = getBank('Euro bank');
    await store.updateAccount(
      Account(
        id: old.id,
        name: old.name,
        currency: old.currency,
        opening: -5000,
        asOf: old.asOf,
        includeOnAsOf: true,
        allowOverdraft: true,
      ),
    );
    final negative = getBank('Euro bank');
    await store.updateAccount(
      Account(
        id: negative.id,
        name: negative.name,
        currency: negative.currency,
        opening: negative.opening,
        asOf: negative.asOf,
        includeOnAsOf: true,
        allowOverdraft: false,
      ),
      currentBalance: 1000,
    );
    expect(store.currentBalances.byAccount[old.id], 1000);
    expect(getBank('Euro bank').canOverdraw, isFalse);
  });
}
