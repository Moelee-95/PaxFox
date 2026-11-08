import 'dart:convert';

import 'exchange_rate.dart';
import 'number_format.dart';

export 'exchange_rate.dart';

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
  String display(int minor) => '$symbol${formatGrouped(minor)}';

  String formatGrouped(int minor) {
    final parts = format(minor).split('.');
    return '${groupDigits(parts[0])}.${parts[1]}';
  }

  int parseInput(String input) => parse(normalizeAmountInput(input));
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
    this.accountAmount,
    this.destinationAmount,
    this.fx,
  });
  final int? id;
  final EntryType type;
  final int amount;
  final Currency currency;
  final DateTime date;
  final DateTime? createdAt;
  final String description, category, notes;
  final int? accountId, destinationId;
  // Current native account units, distinct from the frozen reporting amount.
  final int? accountAmount, destinationAmount;
  final FxSnapshot? fx;

  LedgerEntry withAmounts({
    int? amount,
    int? accountAmount,
    int? destinationAmount,
    FxSnapshot? fx,
  }) => LedgerEntry(
    id: id,
    type: type,
    amount: amount ?? this.amount,
    currency: currency,
    date: date,
    description: description,
    category: category,
    accountId: accountId,
    destinationId: destinationId,
    notes: notes,
    createdAt: createdAt,
    accountAmount: accountAmount ?? this.accountAmount,
    destinationAmount: destinationAmount ?? this.destinationAmount,
    fx: fx ?? this.fx,
  );

  int changeFor(Account account) {
    var change = 0;
    if (accountId == account.id) {
      final native =
          accountAmount ?? (currency == account.currency ? amount : 0);
      change += (type == EntryType.income || type == EntryType.refund)
          ? native
          : -native;
    }
    if (type == EntryType.transfer && destinationId == account.id) {
      change +=
          destinationAmount ?? (currency == account.currency ? amount : 0);
    }
    return change;
  }

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
    'account_amount': accountAmount,
    'destination_amount': destinationAmount,
    'fx_snapshot': fx == null ? null : jsonEncode(fx!.toMap()),
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
    accountAmount: row['account_amount'] as int?,
    destinationAmount: row['destination_amount'] as int?,
    fx: row['fx_snapshot'] == null
        ? null
        : FxSnapshot.fromMap(
            jsonDecode(row['fx_snapshot'] as String) as Map<String, dynamic>,
          ),
  );
}

/// Immutable original input and bank amounts/rates, retained even if an account
/// later changes currency. Transfers show the actual pair supplied by the user.
class FxSnapshot {
  const FxSnapshot({
    required this.inputCurrency,
    required this.inputAmount,
    required this.sourceCurrency,
    required this.sourceAmount,
    required this.sourceRate,
    this.targetCurrency,
    this.targetAmount,
    this.targetRate,
  });
  final Currency inputCurrency, sourceCurrency;
  final int inputAmount, sourceAmount;
  final String sourceRate;
  final Currency? targetCurrency;
  final int? targetAmount;
  final String? targetRate;
  Map<String, Object?> toMap() => {
    'input_currency': inputCurrency.name,
    'input_amount': inputAmount,
    'source_currency': sourceCurrency.name,
    'source_amount': sourceAmount,
    'source_rate': sourceRate,
    'target_currency': targetCurrency?.name,
    'target_amount': targetAmount,
    'target_rate': targetRate,
  };
  factory FxSnapshot.fromMap(Map<String, dynamic> map) => FxSnapshot(
    inputCurrency: Currency.values.byName(map['input_currency'] as String),
    inputAmount: map['input_amount'] as int,
    sourceCurrency: Currency.values.byName(map['source_currency'] as String),
    sourceAmount: map['source_amount'] as int,
    sourceRate: map['source_rate'] as String,
    targetCurrency: map['target_currency'] == null
        ? null
        : Currency.values.byName(map['target_currency'] as String),
    targetAmount: map['target_amount'] as int?,
    targetRate: map['target_rate'] as String?,
  );
  String? get transferRate {
    if (targetCurrency == null || targetAmount == null || sourceAmount <= 0) {
      return null;
    }
    final numerator =
        BigInt.from(targetAmount!) *
        BigInt.from(sourceCurrency.scale) *
        BigInt.from(1000000000);
    final denominator =
        BigInt.from(sourceAmount) * BigInt.from(targetCurrency!.scale);
    final scaled = (numerator + denominator ~/ BigInt.two) ~/ denominator;
    final whole = scaled ~/ BigInt.from(1000000000);
    final tail = (scaled % BigInt.from(1000000000))
        .toString()
        .padLeft(9, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '1 ${sourceCurrency.code} = $whole${tail.isEmpty ? '' : '.$tail'} ${targetCurrency!.code}';
  }
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
    this.baseCurrency,
    this.exchangeRate = '1',
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
  final Currency? baseCurrency;
  final String exchangeRate;
  Currency get reportingCurrency => baseCurrency ?? currency;
  ExchangeRate get rate =>
      ExchangeRate.parse(currency == reportingCurrency ? '1' : exchangeRate);
  int toBase(int native) => currency == reportingCurrency
      ? native
      : rate.toBase(native, currency.scale, reportingCurrency.scale);
  int fromBase(int base) => currency == reportingCurrency
      ? base
      : rate.fromBase(base, reportingCurrency.scale, currency.scale);
  int convertTo(Account target, int native) => rate.convertTo(
    native,
    currency.scale,
    target.rate,
    target.currency.scale,
  );
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
    'base_currency': reportingCurrency.name,
    'exchange_rate': exchangeRate,
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
    baseCurrency: row['base_currency'] == null
        ? null
        : Currency.values.byName(row['base_currency'] as String),
    exchangeRate: row['exchange_rate'] as String? ?? '1',
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
    balance += entry.changeFor(account);
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
    this.isReceivable = false,
    this.deadline,
    this.deadlineAcknowledged,
  });
  final DateTime? deadline, deadlineAcknowledged;
  bool get hasPendingDeadline =>
      amount > 0 && deadline != null && deadlineAcknowledged != deadline;
  bool deadlineDue(DateTime now) =>
      hasPendingDeadline && !deadline!.isAfter(now);
  final bool isReceivable;
  final int? id;
  final String name;
  final int amount;
  final Currency currency;
  final DateTime? createdAt;
  factory Debt.fromMap(Map<String, Object?> row) => Debt(
    id: row['id'] as int,
    isReceivable: row['is_receivable'] == 1,
    name: row['name'] as String,
    amount: row['amount'] as int,
    currency: Currency.values.byName(row['currency'] as String),
    createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
    deadline: DateTime.tryParse(row['deadline'] as String? ?? ''),
    deadlineAcknowledged: DateTime.tryParse(
      row['deadline_acknowledged'] as String? ?? '',
    ),
  );
}
