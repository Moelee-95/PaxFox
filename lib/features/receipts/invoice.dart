import 'dart:convert';

import '../../core/domain/ledger.dart';

class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.quantity,
    required this.total,
    this.category,
    this.unitPrice,
    this.edited = false,
    this.date,
  });
  final String description, quantity;
  final int? total, unitPrice;
  final String? category;
  final bool edited;
  final DateTime? date;
  InvoiceItem withDate(DateTime? value) => InvoiceItem(
    description: description,
    quantity: quantity,
    total: total,
    category: category,
    unitPrice: unitPrice,
    edited: edited,
    date: value,
  );
  Map<String, Object?> toMap() => {
    'description': description,
    'quantity': quantity,
    'total': total,
    'unit_price': unitPrice,
    'category': category,
    'edited': edited ? 1 : 0,
    'date': date == null ? null : dayKey(date!),
  };
  factory InvoiceItem.fromMap(Map<String, dynamic> row) => InvoiceItem(
    description: row['description'] as String? ?? '',
    quantity: row['quantity'] as String? ?? '',
    total: row['total'] as int?,
    unitPrice: row['unit_price'] as int?,
    category: row['category'] as String?,
    edited: row['edited'] == 1,
    date: invoiceDate(row['date'] ?? row['item_date']),
  );
}

class InvoiceDraft {
  const InvoiceDraft({
    this.type = EntryType.expense,
    this.merchant = '',
    this.multipleInvoices = false,
    this.date,
    this.currency,
    this.total,
    this.category,
    this.adjustment,
    this.adjustmentNote = '',
    this.items = const [],
    this.raw = '',
  });
  final EntryType type;
  final String merchant, adjustmentNote, raw;
  final bool multipleInvoices;
  final DateTime? date;
  final String? currency, category;
  final int? total, adjustment;
  final List<InvoiceItem> items;
  Map<String, Object?> toMap() => {
    'entry_type': type.name,
    'merchant': merchant,
    'multiple_invoices': multipleInvoices,
    'date': date == null ? null : dayKey(date!),
    'currency': currency,
    'total': total,
    'category': category,
    'adjustment': adjustment,
    'adjustment_note': adjustmentNote,
    'items': items.map((i) => i.toMap()).toList(),
    'raw': raw,
  };
  factory InvoiceDraft.fromMap(Map<String, dynamic> row) => InvoiceDraft(
    type: EntryType.values.byName(row['entry_type'] as String? ?? 'expense'),
    merchant: row['merchant'] as String? ?? '',
    multipleInvoices: row['multiple_invoices'] == true,
    date: row['date'] == null ? null : DateTime.parse(row['date'] as String),
    currency: row['currency'] as String?,
    total: row['total'] as int?,
    category: row['category'] as String?,
    adjustment: row['adjustment'] as int?,
    adjustmentNote: row['adjustment_note'] as String? ?? '',
    items: (row['items'] as List)
        .map((i) => InvoiceItem.fromMap(Map<String, dynamic>.from(i as Map)))
        .toList(),
    raw: row['raw'] as String? ?? '',
  );
}

int? extractedMoney(dynamic input, {Currency currency = Currency.eur}) {
  if (input is! String) {
    return null;
  }
  try {
    final negative = input.startsWith('-');
    return currency.parse(negative ? input.substring(1) : input) *
        (negative ? -1 : 1);
  } on FormatException {
    return null;
  }
}

DateTime? invoiceDate(dynamic input) {
  if (input is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
    return null;
  }
  final date = DateTime.tryParse(input);
  return date != null && dayKey(date) == input ? date : null;
}

