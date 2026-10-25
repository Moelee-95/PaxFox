import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  late Account bank;
  final start = DateTime(2024, 1, 1);
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Rent bank',
        currency: Currency.eur,
        opening: 50000,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
    bank = store.accounts.single;
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  RecurringRule rule({
    int? id,
    int amount = 10000,
    DateTime? next,
    int day = 31,
    DateTime? end,
  }) => RecurringRule(
    id: id,
    description: 'Rent',
    amount: amount,
    category: 'Rent & utilities',
    accountId: bank.id!,
    day: day,
    nextDate: next ?? DateTime(2024, 1, 31),
    endDate: end,
  );
  test('recurring income credits cash and blocked banks once', () async {
    await store.updateAccount(
      Account(
        id: bank.id,
        name: bank.name,
        currency: Currency.eur,
        opening: bank.opening,
        asOf: start,
        includeOnAsOf: true,
        available: false,
      ),
    );
    await store.saveRecurring(
      RecurringRule(
        type: EntryType.income,
        description: 'Salary',
        amount: 2500,
        category: 'Salary',
        accountId: bank.id!,
        day: 31,
        nextDate: DateTime(2024, 1, 31),
      ),
      today: start,
    );
    await store.addAccount(
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 0,
        kind: AccountKind.cash,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
    final cash = store.accounts.singleWhere((a) => a.kind == AccountKind.cash);
    await store.saveRecurring(
      RecurringRule(
        type: EntryType.income,
        description: 'Cash income',
        amount: 1000,
        category: 'Other',
        accountId: cash.id!,
        day: 31,
        nextDate: DateTime(2024, 1, 31),
      ),
      today: start,
    );
    await store.processRecurring(today: DateTime(2024, 1, 31));
    await store.processRecurring(today: DateTime(2024, 1, 31));
    expect(store.entries, hasLength(2));
    expect(store.entries.every((e) => e.type == EntryType.income), isTrue);
    expect(
      store.recurringOccurrences.every(
        (o) => o.type == EntryType.income && o.status == 'posted',
      ),
      isTrue,
    );
    expect(
      accountBalance(
        store.accounts.singleWhere((a) => a.id == bank.id),
        store.entries,
        DateTime(2024, 1, 31),
      ),
      52500,
    );
    expect(accountBalance(cash, store.entries, DateTime(2024, 1, 31)), 1000);
  });
  test('multi-month catchup posts salary before same-day rent regardless of creation order', () async {
    await store.updateAccount(
      Account(
        id: bank.id,
        name: bank.name,
        currency: Currency.eur,
        opening: 0,
        asOf: start,
        includeOnAsOf: true,
      ),
    );
    await store.saveRecurring(
      RecurringRule(
        description: 'Rent',
        amount: 10000,
        category: 'Rent & utilities',
        accountId: bank.id!,
        day: 1,
        nextDate: start,
        active: false,
      ),
      today: start,
    );
    await store.saveRecurring(
      RecurringRule(
        type: EntryType.income,
        description: 'Salary',
        amount: 20000,
        category: 'Salary',
        accountId: bank.id!,
        day: 1,
        nextDate: start,
        active: false,
      ),
      today: start,
    );
    await store.db.update('recurring_rules', {'active': 1});
    await store.processRecurring(today: DateTime(2024, 3, 1));
    expect(store.entries, hasLength(6));
    expect(
      store.recurringOccurrences.every((o) => o.status == 'posted'),
      isTrue,
    );
    expect(
      accountBalance(
        store.accounts.single,
        store.entries,
        DateTime(2024, 3, 1),
      ),
      30000,
    );
  });
  test('editing rule type changes future occurrences without relabeling posted expenses', () async {
    await store.saveRecurring(rule(), today: start);
    await store.processRecurring(today: DateTime(2024, 1, 31));
    final id = store.recurringRules.single.id!;
    await store.saveRecurring(
      RecurringRule(
        id: id,
        type: EntryType.income,
        description: 'Rental income',
        amount: 12000,
        category: 'Rental income',
        accountId: bank.id!,
        day: 31,
        nextDate: DateTime(2024, 2, 29),
      ),
      today: DateTime(2024, 2, 1),
    );
    await store.processRecurring(today: DateTime(2024, 2, 29));
    expect(
      store.entries.singleWhere((e) => e.date.month == 1).type,
      EntryType.expense,
    );
    expect(
      store.entries.singleWhere((e) => e.date.month == 2).type,
      EntryType.income,
    );
    expect(
      store.recurringOccurrences.map((o) => o.type),
      containsAll([EntryType.expense, EntryType.income]),
    );
  });
  test('income category validation and renaming remain separate from expense categories', () async {
    await expectLater(
      store.saveRecurring(
        RecurringRule(
          type: EntryType.income,
          description: 'Invalid',
          amount: 100,
          category: 'Groceries',
          accountId: bank.id!,
          day: 31,
          nextDate: DateTime(2024, 1, 31),
        ),
        today: start,
      ),
      throwsArgumentError,
    );
    await store.saveRecurring(
      RecurringRule(
        type: EntryType.income,
        description: 'Other income',
        amount: 100,
        category: 'Other',
        accountId: bank.id!,
        day: 31,
        nextDate: DateTime(2024, 1, 31),
      ),
      today: start,
    );
    await store.saveRecurring(
      RecurringRule(
        description: 'Other expense',
        amount: 100,
        category: 'Other',
        accountId: bank.id!,
        day: 31,
        nextDate: DateTime(2024, 1, 31),
      ),
      today: start,
    );
    final category = store.categories.singleWhere(
      (c) => c.kind == CategoryKind.income && c.name == 'Other',
    );
    await store.saveCategory(
      id: category.id,
      kind: category.kind,
      name: 'Extra income',
    );
    expect(
      store.recurringRules
          .singleWhere((r) => r.type == EntryType.income)
          .category,
      'Extra income',
    );
    expect(
      store.recurringRules
          .singleWhere((r) => r.type == EntryType.expense)
          .category,
      'Other',
    );
  });
  test(
    'unpaid bills can be paid after later funding using the actual retry date',
    () async {
      await store.saveRecurring(rule(amount: 60000), today: start);
      await store.processRecurring(today: DateTime(2024, 1, 31));
      final id = store.recurringOccurrences.single.id;
      await expectLater(
        store.retryRecurring(id, paidOn: DateTime(2024, 1, 30)),
        throwsArgumentError,
      );
      await store.saveEntry(
        LedgerEntry(
          type: EntryType.income,
          amount: 20000,
          currency: Currency.eur,
          date: DateTime(2024, 2, 2),
          description: 'Later funding',
          category: 'Other',
          accountId: bank.id,
        ),
      );
      await store.retryRecurring(id, paidOn: DateTime(2024, 2, 2));
      expect(store.recurringOccurrences.single.status, 'posted');
      expect(store.recurringOccurrences.single.date, DateTime(2024, 1, 31));
      expect(
        store.entries.singleWhere((e) => e.type == EntryType.expense).date,
        DateTime(2024, 2, 2),
      );
      expect(accountBalance(bank, store.entries, DateTime(2024, 2, 2)), 10000);
    },
  );
  test(
    'month ends retain selected day through short months and leap years',
    () {
      expect(monthlyDate(2024, 2, 31), DateTime(2024, 2, 29));
      expect(monthlyDate(2025, 2, 31), DateTime(2025, 2, 28));
      expect(monthlyDate(2024, 3, 31), DateTime(2024, 3, 31));
      expect(
        firstMonthlyDate(DateTime(2024, 1, 20), 15),
        DateTime(2024, 2, 15),
      );
    },
  );
  test(
    'income needs an account and blocked accounts can receive but never spend',
    () async {
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.income,
            amount: 1000,
            currency: Currency.eur,
            date: start,
            description: 'Salary',
            category: 'Salary',
          ),
        ),
        throwsArgumentError,
      );
      await store.updateAccount(
        Account(
          id: bank.id,
          name: bank.name,
          currency: Currency.eur,
          opening: bank.opening,
          asOf: start,
          includeOnAsOf: true,
          available: false,
        ),
      );
      await store.saveEntry(
        LedgerEntry(
          type: EntryType.income,
          amount: 1000,
          currency: Currency.eur,
          date: start,
          description: 'Salary',
          category: 'Salary',
          accountId: bank.id,
        ),
      );
      expect(
        accountBalance(store.accounts.single, store.entries, start),
        51000,
      );
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.expense,
            amount: 100,
            currency: Currency.eur,
            date: start,
            description: 'Blocked',
            category: 'Other',
            accountId: bank.id,
          ),
        ),
        throwsArgumentError,
      );
      await store.addAccount(
        Account(
          name: 'Cash',
          currency: Currency.eur,
          opening: 0,
          asOf: start,
          includeOnAsOf: true,
          kind: AccountKind.cash,
        ),
      );
      final cash = store.accounts.singleWhere(
        (a) => a.kind == AccountKind.cash,
      );
      await expectLater(
        store.saveEntry(
          LedgerEntry(
            type: EntryType.transfer,
            amount: 100,
            currency: Currency.eur,
            date: start,
            description: 'Blocked transfer',
            category: 'Transfer',
            accountId: bank.id,
            destinationId: cash.id,
          ),
        ),
        throwsArgumentError,
      );
      expect(store.entries, hasLength(1));
      expect(
        store.accounts
            .where((a) => a.available)
            .fold<int>(
              0,
              (total, a) => total + accountBalance(a, store.entries, start),
            ),
        0,
      );
      expect(
        store.accounts.fold<int>(
          0,
          (total, a) => total + accountBalance(a, store.entries, start),
        ),
        51000,
      );
    },
  );
  test(
    'due catchup is atomic and repeated concurrent checks never duplicate',
    () async {
      await store.saveRecurring(rule(), today: start);
      expect(store.entries, isEmpty);
      await Future.wait([
        store.processRecurring(today: DateTime(2024, 3, 31)),
        store.processRecurring(today: DateTime(2024, 3, 31)),
      ]);
      await store.refresh();
      expect(store.entries, hasLength(3));
      expect(store.recurringOccurrences, hasLength(3));
      expect(
        store.entries.map((e) => dayKey(e.date)),
        containsAll(['2024-01-31', '2024-02-29', '2024-03-31']),
      );
      expect(accountBalance(bank, store.entries, DateTime(2024, 3, 31)), 20000);
      expect(store.recurringRules.single.nextDate, DateTime(2024, 4, 30));
    },
  );
  test(
    'pause skips paused months, resume posts only the new next date',
    () async {
      await store.saveRecurring(rule(), today: start);
      final id = store.recurringRules.single.id!;
      await store.setRecurringActive(id, false, today: start);
      await store.processRecurring(today: DateTime(2024, 3, 31));
      expect(store.entries, isEmpty);
      await store.setRecurringActive(id, true, today: DateTime(2024, 3, 31));
      expect(store.entries, hasLength(1));
      expect(store.entries.single.date, DateTime(2024, 3, 31));
    },
  );
  test('failed payments remain unpaid, retry once funded, and deletion never recreates', () async {
    await store.saveRecurring(rule(amount: 60000), today: start);
    await store.processRecurring(today: DateTime(2024, 1, 31));
    expect(store.entries, isEmpty);
    expect(store.recurringOccurrences.single.status, 'failed');
    expect(
      store.recurringOccurrences.single.error,
      contains('Insufficient funds'),
    );
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.income,
        amount: 20000,
        currency: Currency.eur,
        date: start,
        description: 'Funding',
        category: 'Other',
        accountId: bank.id,
      ),
    );
    final occurrenceId = store.recurringOccurrences.single.id;
    await store.retryRecurring(occurrenceId);
    await store.retryRecurring(occurrenceId);
    expect(store.entries, hasLength(2));
    expect(store.recurringOccurrences.single.status, 'posted');
    final transactionId = store.recurringOccurrences.single.transactionId!;
    await store.deleteEntry(transactionId);
    await store.processRecurring(today: DateTime(2024, 1, 31));
    await store.retryRecurring(occurrenceId);
    expect(store.entries, hasLength(1));
    expect(store.recurringOccurrences.single.transactionId, isNull);
  });
  test('price edits affect future payments, end date stops, archived rules stay stopped', () async {
    await store.saveRecurring(rule(), today: start);
    await store.processRecurring(today: DateTime(2024, 1, 31));
    final id = store.recurringRules.single.id!;
    await store.saveRecurring(
      rule(
        id: id,
        amount: 12000,
        next: DateTime(2024, 2, 29),
        end: DateTime(2024, 2, 29),
      ),
      today: DateTime(2024, 2, 1),
    );
    await store.processRecurring(today: DateTime(2024, 5, 31));
    expect(store.entries.map((e) => e.amount), containsAll([10000, 12000]));
    expect(store.entries, hasLength(2));
    expect(store.recurringRules.single.active, isFalse);
    await store.archiveRecurring(id);
    await store.processRecurring(today: DateTime(2025, 1, 1));
    expect(store.recurringRules, isEmpty);
    expect(store.entries, hasLength(2));
  });
  test('a newly blocked account causes an unpaid bill, and new past schedules are rejected', () async {
    await expectLater(
      store.saveRecurring(rule(), today: DateTime(2024, 2, 1)),
      throwsArgumentError,
    );
    await store.saveRecurring(rule(), today: start);
    await store.updateAccount(
      Account(
        id: bank.id,
        name: bank.name,
        currency: Currency.eur,
        opening: bank.opening,
        asOf: start,
        includeOnAsOf: true,
        available: false,
      ),
    );
    await store.processRecurring(today: DateTime(2024, 1, 31));
    expect(store.entries, isEmpty);
    expect(store.recurringOccurrences.single.error, contains('blocked'));
    await store.skipRecurring(store.recurringOccurrences.single.id);
    await store.retryRecurring(store.recurringOccurrences.single.id);
    expect(store.recurringOccurrences.single.status, 'skipped');
    expect(store.entries, isEmpty);
  });
}
