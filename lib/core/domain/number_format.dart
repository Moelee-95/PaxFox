/// Fixed comma grouping without converting exact ledger amounts to doubles.
String groupDigits(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

String formatInteger(int value) =>
    '${value < 0 ? '-' : ''}${groupDigits(value.abs().toString())}';

/// UI uses comma grouping and dot decimals. Unambiguous decimal-comma input
/// remains accepted; e.g. 12,50 becomes 12.50, while 1,234 means 1234.
String normalizeAmountInput(String input) {
  final text = input.trim();
  if (RegExp(r'^-?\d{1,3}(?:,\d{3})+(?:\.\d*)?$').hasMatch(text)) {
    return text.replaceAll(',', '');
  }
  if (RegExp(r'^-?\d*,\d*$').hasMatch(text)) {
    return text.replaceFirst(',', '.');
  }
  return text;
}