InvoiceDraft parseInvoice(
  String raw,
  Set<String> categories, {
  Currency currency = Currency.eur,
  EntryType type = EntryType.expense,
}) {
  var text = raw
      .trim()
      .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '');
  final json = jsonDecode(text);
  if (json is! Map<String, dynamic> ||
      json['items'] is! List ||
      (json['items'] as List).length > 300) {
    throw const FormatException('Invalid invoice response.');
  }
  String? category(dynamic value) =>
      value is String && categories.contains(value) ? value : null;
  return InvoiceDraft(
    type: type,
    merchant: json['merchant'] is String ? json['merchant'] as String : '',
    multipleInvoices: json['multiple_invoices'] == true,
    date: invoiceDate(json['date']),
    currency: json['currency'] as String?,
    total: extractedMoney(json['total'], currency: currency),
    adjustment: extractedMoney(json['adjustment'], currency: currency),
    adjustmentNote: json['adjustment_note'] as String? ?? '',
    category: category(json['category']),
    raw: raw,
    items: (json['items'] as List)
        .where(
          (value) =>
              type != EntryType.income ||
              value is Map && value['entry_kind'] == 'income',
        )
        .map((value) {
          final item = Map<String, dynamic>.from(value as Map);
          return InvoiceItem(
            description: item['description'] as String? ?? '',
            quantity: type == EntryType.income
                ? '1'
                : item['quantity'] as String? ?? '',
            total: extractedMoney(item['line_total'], currency: currency),
            unitPrice: extractedMoney(item['unit_price'], currency: currency),
            category: category(item['category']),
            date:
                invoiceDate(item['date']) ??
                (json['multiple_invoices'] == true
                    ? null
                    : invoiceDate(json['date'])),
          );
        })
        .toList(),
  );
}

List<InvoiceItem> expandInvoiceItems(List<InvoiceItem> items) {
  final expanded = <InvoiceItem>[];
  for (final item in items) {
    final count =
        int.tryParse(item.quantity.replaceFirst(RegExp(r'[.,]0+$'), '')) ?? 1;
    if (count > 300) {
      throw ArgumentError(
        'An invoice can contain at most 300 individual items.',
      );
    }
    final repeats = count > 1 && count <= 300 ? count : 1;
    if (expanded.length + repeats > 300) {
      throw ArgumentError(
        'An invoice can contain at most 300 individual items.',
      );
    }
    for (var i = 0; i < repeats; i++) {
      final amount = item.total;
      final price = amount == null
          ? null
          : (amount.abs() ~/ repeats + (i < amount.abs() % repeats ? 1 : 0)) *
                (amount < 0 ? -1 : 1);
      expanded.add(
        InvoiceItem(
          description: item.description,
          quantity: '1',
          total: price,
          category: item.category,
          edited: item.edited,
          date: item.date,
        ),
      );
    }
  }
  return expanded;
}

String? invoiceItemError(
  InvoiceItem item,
  Set<String> categories, {
  EntryType type = EntryType.expense,
}) {
  final errors = <String>[];
  if (item.description.trim().isEmpty) {
    errors.add('Enter an item name.');
  }
  if (item.total == null || item.total!.abs() > 9000000000000000) {
    errors.add('Enter a valid price.');
  }
  if (type == EntryType.income && item.total != null && item.total! <= 0) {
    errors.add('Income must be a positive received amount.');
  }
  if (!categories.contains(item.category)) {
    errors.add('Select an available ${type.name} category.');
  }
  return errors.isEmpty ? null : errors.join('\n');
}

void validateInvoice(
  InvoiceDraft draft,
  Set<String> categories, {
  Currency currency = Currency.eur,
}) {
  if ((draft.type != EntryType.expense && draft.type != EntryType.income) ||
      (draft.type == EntryType.income && (draft.adjustment ?? 0) != 0) ||
      draft.currency != currency.code ||
      ((draft.multipleInvoices || draft.date == null) &&
          draft.items.any((item) => item.date == null)) ||
      (draft.date == null && (draft.adjustment ?? 0) != 0) ||
      draft.merchant.trim().isEmpty ||
      draft.total == null ||
      draft.total! <= 0 ||
      !categories.contains(draft.category) ||
      draft.items.isEmpty) {
    throw ArgumentError(
      'Review merchant, item dates, total, currency, category and items.',
    );
  }
  var sum = 0;
  for (final item in draft.items) {
    final itemError = invoiceItemError(item, categories, type: draft.type);
    if (itemError != null) {
      throw ArgumentError('Item ${draft.items.indexOf(item) + 1}: $itemError');
    }
    sum += item.total!;
  }
  if (sum + (draft.adjustment ?? 0) != draft.total) {
    throw ArgumentError(
      'Item totals plus adjustment must equal the charged total.',
    );
  }
  if ((draft.adjustment ?? 0) != 0 && draft.adjustmentNote.trim().isEmpty) {
    throw ArgumentError(
      'Explain the adjustment (tax, discount, tip or rounding).',
    );
  }
}
