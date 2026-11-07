import 'number_format.dart';

/// Foreign major units per one reporting-currency unit. All math is exact;
/// rounding happens once, to the destination minor unit, halfway away from zero.
class ExchangeRate {
  ExchangeRate._(this.numerator, this.denominator, this.value);
  final BigInt numerator, denominator;
  final String value;

  factory ExchangeRate.parse(String text) {
    final normalized = normalizeAmountInput(text.trim());
    if (!RegExp(r'^\d+(?:\.\d{1,9})?$').hasMatch(normalized)) {
      throw const FormatException(
        'Enter a positive rate with up to 9 decimals.',
      );
    }
    final parts = normalized.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final denominator = BigInt.from(10).pow(fraction.length);
    final numerator =
        BigInt.parse(parts[0]) * denominator +
        BigInt.parse(fraction.isEmpty ? '0' : fraction);
    if (numerator <= BigInt.zero ||
        numerator > BigInt.from(1000000000000) * denominator) {
      throw const FormatException(
        'Enter a rate greater than zero, up to 1,000,000,000,000.',
      );
    }
    final tail = fraction.replaceFirst(RegExp(r'0+$'), '');
    return ExchangeRate._(
      numerator,
      denominator,
      '${BigInt.parse(parts[0])}${tail.isEmpty ? '' : '.$tail'}',
    );
  }

  int fromBase(int amount, int baseScale, int foreignScale) => rounded(
    BigInt.from(amount) * numerator * BigInt.from(foreignScale),
    denominator * BigInt.from(baseScale),
  );

  int toBase(int amount, int foreignScale, int baseScale) => rounded(
    BigInt.from(amount) * denominator * BigInt.from(baseScale),
    numerator * BigInt.from(foreignScale),
  );

  int convertTo(int amount, int fromScale, ExchangeRate target, int toScale) =>
      rounded(
        BigInt.from(amount) *
            denominator *
            target.numerator *
            BigInt.from(toScale),
        numerator * target.denominator * BigInt.from(fromScale),
      );

  static int rounded(BigInt numerator, BigInt denominator) {
    final value = (numerator.abs() + denominator ~/ BigInt.two) ~/ denominator;
    if (value > BigInt.from(9000000000000000)) {
      throw const FormatException(
        'Converted amount exceeds the supported limit.',
      );
    }
    return (numerator.isNegative ? -value : value).toInt();
  }
}
