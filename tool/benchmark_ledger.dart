import 'dart:io';

import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/ledger_queries.dart';

void main() {
  final through = DateTime(2026, 10, 25);
  final accounts = List.generate(
    100,
    (i) => Account(
      id: i + 1,
      name: 'Account $i',
      currency: Currency.eur,
      opening: 1000000,
      asOf: DateTime(2020),
      includeOnAsOf: true,
      available: i.isEven,
    ),
  );
  final entries = List.generate(
    100000,
    (i) => LedgerEntry(
      id: i + 1,
      type: EntryType.values[i % EntryType.values.length],
      amount: 100 + i % 10000,
      currency: Currency.eur,
      date: DateTime(2020, 1, 1 + i % 2400),
      description: 'Transaction $i',
      category: 'Category ${i % 20}',
      accountId: i % accounts.length + 1,
      destinationId: (i + 1) % accounts.length + 1,
    ),
  );

  int individualBalances() => accounts.fold(
    0,
    (total, account) => total + accountBalance(account, entries, through),
  );
  int batchBalances() => AccountBalances(accounts, entries, through).wealth;

  final expected = individualBalances();
  if (batchBalances() != expected) {
    throw StateError('Balance calculations disagree.');
  }

  stdout.writeln(
    'Synthetic ledger: ${accounts.length} accounts, ${entries.length} entries',
  );
  final individualTime = medianMicroseconds(individualBalances);
  final batchTime = medianMicroseconds(batchBalances);
  stdout.writeln('Per-account scans: ${individualTime / 1000} ms');
  stdout.writeln('Single ledger pass: ${batchTime / 1000} ms');
  stdout.writeln(
    'Balance calculation speedup: ${(individualTime / batchTime).toStringAsFixed(1)}x',
  );

  final index = LedgerIndex(entries);
  final month = DateTime(2025, 10);
  int scanMonth() {
    final totals = Totals();
    for (final entry in entries) {
      if (entry.date.year == month.year && entry.date.month == month.month) {
        totals.add(entry);
      }
    }
    return totals.net;
  }

  int indexedMonth() => index.forMonth(month).eurTotals.net;
  if (scanMonth() != indexedMonth()) {
    throw StateError('Monthly calculations disagree.');
  }
  final scanTime = medianMicroseconds(scanMonth, repetitions: 100);
  final cachedTime = medianMicroseconds(indexedMonth, repetitions: 100);
  stdout.writeln('100 monthly scans: ${scanTime / 1000} ms');
  stdout.writeln('100 cached month lookups: ${cachedTime / 1000} ms');
  stdout.writeln(
    'Index construction and first monthly lookup are excluded from cached timing.',
  );
}

int medianMicroseconds(int Function() calculate, {int repetitions = 1}) {
  for (var i = 0; i < 3; i++) {
    calculate();
  }
  final samples = <int>[];
  for (var sample = 0; sample < 7; sample++) {
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < repetitions; i++) {
      calculate();
    }
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}
