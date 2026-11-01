import 'dart:convert';

import 'package:csv/csv.dart';

import '../domain/ledger.dart';

class CsvTransactionRow {
  const CsvTransactionRow({required this.number, required this.entry});
  final int number;
  final LedgerEntry entry;
}

class CsvPreview {
  const CsvPreview(this.rows, this.errors, {this.hasAssignments = false});
  final List<CsvTransactionRow> rows;
  final List<String> errors;
  final bool hasAssignments;
}

class TransactionCsv {
  static const headers = [
    'Date',
    'Details',
    'Category',
    'Cost',
    'Notes more info',
  ];
  static const maxBytes = 5 * 1024 * 1024;
  static const maxRows = 5000;
  static const accountHeaders = [
    ...headers,
    'Account',
    'Type',
    'Destination account',
    'Currency',
  ];

  static String encode(
    Iterable<LedgerEntry> entries, {
    List<Account>? accounts,
  }) {
    final byId = {for (final a in accounts ?? <Account>[]) a.id: a};
    final nameCounts = <String, int>{};
    for (final a in byId.values) {
      final name = a.name.trim().toLowerCase();
      nameCounts[name] = (nameCounts[name] ?? 0) + 1;
    }
    String accountName(int? id) {
      if (id == null) return '';
      final account = byId[id];
      if (account == null) {
        throw const FormatException('An exported account no longer exists.');
      }
      if (nameCounts[account.name.trim().toLowerCase()] != 1) {
        throw FormatException(
          'Rename duplicate accounts named "${account.name}" before exporting.',
        );
      }
      return account.name;
    }

    return Csv(addBom: true).encode([
      accounts == null ? headers : accountHeaders,
      for (final e in entries)
        [
          '${e.date.day}.${e.date.month}.${e.date.year >= 2000 && e.date.year <= 2099 ? (e.date.year % 100).toString().padLeft(2, '0') : e.date.year.toString().padLeft(4, '0')}',
          e.description,
          e.category,
          '${e.currency.symbol}${e.currency.format(e.amount)}',
          e.notes,
          if (accounts != null) ...[
            accountName(e.accountId),
            e.type.name,
            accountName(e.destinationId),
            e.currency.code,
          ],
        ],
    ]);
  }

