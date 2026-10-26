import 'ledger.dart';

class LedgerIndex {
  LedgerIndex(Iterable<LedgerEntry> entries)
    : entries = List.unmodifiable(entries) {
    for (final entry in this.entries) {
      (_months[(entry.date.year, entry.date.month)] ??= []).add(entry);
      _searchText.add(
        '${entry.description} ${entry.notes} ${entry.category}'.toLowerCase(),
      );
    }
  }

  final List<LedgerEntry> entries;
  final _months = <(int, int), List<LedgerEntry>>{};
  final _summaries = <(int, int), MonthlyLedger>{};
  final _searchText = <String>[];
  String? _lastQuery;
  EntryType? _lastType;
  List<LedgerEntry>? _lastResult;

  MonthlyLedger forMonth(DateTime month) {
    final key = (month.year, month.month);
    return _summaries.putIfAbsent(
      key,
      () => MonthlyLedger(_months[key] ?? const []),
    );
  }

  List<LedgerEntry> search({String query = '', EntryType? type}) {
    final normalized = query.toLowerCase();
    if (normalized.isEmpty && type == null) return entries;
    if (_lastQuery == normalized && _lastType == type) return _lastResult!;
    _lastQuery = normalized;
    _lastType = type;
    return _lastResult = List.unmodifiable([
      for (var i = 0; i < entries.length; i++)
        if ((type == null || entries[i].type == type) &&
            _searchText[i].contains(normalized))
          entries[i],
    ]);
  }
}

class MonthlyLedger {
  MonthlyLedger(Iterable<LedgerEntry> entries)
    : entries = List.unmodifiable(entries) {
    final spending = <LedgerEntry>[];
    final income = <LedgerEntry>[];
    final totals = <Currency, Totals>{};
    final categories = <(Currency, String), int>{};
    for (final entry in this.entries) {
      (totals[entry.currency] ??= Totals()).add(entry);
      switch (entry.type) {
        case EntryType.expense || EntryType.refund:
          spending.add(entry);
          final key = (entry.currency, entry.category);
          categories.update(
            key,
            (value) => value + _spendingAmount(entry),
            ifAbsent: () => _spendingAmount(entry),
          );
        case EntryType.income:
          income.add(entry);
        case EntryType.transfer:
          break;
      }
    }
    spendingEntries = List.unmodifiable(spending);
    incomeEntries = List.unmodifiable(income);
    totalsByCurrency = Map.unmodifiable(totals);
    spendingByCategory = Map.unmodifiable(categories);
  }

  final List<LedgerEntry> entries;
  late final List<LedgerEntry> spendingEntries;
  late final List<LedgerEntry> incomeEntries;
  late final Map<Currency, Totals> totalsByCurrency;
  late final Map<(Currency, String), int> spendingByCategory;
  Totals totalsFor(Currency currency) => totalsByCurrency[currency] ?? Totals();
  Totals get eurTotals => totalsByCurrency[Currency.eur] ?? Totals();

  static int _spendingAmount(LedgerEntry entry) =>
      entry.type == EntryType.refund ? -entry.amount : entry.amount;
}

class AccountBalances {
  AccountBalances(
    Iterable<Account> accounts,
    Iterable<LedgerEntry> entries,
    DateTime through,
  ) {
    final byId = {for (final account in accounts) account.id: account};
    final starts = {
      for (final account in accounts) account.id: dateOnly(account.asOf),
    };
    final balances = {
      for (final account in accounts)
        if (account.id != null) account.id!: account.opening,
    };
    final end = dateOnly(through);

    void apply(int? id, LedgerEntry entry, int change) {
      final account = byId[id];
      if (id == null || account == null || entry.currency != account.currency) {
        return;
      }
      final start = starts[id]!;
      if (account.includeOnAsOf
          ? entry.date.isBefore(start)
          : !entry.date.isAfter(start)) {
        return;
      }
      balances[id] = balances[id]! + change;
    }

    for (final entry in entries) {
      if (entry.date.isAfter(end)) continue;
      apply(entry.accountId, entry, entry.accountChange);
      if (entry.type == EntryType.transfer) {
        apply(entry.destinationId, entry, entry.amount);
      }
    }

    byAccount = Map.unmodifiable(balances);
    var totalWealth = 0;
    var totalAvailable = 0;
    for (final account in accounts) {
      final balance = balances[account.id] ?? account.opening;
      totalWealth += balance;
      if (account.available) totalAvailable += balance;
    }
    wealth = totalWealth;
    available = totalAvailable;
  }

  late final Map<int, int> byAccount;
  late final int wealth;
  late final int available;
  int get blocked => wealth - available;
}
