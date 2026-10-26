import 'ledger.dart';

DateTime monthlyDate(int year, int month, int day) {
  final normalized = DateTime(year, month);
  final last = DateTime(normalized.year, normalized.month + 1, 0).day;
  return DateTime(normalized.year, normalized.month, day.clamp(1, last));
}

DateTime firstMonthlyDate(DateTime start, int day) {
  final candidate = monthlyDate(start.year, start.month, day);
  return candidate.isBefore(dateOnly(start))
      ? monthlyDate(start.year, start.month + 1, day)
      : candidate;
}

class RecurringRule {
  const RecurringRule({
    this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.accountId,
    required this.day,
    required this.nextDate,
    this.interval = 1,
    this.active = true,
    this.archived = false,
    this.endDate,
    this.type = EntryType.expense,
    this.isAsset = false,
    this.isLiability = false,
  });
  final int? id;
  final String description, category;
  final int amount, accountId, day, interval;
  final DateTime nextDate;
  final DateTime? endDate;
  final bool active, archived;
  final bool isAsset, isLiability;
  final EntryType type;
  Map<String, Object?> toMap() => {
    'description': description,
    'type': type.name,
    'amount': amount,
    'category': category,
    'account_id': accountId,
    'day': day,
    'interval': interval,
    'next_date': dayKey(nextDate),
    'end_date': endDate == null ? null : dayKey(endDate!),
    'active': active ? 1 : 0,
    'archived': archived ? 1 : 0,
    'is_asset': isAsset ? 1 : 0,
    'is_liability': isLiability ? 1 : 0,
  };
  factory RecurringRule.fromMap(Map<String, Object?> row) => RecurringRule(
    id: row['id'] as int,
    type: EntryType.values.byName((row['type'] as String?) ?? 'expense'),
    description: row['description'] as String,
    amount: row['amount'] as int,
    category: row['category'] as String,
    accountId: row['account_id'] as int,
    day: row['day'] as int,
    interval: row['interval'] as int,
    nextDate: DateTime.parse(row['next_date'] as String),
    endDate: row['end_date'] == null
        ? null
        : DateTime.parse(row['end_date'] as String),
    active: row['active'] == 1,
    archived: row['archived'] == 1,
    isAsset: row['is_asset'] == 1,
    isLiability: row['is_liability'] == 1,
  );
}

class RecurringOccurrence {
  const RecurringOccurrence({
    required this.id,
    required this.ruleId,
    required this.date,
    required this.description,
    required this.amount,
    required this.accountId,
    required this.category,
    required this.status,
    this.error,
    this.transactionId,
    this.type = EntryType.expense,
  });
  final int id, ruleId, amount, accountId;
  final DateTime date;
  final String description, category, status;
  final String? error;
  final int? transactionId;
  final EntryType type;
  factory RecurringOccurrence.fromMap(Map<String, Object?> row) =>
      RecurringOccurrence(
        id: row['id'] as int,
        type: EntryType.values.byName((row['type'] as String?) ?? 'expense'),
        ruleId: row['rule_id'] as int,
        date: DateTime.parse(row['scheduled_date'] as String),
        description: row['description'] as String,
        amount: row['amount'] as int,
        accountId: row['account_id'] as int,
        category: row['category'] as String,
        status: row['status'] as String,
        error: row['error'] as String?,
        transactionId: row['transaction_id'] as int?,
      );
}
