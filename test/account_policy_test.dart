import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  final start = DateTime(2026, 1, 1);
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<Account> add(
    String name, {
    AccountKind kind = AccountKind.bank,
    int opening = 0,
    bool overdraft = false,
  }) async {
    await store.addAccount(
      Account(
        name: name,
        currency: Currency.eur,
        opening: opening,
        asOf: start,
        kind: kind,
        includeOnAsOf: true,
        allowOverdraft: overdraft,
      ),
    );
    return store.accounts.singleWhere((a) => a.name == name);
  }

  LedgerEntry entry(
    Account a,
    int amount, {
    int? id,
    EntryType type = EntryType.expense,
    Account? to,
    DateTime? date,
  }) => LedgerEntry(
    id: id,
    type: type,
    amount: amount,
    currency: Currency.eur,
    date: date ?? start,
    description: 'Payment',
    category: 'Other',
    accountId: a.id,
    destinationId: to?.id,
  );

  test('cash cannot be negative, even if overdraft is requested', () async {
    await expectLater(
      add('Invalid cash', kind: AccountKind.cash, opening: -1, overdraft: true),
      throwsArgumentError,
    );
    final cash = await add(
      'Cash',
      kind: AccountKind.cash,
      opening: 1000,
      overdraft: true,
    );
    expect(cash.canOverdraw, isFalse);
    await store.saveEntry(entry(cash, 1000));
    await expectLater(store.saveEntry(entry(cash, 1)), throwsArgumentError);
    expect(store.entries, hasLength(1));
    expect(accountBalance(cash, store.entries, start), 0);
  });
  test('two banks have independent overdraft policies', () async {
    final debit = await add('Debit');
    final credit = await add('Overdraft bank', overdraft: true);
    await expectLater(store.saveEntry(entry(debit, 1000)), throwsArgumentError);
    await store.saveEntry(entry(credit, 1000));
    expect(accountBalance(debit, store.entries, start), 0);
    expect(accountBalance(credit, store.entries, start), -1000);
    await store.refresh();
    expect(
      store.accounts.singleWhere((a) => a.id == credit.id).canOverdraw,
      isTrue,
    );
  });
  test(
    'rejected edit and transfer roll back without partial balance updates',
    () async {
      final cash = await add('Cash', kind: AccountKind.cash, opening: 1000);
      final bank = await add('Bank');
      await store.saveEntry(entry(cash, 600));
      final id = store.entries.single.id;
      await expectLater(
        store.saveEntry(entry(cash, 1001, id: id)),
        throwsArgumentError,
      );
      expect(store.entries.single.amount, 600);
      await expectLater(
        store.saveEntry(entry(cash, 500, type: EntryType.transfer, to: bank)),
        throwsArgumentError,
      );
      expect(store.entries, hasLength(1));
      expect(accountBalance(cash, store.entries, start), 400);
      expect(accountBalance(bank, store.entries, start), 0);
    },
  );
  test('deleting funding income and moving it to another account cannot overdraw cash', () async {
    final cash = await add('Cash', kind: AccountKind.cash);
    final bank = await add('Bank');
    await store.saveEntry(entry(cash, 1000, type: EntryType.income));
    final incomeId = store.entries.single.id!;
    await store.saveEntry(entry(cash, 800));
    await expectLater(store.deleteEntry(incomeId), throwsArgumentError);
    await expectLater(
      store.saveEntry(entry(bank, 1000, id: incomeId, type: EntryType.income)),
      throwsArgumentError,
    );
    expect(store.entries, hasLength(2));
    expect(accountBalance(cash, store.entries, start), 200);
  });
  test('future funding does not cover an earlier deficit', () async {
    final cash = await add('Cash', kind: AccountKind.cash);
    await store.saveEntry(
      entry(cash, 1000, type: EntryType.income, date: DateTime(2026, 1, 2)),
    );
    await expectLater(store.saveEntry(entry(cash, 800)), throwsArgumentError);
    expect(store.entries, hasLength(1));
  });
  test('editing account details preserves payments and rejects unsafe policy changes', () async {
    final bank = await add('Old bank', overdraft: true);
    await store.saveEntry(entry(bank, 1000));
    await expectLater(
      store.updateAccount(
        Account(
          id: bank.id,
          name: 'New bank',
          currency: Currency.eur,
          opening: 0,
          asOf: start,
          includeOnAsOf: true,
        ),
      ),
      throwsArgumentError,
    );
    expect(store.accounts.single.name, 'Old bank');
    expect(store.accounts.single.canOverdraw, isTrue);
    await store.updateAccount(
      Account(
        id: bank.id,
        name: 'New bank',
        currency: Currency.eur,
        opening: 3000,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
    expect(store.accounts.single.name, 'New bank');
    expect(store.accounts.single.canOverdraw, isFalse);
    expect(accountBalance(store.accounts.single, store.entries, start), 2000);
    expect(store.entries.single.amount, 1000);
  });
  test(
    'concurrent payments cannot both spend the same remaining balance',
    () async {
      final cash = await add('Cash', kind: AccountKind.cash, opening: 1000);
      final results = await Future.wait([
        for (var i = 0; i < 2; i++)
          store
              .saveEntry(entry(cash, 800))
              .then((_) => true, onError: (_) => false),
      ]);
      expect(results.where((success) => success), hasLength(1));
      await store.refresh();
      expect(store.entries, hasLength(1));
      expect(accountBalance(cash, store.entries, start), 200);
    },
  );
}
