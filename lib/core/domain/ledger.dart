enum EntryType { expense, income, refund, transfer }

enum Currency {
  eur('EUR', 2),
  usd('USD', 2),
  gbp('GBP', 2),
  iqd('IQD', 3);

  const Currency(this.code, this.exponent);
  final String code;
  String get symbol => switch (this) {
    Currency.eur => '\u20ac',
    Currency.usd => '\u0024',
    Currency.gbp => '\u00a3',
    Currency.iqd => 'IQD ',
  };
  String display(int minor) => '$symbol${format(minor)}';
  final int exponent;
  int get scale => exponent == 2 ? 100 : 1000;
  static final _amountPattern = RegExp(r'^(\d+)(?:[.,](\d+))?$');

  int parse(String input) {
    final match = _amountPattern.firstMatch(input.trim());
    if (match == null || (match[2]?.length ?? 0) > exponent) {
      throw FormatException(
        'Use a positive amount with up to $exponent decimals.',
      );
    }
    final value =
        BigInt.parse(match[1]!) * BigInt.from(scale) +
        BigInt.parse((match[2] ?? '').padRight(exponent, '0'));
    if (value > BigInt.from(9000000000000000)) {
      throw const FormatException('Amount exceeds the supported limit.');
    }
    return value.toInt();
  }

  String format(int minor) {
    final abs = minor.abs();
    return '${minor < 0 ? '-' : ''}${abs ~/ scale}.${(abs % scale).toString().padLeft(exponent, '0')}';
  }
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);
String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class LedgerEntry {
  const LedgerEntry({
    this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.date,
    required this.description,
    required this.category,
    this.accountId,
    this.destinationId,
    this.notes = '',
    this.createdAt,
  });
  final int? id;
  final EntryType type;
  final int amount;
  final Currency currency;
  final DateTime date;
  final DateTime? createdAt;
  final String description, category, notes;
  final int? accountId, destinationId;

  int get accountChange => switch (type) {
    EntryType.income || EntryType.refund => amount,
    EntryType.expense || EntryType.transfer => -amount,
  };

  Map<String, Object?> toMap() => {
    'type': type.name,
    'amount': amount,
    'currency': currency.name,
    'date': dayKey(date),
    'description': description,
    'category': category,
    'account_id': accountId,
    'destination_id': destinationId,
    'notes': notes,
  };
  factory LedgerEntry.fromMap(Map<String, Object?> row) => LedgerEntry(
    id: row['id'] as int,
    type: EntryType.values.byName(row['type'] as String),
    amount: row['amount'] as int,
    currency: Currency.values.byName(row['currency'] as String),
    date: DateTime.parse(row['date'] as String),
    description: row['description'] as String,
    category: row['category'] as String,
    accountId: row['account_id'] as int?,
    destinationId: row['destination_id'] as int?,
    notes: row['notes'] as String,
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
  );
}

enum AccountKind { cash, bank }

class Account {
  const Account({
    this.id,
    required this.name,
    required this.currency,
    required this.opening,
    required this.asOf,
    this.available = true,
    this.kind = AccountKind.bank,
    this.includeOnAsOf = false,
    this.allowOverdraft = false,
  });
  final int? id;
  final String name;
  final Currency currency;
  final int opening;
  final DateTime asOf;
  final bool available;
  final AccountKind kind;
  final bool includeOnAsOf;
  final bool allowOverdraft;
  bool get canOverdraw => kind == AccountKind.bank && allowOverdraft;
  Map<String, Object?> toMap() => {
    'name': name,
    'currency': currency.name,
    'opening': opening,
    'as_of': dayKey(asOf),
    'available': available ? 1 : 0,
    'kind': kind.name,
    'include_on_as_of': includeOnAsOf ? 1 : 0,
    'allow_overdraft': canOverdraw ? 1 : 0,
  };
  factory Account.fromMap(Map<String, Object?> row) => Account(
    id: row['id'] as int,
    name: row['name'] as String,
    currency: Currency.values.byName(row['currency'] as String),
    opening: row['opening'] as int,
    asOf: DateTime.parse(row['as_of'] as String),
    available: row['available'] == 1,
    kind: AccountKind.values.byName((row['kind'] as String?) ?? 'bank'),
    includeOnAsOf: row['include_on_as_of'] == 1,
    allowOverdraft: row['allow_overdraft'] == 1,
  );
}

class Totals {
  int income = 0;
  int spending = 0;
  int get net => income - spending;
  void add(LedgerEntry entry) {
    switch (entry.type) {
      case EntryType.income:
        income += entry.amount;
      case EntryType.expense:
        spending += entry.amount;
      case EntryType.refund:
        spending -= entry.amount;
      case EntryType.transfer:
        break;
    }
  }
}

int accountBalance(
  Account account,
  Iterable<LedgerEntry> entries,
  DateTime through,
) {
  var balance = account.opening;
  final start = dateOnly(account.asOf);
  final end = dateOnly(through);
  for (final entry in entries) {
    if ((account.includeOnAsOf
            ? entry.date.isBefore(start)
            : !entry.date.isAfter(start)) ||
        entry.date.isAfter(end)) {
      continue;
    }
    if (entry.currency != account.currency) {
      continue;
    }
    if (entry.accountId == account.id) {
      balance += entry.accountChange;
    }
    if (entry.type == EntryType.transfer && entry.destinationId == account.id) {
      balance += entry.amount;
    }
  }
  return balance;
}

class Debt {
  const Debt({
    this.id,
    required this.name,
    required this.amount,
    required this.currency,
    this.createdAt,
  });
  final int? id;
  final String name;
  final int amount;
  final Currency currency;
  final DateTime? createdAt;
  factory Debt.fromMap(Map<String, Object?> row) => Debt(
    id: row['id'] as int,
    name: row['name'] as String,
    amount: row['amount'] as int,
    currency: Currency.values.byName(row['currency'] as String),
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
  );
}