  static CsvPreview decode(
    List<int> bytes,
    EntryType? type,
    int? accountId, {
    Currency currency = Currency.eur,
    List<Account> accounts = const [],
  }) {
    if (bytes.length > maxBytes) {
      throw const FormatException('Choose a CSV smaller than 5 MB.');
    }
    String text;
    try {
      text = utf8.decode(bytes).replaceFirst(RegExp(r'^\uFEFF'), '');
    } on FormatException {
      throw const FormatException(
        'Save the CSV with UTF-8 encoding and try again.',
      );
    }
    // The decoder tolerates an unterminated quoted field. Reject that case
    // explicitly rather than silently combining several transactions.
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      if (text[i] != '"') continue;
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        i++;
      } else {
        quoted = !quoted;
      }
    }
    if (quoted) {
      throw const FormatException(
        'A quoted CSV field is not closed. Check the quotation marks.',
      );
    }
    final records = Csv(skipEmptyLines: false).decode(text);
    if (records.isEmpty) throw const FormatException('The CSV is empty.');
    final header = records.first
        .map((v) => v.toString().trim().toLowerCase())
        .toList();
    final hasAssignments =
        header.contains('account') || header.contains('type');
    final expected = hasAssignments ? accountHeaders : headers;
    if (header.length != expected.length ||
        header.toSet().length != header.length ||
        expected.any((h) => !header.contains(h.toLowerCase()))) {
      throw FormatException('Expected columns: ${expected.join(', ')}.');
    }
    if (!hasAssignments && type == EntryType.transfer) {
      throw const FormatException(
        'Transfers need Account, Type, Destination account and Currency columns.',
      );
    }
    final indices = expected
        .map((h) => header.indexOf(h.toLowerCase()))
        .toList();
    final accountsByName = <String, List<Account>>{};
    for (final a in accounts) {
      (accountsByName[a.name.trim().toLowerCase()] ??= []).add(a);
    }
    int? resolveAccount(String name) {
      if (name.trim().isEmpty) return null;
      final matches = accountsByName[name.trim().toLowerCase()] ?? const [];
      if (matches.length != 1) {
        throw FormatException(
          matches.isEmpty
              ? 'Account "$name" was not found. Add it in Accounts first.'
              : 'Account "$name" is ambiguous. Give the accounts different names.',
        );
      }
      if (matches.single.currency != currency) {
        throw const FormatException('Account must use the app currency.');
      }
      return matches.single.id;
    }

    if (records.length > maxRows + 2) {
      throw const FormatException('Import up to 5,000 rows at a time.');
    }
    final rows = <CsvTransactionRow>[];
    final errors = <String>[];
    for (var i = 1; i < records.length; i++) {
      final record = records[i];
      if (record.every((v) => v.toString().trim().isEmpty)) continue;
      if (rows.length + errors.length >= maxRows) {
        throw const FormatException('Import up to 5,000 rows at a time.');
      }
      try {
        if (record.length != expected.length) {
          throw FormatException(
            'Expected ${expected.length} columns. Quote prices containing commas.',
          );
        }
        final fields = indices.map((j) => record[j].toString()).toList();
        if (fields[1].trim().isEmpty) {
          throw const FormatException('Details are required.');
        }
        final rowType = hasAssignments
            ? EntryType.values
                  .where((t) => t.name == fields[6].trim().toLowerCase())
                  .firstOrNull
            : type ?? EntryType.expense;
        if (rowType == null) {
          throw const FormatException(
            'Type must be expense, income, refund or transfer.',
          );
        }
        if (hasAssignments && fields[8].trim().toUpperCase() != currency.code) {
          throw FormatException(
            'Currency must be ${currency.code}; amounts are not converted.',
          );
        }
        final sourceId = hasAssignments ? resolveAccount(fields[5]) : accountId;
        final destinationId = hasAssignments ? resolveAccount(fields[7]) : null;
        if (rowType == EntryType.transfer &&
            (sourceId == null ||
                destinationId == null ||
                sourceId == destinationId)) {
          throw const FormatException(
            'Transfers require two different accounts.',
          );
        }
        if (rowType != EntryType.transfer && destinationId != null) {
          throw const FormatException(
            'Only transfers have a destination account.',
          );
        }
        if (rowType != EntryType.transfer && fields[2].trim().isEmpty) {
          throw const FormatException('Category is required.');
        }
        rows.add(
          CsvTransactionRow(
            number: i + 1,
            entry: LedgerEntry(
              type: rowType,
              amount: parseCost(fields[3], currency: currency),
              currency: currency,
              date: parseDate(fields[0]),
              description: fields[1].trim(),
              category: rowType == EntryType.transfer
                  ? 'Transfer'
                  : fields[2].trim(),
              accountId: sourceId,
              destinationId: destinationId,
              notes: fields[4],
            ),
          ),
        );
      } on FormatException catch (e) {
        errors.add('Row ${i + 1}: ${e.message}');
      }
    }
    if (rows.isEmpty && errors.isEmpty) {
      errors.add('The CSV contains no transactions.');
    }
    return CsvPreview(rows, errors, hasAssignments: hasAssignments);
  }

  static DateTime parseDate(String text) {
    final value = text.trim();
    final local = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{2}|\d{4})$')
        .firstMatch(value);
    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (local == null && iso == null) {
      throw const FormatException(
        'Date must be D.M.YY, D.M.YYYY or YYYY-MM-DD.',
      );
    }
    final day = int.parse(local?[1] ?? iso![3]!);
    final month = int.parse(local?[2] ?? iso![2]!);
    var year = int.parse(local?[3] ?? iso![1]!);
    if (local != null && local[3]!.length == 2) year += 2000;
    final date = DateTime(year, month, day);
    if (year < 1900 ||
        year > 9999 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const FormatException('Date is not a valid calendar date.');
    }
    return date;
  }

  static int parseCost(String text, {Currency currency = Currency.eur}) {
    var value = text
        .trim()
        .replaceFirst(
          RegExp(
            '^(?:${RegExp.escape(currency.symbol.trim())}|${currency.code})\\s*',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(
            '\\s*(?:${RegExp.escape(currency.symbol.trim())}|${currency.code})\$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    // Accept plain decimals and explicitly grouped German/English amounts.
    if (RegExp('^\\d{1,3}(?:\\.\\d{3})+,\\d{1,${currency.exponent}}\$')
        .hasMatch(value)) {
      value = value.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp('^\\d{1,3}(?:,\\d{3})+\\.\\d{1,${currency.exponent}}\$')
        .hasMatch(value)) {
      value = value.replaceAll(',', '');
    }
    try {
      final amount = currency.parse(value);
      if (amount > 0) return amount;
    } on FormatException {
      // Use the same field-specific message for malformed and zero values.
    }
    throw FormatException('Cost must be a positive ${currency.code} amount.');
  }
}
