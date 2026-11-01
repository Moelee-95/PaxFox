import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/ledger_queries.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

LedgerEntry entry(
  EntryType type,
  int amount, {
  int? id,
  DateTime? date,
  Currency currency = Currency.eur,
  int? accountId = 1,
  int? destinationId,
  String description = 'Purchase',
  String category = 'Groceries',
  String notes = '',
}) => LedgerEntry(
  id: id,
  type: type,
  amount: amount,
  currency: currency,
  date: date ?? DateTime(2026, 10, 15),
  description: description,
  category: category,
  notes: notes,
  accountId: accountId,
  destinationId: destinationId,
);

void main() {
  test('monthly summaries separate years, income, refunds and transfers', () {
    final ledger = LedgerIndex([
      entry(EntryType.income, 5000, id: 1),
      entry(EntryType.expense, 1200, id: 2),
      entry(EntryType.refund, 300, id: 3),
      entry(EntryType.transfer, 2000, id: 4, destinationId: 2),
      entry(EntryType.expense, 900, id: 5, date: DateTime(2025, 10)),
      entry(EntryType.expense, 800, id: 6, date: DateTime(2026, 9)),
    ]);
    final october = ledger.forMonth(DateTime(2026, 10));

    expect(october.entries, hasLength(4));
    expect(october.spendingEntries.map((entry) => entry.id), [2, 3]);
    expect(october.incomeEntries.single.id, 1);
    expect(october.eurTotals.income, 5000);
    expect(october.eurTotals.spending, 900);
    expect(october.eurTotals.net, 4100);
    expect(october.spendingByCategory[(Currency.eur, 'Groceries')], 900);
    final categoryRows = october.spendingForCategory(Currency.eur, 'Groceries');
    expect(categoryRows.map((entry) => entry.id), [2, 3]);
    expect(
      october.spendingForCategory(Currency.eur, 'Groceries'),
      same(categoryRows),
    );
    expect(() => categoryRows.clear(), throwsUnsupportedError);
    final ranked = october.rankedCategories(Currency.eur);
    expect(ranked.single.value, 900);
    expect(october.rankedCategories(Currency.eur), same(ranked));
    expect(() => ranked.clear(), throwsUnsupportedError);
    expect(ledger.forMonth(DateTime(2026, 10, 31)), same(october));
    expect(ledger.forMonth(DateTime(2025, 10)).eurTotals.spending, 900);
  });

  test('category summaries retain currency and allow net refunds', () {
    final summary = MonthlyLedger([
      entry(EntryType.expense, 100, category: 'EUR · Travel'),
      entry(EntryType.refund, 300, category: 'EUR · Travel'),
      entry(EntryType.expense, 7000, currency: Currency.iqd),
    ]);

    expect(summary.spendingByCategory, {
      (Currency.eur, 'EUR · Travel'): -200,
      (Currency.iqd, 'Groceries'): 7000,
    });
    expect(summary.eurTotals.spending, -200);
  });

  test('missing months return a reusable empty summary', () {
    final ledger = LedgerIndex(const []);
    final summary = ledger.forMonth(DateTime(2026, 10));
    expect(summary.entries, isEmpty);
    expect(summary.spendingEntries, isEmpty);
    expect(summary.incomeEntries, isEmpty);
    expect(summary.eurTotals.net, 0);
    expect(summary.spendingByCategory, isEmpty);
    expect(ledger.forMonth(DateTime(2026, 10, 2)), same(summary));
  });

  test(
    'search combines case insensitive text and type while preserving order',
    () {
      final ledger = LedgerIndex([
        entry(EntryType.expense, 100, id: 1, description: 'Coffee shop'),
        entry(EntryType.income, 200, id: 2, category: 'Coffee sales'),
        entry(EntryType.refund, 50, id: 3, notes: 'COFFEE refund'),
      ]);
      expect(ledger.search(query: 'coffee').map((entry) => entry.id), [
        1,
        2,
        3,
      ]);
      expect(
        ledger.search(query: 'COFFEE', type: EntryType.refund).single.id,
        3,
      );
      expect(ledger.search(query: 'missing'), isEmpty);
      expect(ledger.search(type: EntryType.income).single.id, 2);
      expect(ledger.search(), same(ledger.entries));
      final matches = ledger.search(query: 'coffee');
      expect(ledger.search(query: 'COFFEE'), same(matches));
    },
  );

  test('indexed entries cannot be changed behind cached summaries', () {
    final source = [entry(EntryType.expense, 100)];
    final ledger = LedgerIndex(source);
    source.clear();
    expect(ledger.entries, hasLength(1));
    expect(() => ledger.entries.clear(), throwsUnsupportedError);
    expect(
      () => ledger.forMonth(DateTime(2026, 10)).spendingEntries.clear(),
      throwsUnsupportedError,
    );
    expect(
      () => ledger.search(query: 'purchase').clear(),
      throwsUnsupportedError,
    );
  });

  test('type-filter caches survive switching filters and text searches', () {
    final ledger = LedgerIndex([
      entry(EntryType.expense, 100, id: 1),
      entry(EntryType.refund, 50, id: 2),
      entry(EntryType.income, 200, id: 3),
      entry(EntryType.expense, 300, id: 4),
    ]);
    final expenses = ledger.search(type: EntryType.expense);
    final refunds = ledger.search(type: EntryType.refund);
    expect(expenses.map((entry) => entry.id), [1, 4]);
    expect(refunds.single.id, 2);
    expect(ledger.search(query: 'purchase'), hasLength(4));
    expect(ledger.search(type: EntryType.expense), same(expenses));
    expect(ledger.search(type: EntryType.refund), same(refunds));
    expect(() => expenses.clear(), throwsUnsupportedError);
    expect(ledger.search(type: EntryType.transfer), isEmpty);
  });

  test('batch balances match individual balances across account policies', () {
    final accounts = [
      Account(
        id: 1,
        name: 'Cash',
        currency: Currency.eur,
        opening: 1000,
        asOf: DateTime(2026, 10, 10, 18),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
      Account(
        id: 2,
        name: 'Blocked bank',
        currency: Currency.eur,
        opening: -500,
        asOf: DateTime(2026, 10, 10),
        available: false,
        allowOverdraft: true,
      ),
      Account(
        id: 3,
        name: 'Legacy currency',
        currency: Currency.iqd,
        opening: 7000,
        asOf: DateTime(2026, 10, 1),
      ),
    ];
    final entries = [
      entry(EntryType.expense, 100, date: DateTime(2026, 10, 9)),
      entry(EntryType.expense, 200, date: DateTime(2026, 10, 10)),
      entry(EntryType.income, 1000, accountId: 2, date: DateTime(2026, 10, 10)),
      entry(EntryType.transfer, 300, destinationId: 2),
      entry(EntryType.refund, 50),
      entry(EntryType.income, 200, accountId: 2),
      entry(EntryType.expense, 800, accountId: null),
      entry(EntryType.expense, 6000, currency: Currency.iqd),
      entry(EntryType.expense, 1000, currency: Currency.iqd, accountId: 3),
      entry(EntryType.income, 9000, date: DateTime(2026, 10, 16)),
      entry(EntryType.expense, 9000, accountId: 999),
    ];
    final through = DateTime(2026, 10, 15, 23);
    final balances = AccountBalances(accounts, entries, through);
    for (final account in accounts) {
      expect(
        balances.byAccount[account.id],
        accountBalance(account, entries, through),
        reason: account.name,
      );
    }
    expect(balances.byAccount, {1: 550, 2: 0, 3: 6000});
    expect(balances.wealth, 6550);
    expect(balances.available, 6550);
    expect(balances.blocked, 0);
    expect(() => balances.byAccount.clear(), throwsUnsupportedError);
  });

  test('blocked debt stays in wealth and empty balances are zero', () {
    final accounts = [
      Account(
        id: 1,
        name: 'Blocked debt',
        currency: Currency.eur,
        opening: -500,
        asOf: DateTime(2026, 10),
        available: false,
        allowOverdraft: true,
      ),
    ];
    final balances = AccountBalances(accounts, const [], DateTime(2026, 10));
    expect(balances.wealth, -500);
    expect(balances.available, 0);
    expect(balances.blocked, -500);
    expect(AccountBalances(const [], const [], DateTime(2026)).wealth, 0);
  });

  group('store cache lifecycle', () {
    late LedgerStore store;

    setUp(() async {
      sqfliteFfiInit();
      store = await LedgerStore.open(
        path: ':memory:',
        factory: databaseFactoryFfi,
      );
      await store.addAccount(
        Account(
          name: 'Cash',
          currency: Currency.eur,
          opening: 10000,
          asOf: DateTime(2026, 10),
          includeOnAsOf: true,
          kind: AccountKind.cash,
        ),
      );
    });

    tearDown(() async {
      store.dispose();
      await store.db.close();
    });

    test(
      'writes and deletes invalidate summaries, search and balances',
      () async {
        final month = DateTime(2026, 10);
        final initialSummary = store.monthSummary(month);
        final initialBalances = store.currentBalances;
        expect(store.currentBalances, same(initialBalances));
        expect(store.searchEntries(query: 'purchase'), isEmpty);

        await store.saveEntry(
          entry(EntryType.expense, 1200, accountId: store.accounts.single.id),
        );
        expect(store.monthSummary(month), isNot(same(initialSummary)));
        expect(store.monthSummary(month).eurTotals.spending, 1200);
        expect(store.currentBalances, isNot(same(initialBalances)));
        expect(
          store.currentBalances.byAccount[store.accounts.single.id],
          accountBalance(store.accounts.single, store.entries, DateTime.now()),
        );
        expect(store.searchEntries(query: 'purchase'), hasLength(1));

        await store.deleteEntry(store.entries.single.id!);
        expect(store.monthSummary(month).entries, isEmpty);
        expect(store.searchEntries(query: 'purchase'), isEmpty);
        expect(store.currentBalances.wealth, 10000);
      },
    );

    test(
      'category edits refresh icon lookup and historical summaries',
      () async {
        await store.saveEntry(
          entry(EntryType.expense, 1200, accountId: store.accounts.single.id),
        );
        final category = store.categories.singleWhere(
          (category) => category.name == 'Groceries',
        );
        expect(
          store.categoryFor('Groceries', EntryType.expense),
          same(category),
        );
        expect(
          store.categoryFor('Groceries', EntryType.refund),
          same(category),
        );
        expect(store.categoryFor('Groceries', EntryType.income), isNull);
        expect(store.categoryFor('missing', EntryType.expense), isNull);
        store.monthSummary(DateTime(2026, 10));
        await store.saveCategory(
          id: category.id,
          kind: category.kind,
          name: 'Food',
          icon: CategoryIcon.dining,
        );
        expect(store.iconFor(store.entries.single), CategoryIcon.dining);
        expect(store.categoryFor('Groceries', EntryType.expense), isNull);
        expect(store.categoryFor('Food', EntryType.expense)?.id, category.id);
        expect(store.searchEntries(query: 'groceries'), isEmpty);
        expect(store.searchEntries(query: 'food'), hasLength(1));
        expect(store.monthSummary(DateTime(2026, 10)).spendingByCategory, {
          (Currency.eur, 'Food'): 1200,
        });
        expect(() => store.accounts.clear(), throwsUnsupportedError);
        expect(() => store.categories.clear(), throwsUnsupportedError);
        expect(
          () => store.categoriesFor(EntryType.expense).clear(),
          throwsUnsupportedError,
        );
      },
    );

    test('category appearance edits write only the category row', () async {
      await store.saveEntry(
        entry(EntryType.expense, 1200, accountId: store.accounts.single.id),
      );
      const timestamp = '2026-01-01T00:00:00.000Z';
      await store.db.update('transactions', {'updated_at': timestamp});
      await store.db.insert('receipts', {
        'transaction_id': store.entries.single.id,
        'total': 1200,
        'draft': '{"category":"Groceries","items":[]}',
        'image_paths': '[]',
        'raw_response': '',
        'scanned_at': timestamp,
      });
      final category = store.categoryFor('Groceries', EntryType.expense)!;
      Future<int> totalChanges() async =>
          (await store.db.rawQuery('SELECT total_changes() AS count'))
                  .single['count']
              as int;
      final before = await totalChanges();
      await store.saveCategory(
        id: category.id,
        kind: category.kind,
        name: category.name,
        icon: CategoryIcon.dining,
        color: 0xff55c9a4,
      );

      expect(await totalChanges() - before, 1);
      expect(
        (await store.db.query('transactions')).single['updated_at'],
        timestamp,
      );
      expect(store.colorFor(store.entries.single), 0xff55c9a4);
      expect(store.iconFor(store.entries.single), CategoryIcon.dining);
      expect(store.entries.single.amount, 1200);
      expect(store.monthSummary(DateTime(2026, 10)).eurTotals.spending, 1200);
    });

    test(
      'failed refresh retains the last complete state without notifying',
      () async {
        final accounts = store.accounts;
        final categories = store.categories;
        var notifications = 0;
        store.addListener(() => notifications++);
        await store.db.insert('settings', {
          'key': 'app_currency',
          'value': 'invalid currency',
        });
        await store.db.update('accounts', {'name': 'New name'});

        await expectLater(store.refresh(), throwsArgumentError);
        expect(store.accounts, same(accounts));
        expect(store.categories, same(categories));
        expect(store.accounts.single.name, 'Cash');
        expect(notifications, 0);

        await store.db.delete(
          'settings',
          where: 'key = ?',
          whereArgs: ['app_currency'],
        );
        await store.refresh();
        expect(store.accounts.single.name, 'New name');
        expect(notifications, 1);
      },
    );
  });
}
