import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/currency_exchange.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  final today = dateOnly(DateTime.now());
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
        opening: 100000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    await store.saveExchangeRates({'eur_iqd': '1772', 'eur_usd': '1.1'});
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<Debt> makeDebt({bool receivable = false}) async {
    await store.saveDebt(
      Debt(
        name: 'IQD rent',
        amount: Currency.iqd.parse('177200'),
        currency: Currency.iqd,
        isReceivable: receivable,
      ),
    );
    return store.debts.single;
  }

  Future<void> settle(
    Debt d, {
    String principal = '3544',
    int fee = 100,
    int? id,
    String? rate,
    int? account,
  }) => store.settleDebt(
    debtId: d.id!,
    principal: Currency.iqd.parse(principal),
    accountId: account ?? store.accounts.first.id!,
    rate: rate == null
        ? store.exchangeTable.rate(Currency.iqd, Currency.eur)!
        : ConversionRate.parse(rate),
    fee: fee,
    date: today,
    transactionId: id,
  );

  test('exact reverse and cross conversions round only at the destination', () {
    final table = store.exchangeTable;
    expect(table.convert(10000, Currency.eur, Currency.iqd), 177200000);
    expect(table.convert(177200000, Currency.iqd, Currency.eur), 10000);
    expect(table.convert(177200000, Currency.iqd, Currency.usd), 11000);
    expect(
      ConversionRate.parse('1,772').convert(200, Currency.eur, Currency.iqd),
      3544000,
    );
    expect(() => ConversionRate.parse('0'), throwsFormatException);
  });
  test('native debt, separate outgoing fee, partial edit, defaults and deletion remain consistent', () async {
    final d = await makeDebt();
    expect(store.totalDebt, 10000);
    await settle(d);
    final principal = store.entries.singleWhere((e) => e.category == 'Debt');
    final fee = store.entries.singleWhere((e) => e.category == 'Exchange fees');
    expect(principal.amount, 200);
    expect(fee.amount, 100);
    expect(store.debts.single.amount, Currency.iqd.parse('173656'));
    expect(store.currentBalances.byAccount[store.accounts.first.id], 99700);
    expect(store.debtFeeLinks[fee.id], principal.id);
    await store.saveExchangeRates({'eur_iqd': '2000'});
    expect(store.entries.singleWhere((e) => e.id == principal.id).amount, 200);
    await settle(
      d,
      principal: '7088',
      fee: 50,
      id: principal.id,
      rate: '0.001',
    );
    expect(store.entries.singleWhere((e) => e.id == principal.id).amount, 709);
    expect(store.debts.single.amount, Currency.iqd.parse('170112'));
    expect(store.currentBalances.byAccount[store.accounts.first.id], 99241);
    await store.deleteEntry(principal.id!);
    expect(store.entries, isEmpty);
    expect(store.debts.single.amount, d.amount);
    expect(store.currentBalances.byAccount[store.accounts.first.id], 100000);
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
    'incoming fee is a separate expense deducted from gross receipt',
    () async {
      final d = await makeDebt(receivable: true);
      await settle(d, fee: 50);
      expect(
        store.entries.singleWhere((e) => e.type == EntryType.income).amount,
        200,
      );
      expect(
        store.entries.singleWhere((e) => e.type == EntryType.expense).amount,
        50,
      );
      expect(store.currentBalances.byAccount[store.accounts.first.id], 100150);
      expect(store.totalReceivable, 9800);
      final id = store.entries.singleWhere((e) => e.category == 'Debt').id!;
      await expectLater(
        settle(d, principal: '100', fee: 100, id: id),
        throwsArgumentError,
      );
      expect(store.currentBalances.byAccount[store.accounts.first.id], 100150);
      await store.deleteEntry(id);
      expect(store.totalReceivable, 10000);
      expect(store.entries, isEmpty);
    },
  );
  test(
    'overpayment and insufficient funds roll back fees and principal',
    () async {
      final d = await makeDebt();
      await expectLater(settle(d, principal: '177201'), throwsArgumentError);
      await expectLater(settle(d, fee: 100001), throwsArgumentError);
      expect(store.entries, isEmpty);
      expect(store.debts.single.amount, d.amount);
      expect(await store.db.query('debt_payments'), isEmpty);
    },
  );
  test('same native currency uses direct amount, forbids fee, guards currency changes after payments', () async {
    final d = await makeDebt();
    await store.addAccount(
      Account(
        name: 'IQD bank',
        currency: Currency.iqd,
        baseCurrency: Currency.eur,
        exchangeRate: '1772',
        opening: d.amount,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    final bank = store.accounts.singleWhere((a) => a.currency == Currency.iqd);
    await settle(d, account: bank.id, fee: 0, rate: '9000');
    expect(store.entries.single.accountAmount, Currency.iqd.parse('3544'));
    expect(store.entries.single.amount, 200);
    await expectLater(settle(d, account: bank.id, fee: 1), throwsArgumentError);
    await expectLater(
      store.saveDebt(
        Debt(id: d.id, name: d.name, amount: 50, currency: Currency.eur),
      ),
      throwsArgumentError,
    );
    await store.saveExchangeRates({});
    expect(store.debtMainAmount(store.debts.single), isNull);
    final id = store.entries.single.id!;
    await store.deleteEntry(id);
    expect(store.debts.single.amount, d.amount);
  });
  test('editing only date after account rate changes preserves old reporting amounts and fee', () async {
    await store.addAccount(
      Account(
        name: 'USD bank',
        currency: Currency.usd,
        baseCurrency: Currency.eur,
        exchangeRate: '1.1',
        opening: 110000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    final a = store.accounts.singleWhere((a) => a.currency == Currency.usd);
    final d = await makeDebt();
    await store.settleDebt(
      debtId: d.id!,
      principal: Currency.iqd.parse('3544'),
      accountId: a.id!,
      rate: store.exchangeTable.rate(Currency.iqd, Currency.usd)!,
      fee: 110,
      date: today,
    );
    final entry = store.entries.singleWhere((e) => e.category == 'Debt');
    expect(entry.amount, 200);
    await store.updateAccount(
      Account(
        id: a.id,
        name: a.name,
        currency: a.currency,
        baseCurrency: Currency.eur,
        exchangeRate: '2',
        opening: a.opening,
        asOf: a.asOf,
        includeOnAsOf: true,
      ),
    );
    await store.settleDebt(
      debtId: d.id!,
      principal: Currency.iqd.parse('3544'),
      accountId: a.id!,
      rate: store.exchangeTable.rate(Currency.iqd, Currency.usd)!,
      fee: 110,
      date: today,
      transactionId: entry.id,
    );
    expect(store.entries.singleWhere((e) => e.category == 'Debt').amount, 200);
    expect(
      store.entries.singleWhere((e) => e.category == 'Exchange fees').amount,
      100,
    );
  });
  test(
    'deleting just the fee keeps principal settled and detaches fee safely',
    () async {
      final d = await makeDebt();
      await settle(d);
      final id = store.entries.singleWhere((e) => e.category == 'Debt').id!;
      await store.deleteEntry(
        store.entries.singleWhere((e) => e.category == 'Exchange fees').id!,
      );
      expect((await store.debtSettlement(id))!['fee_transaction_id'], isNull);
      expect(store.debts.single.amount, Currency.iqd.parse('173656'));
      await store.deleteEntry(id);
      expect(store.debts.single.amount, d.amount);
    },
  );
  test('schema 16 migration preserves linked payments and initializes known bank defaults', () async {
    final dir = await Directory.systemTemp.createTemp(
      'paxfox_native_debt_v16_',
    );
    final path = '${dir.path}/ledger.sqlite';
    var saved = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
    try {
      await saved.addAccount(
        Account(
          name: 'Euro bank',
          currency: Currency.eur,
          opening: 100000,
          asOf: DateTime(2020),
          includeOnAsOf: true,
        ),
      );
      await saved.addAccount(
        Account(
          name: 'IQD bank',
          currency: Currency.iqd,
          baseCurrency: Currency.eur,
          exchangeRate: '1772',
          opening: 0,
          asOf: DateTime(2020),
          includeOnAsOf: true,
        ),
      );
      await saved.saveDebt(
        const Debt(name: 'Existing debt', amount: 5000, currency: Currency.eur),
      );
      final debtId = saved.debts.single.id!;
      await saved.payDebt(
        debtId,
        LedgerEntry(
          type: EntryType.expense,
          amount: 2000,
          currency: Currency.eur,
          date: today,
          description: 'Old payment',
          category: 'Debt',
          accountId: saved.accounts.first.id,
        ),
      );
      final paymentId = saved.entries.single.id!;
      await saved.db.execute('PRAGMA foreign_keys = OFF');
      await saved.db.execute('DROP TRIGGER debt_payment_validate');
      await saved.db.execute('DROP TRIGGER debt_transaction_change');
      await saved.db.execute('ALTER TABLE debt_payments DROP COLUMN details');
      await saved.db.execute(
        'ALTER TABLE debt_payments DROP COLUMN fee_transaction_id',
      );
      await saved.db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: ['currency_exchange_rates'],
      );
      await saved.db.setVersion(16);
      await saved.db.close();
      saved.dispose();
      saved = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
      expect(await saved.db.getVersion(), 18);
      expect(saved.debts.single.amount, 3000);
      expect(saved.entries.single.amount, 2000);
      expect((await saved.debtSettlement(paymentId))!['details'], isNull);
      expect(
        saved.exchangeTable.convert(10000, Currency.eur, Currency.iqd),
        177200000,
      );
      await saved.settleDebt(
        debtId: debtId,
        principal: 2500,
        accountId: saved.accounts.first.id!,
        rate: ConversionRate.parse('1'),
        fee: 0,
        date: today,
        transactionId: paymentId,
      );
      expect(saved.debts.single.amount, 2500);
      expect(saved.entries.single.amount, 2500);
      expect(await saved.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await saved.db.close();
      saved.dispose();
      await dir.delete(recursive: true);
    }
  });
  test('deleting a native receipt and its fee rolls back if later spending depends on it', () async {
    final d = await makeDebt(receivable: true);
    await settle(d, fee: 50);
    final receipt = store.entries.singleWhere((e) => e.category == 'Debt');
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 100100,
        currency: Currency.eur,
        date: today,
        description: 'Spend receipt',
        category: 'Exchange fees',
        accountId: store.accounts.first.id,
      ),
    );
    await expectLater(store.deleteEntry(receipt.id!), throwsArgumentError);
    expect(store.entries.length, 3);
    expect(store.debts.single.amount, Currency.iqd.parse('173656'));
    expect(
      (await store.debtSettlement(receipt.id!))!['fee_transaction_id'],
      isNotNull,
    );
    expect(store.currentBalances.byAccount[store.accounts.first.id], 50);
  });
  test(
    'foreign debt and receivable need no default rate, including setup',
    () async {
      await store.saveExchangeRates({});
      await store.saveDebt(
        const Debt(name: 'Unvalued', amount: 177200000, currency: Currency.iqd),
      );
      expect(store.debtMainAmount(store.debts.single), isNull);
      expect(store.totalDebt, 0);
      expect(store.hasUnvaluedDebts, isTrue);
      await store.saveDebt(
        const Debt(
          name: 'Unvalued receivable',
          amount: 5000,
          currency: Currency.usd,
          isReceivable: true,
        ),
      );
      expect(store.totalReceivable, 0);
      expect(store.entries, isEmpty);
      await store.saveExchangeRates({'iqd_eur': '0.0005', 'usd_eur': '0.9'});
      expect(store.totalDebt, 8860);
      expect(store.totalReceivable, 4500);
      await store.saveExchangeRates({});
      expect(store.totalDebt, 0);
    },
  );
  test('deadline acknowledge keeps money, stale actions cannot acknowledge a changed deadline', () async {
    final deadline = DateTime.now().subtract(const Duration(days: 1));
    await store.saveDebt(
      Debt(
        name: 'Due rent',
        amount: 5000,
        currency: Currency.eur,
        deadline: deadline,
      ),
    );
    final d = store.debts.single;
    expect(store.dueDebts().single.id, d.id);
    await store.acknowledgeDebtDeadline(d.id!, deadline);
    expect(store.dueDebts(), isEmpty);
    expect(store.debts.single.amount, 5000);
    expect(store.entries, isEmpty);
    final later = deadline.add(const Duration(days: 3));
    await store.saveDebt(
      Debt(
        id: d.id,
        name: d.name,
        amount: d.amount,
        currency: d.currency,
        deadline: later,
      ),
    );
    await store.acknowledgeDebtDeadline(d.id!, deadline);
    expect(store.debts.single.hasPendingDeadline, isTrue);
    expect(store.dueDebts(later.subtract(const Duration(minutes: 1))), isEmpty);
    expect(store.dueDebts(later).single.id, d.id);
    await store.settleDebt(
      debtId: d.id!,
      principal: 5000,
      accountId: store.accounts.first.id!,
      rate: ConversionRate.parse('1'),
      fee: 0,
      date: today,
    );
    expect(store.dueDebts(later), isEmpty);
    await store.deleteEntry(store.entries.single.id!);
    expect(store.dueDebts(later).single.id, d.id);
  });
  test('schema 17 upgrades without losing foreign debt; setup needs no rate and deadlines survive reopen', () async {
    final dir = await Directory.systemTemp.createTemp('paxfox_debt_deadline_');
    final path = '${dir.path}/ledger.sqlite';
    var local = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
    try {
      await local.completeSetup(
        [
          Account(
            name: 'Cash',
            kind: AccountKind.cash,
            currency: Currency.eur,
            opening: 0,
            asOf: today,
          ),
        ],
        initialDebts: [
          const Debt(
            name: 'Native setup debt',
            amount: 177200000,
            currency: Currency.iqd,
          ),
        ],
      );
      expect(local.debtMainAmount(local.debts.single), isNull);
      await local.db.execute('ALTER TABLE debts DROP COLUMN deadline');
      await local.db.execute(
        'ALTER TABLE debts DROP COLUMN deadline_acknowledged',
      );
      await local.db.setVersion(17);
      await local.db.close();
      local.dispose();
      local = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
      expect(await local.db.getVersion(), 18);
      expect(local.debts.single.amount, 177200000);
      expect(local.debts.single.deadline, isNull);
      final d = local.debts.single;
      final deadline = DateTime(2027, 1, 2, 10, 30);
      await local.saveDebt(
        Debt(
          id: d.id,
          name: d.name,
          amount: d.amount,
          currency: d.currency,
          deadline: deadline,
        ),
      );
      await local.db.close();
      local.dispose();
      local = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
      expect(local.debts.single.deadline, deadline);
      expect(local.dueDebts(DateTime(2027, 1, 2, 10, 29)), isEmpty);
      expect(local.dueDebts(deadline), hasLength(1));
      expect(await local.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      await local.db.close();
      local.dispose();
      await dir.delete(recursive: true);
    }
  });
}
