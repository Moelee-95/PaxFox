import 'ledger.dart';
import 'number_format.dart';

/// Positive rational rate: destination major units per one source major unit.
/// Inverses and cross rates keep their exact fractions until final money rounding.
class ConversionRate {
  ConversionRate._(this.numerator, this.denominator);
  final BigInt numerator, denominator;
  factory ConversionRate.parse(String input) {
    final text = normalizeAmountInput(input.trim());
    if (!RegExp(r'^\d+(?:\.\d{1,12})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter a positive rate with up to 12 decimals.',
      );
    }
    final parts = text.split('.');
    final fraction = parts.length > 1 ? parts[1] : '';
    final denominator = BigInt.from(10).pow(fraction.length);
    final numerator =
        BigInt.parse(parts[0]) * denominator +
        BigInt.parse(fraction.isEmpty ? '0' : fraction);
    if (numerator <= BigInt.zero ||
        numerator > BigInt.from(1000000000000) * denominator) {
      throw const FormatException(
        'Use a positive rate up to 1,000,000,000,000.',
      );
    }
    return ConversionRate._(numerator, denominator);
  }
  factory ConversionRate.fromAmounts(
    int source,
    Currency from,
    int target,
    Currency to,
  ) {
    if (source <= 0 || target <= 0) {
      throw const FormatException('Amounts must be positive.');
    }
    return ConversionRate._(
      BigInt.from(target) * BigInt.from(from.scale),
      BigInt.from(source) * BigInt.from(to.scale),
    );
  }
  ConversionRate get inverse => ConversionRate._(denominator, numerator);
  ConversionRate times(ConversionRate other) => ConversionRate._(
    numerator * other.numerator,
    denominator * other.denominator,
  );
  int convert(int amount, Currency from, Currency to) => ExchangeRate.rounded(
    BigInt.from(amount) * numerator * BigInt.from(to.scale),
    denominator * BigInt.from(from.scale),
  );
  String get text {
    const digits = 12;
    final scale = BigInt.from(10).pow(digits);
    final value =
        (numerator * scale + denominator ~/ BigInt.two) ~/ denominator;
    final tail = (value % scale)
        .toString()
        .padLeft(digits, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${value ~/ scale}${tail.isEmpty ? '' : '.$tail'}';
  }

  Map<String, String> toMap() => {
    'numerator': numerator.toString(),
    'denominator': denominator.toString(),
  };
  factory ConversionRate.fromMap(Map<String, dynamic> map) {
    final n = BigInt.parse(map['numerator'] as String),
        d = BigInt.parse(map['denominator'] as String);
    if (n <= BigInt.zero || d <= BigInt.zero) {
      throw const FormatException('Invalid saved rate.');
    }
    return ConversionRate._(n, d);
  }
}

class CurrencyExchangeTable {
  CurrencyExchangeTable(Map<String, String> rates)
    : rates = Map.unmodifiable(rates);
  final Map<String, String> rates;
  final Map<(Currency, Currency), ConversionRate?> _resolved = {};
  static String key(Currency from, Currency to) => '${from.name}_${to.name}';
  ConversionRate? rate(Currency from, Currency to) {
    final pair = (from, to);
    if (_resolved.containsKey(pair)) return _resolved[pair];
    return _resolved[pair] = _resolve(from, to);
  }

  ConversionRate? _resolve(Currency from, Currency to) {
    if (from == to) return ConversionRate.parse('1');
    final queue = <({Currency currency, ConversionRate rate})>[
      (currency: from, rate: ConversionRate.parse('1')),
    ];
    final visited = <Currency>{from};
    for (var i = 0; i < queue.length; i++) {
      final current = queue[i];
      for (final next in [to, ...Currency.values.where((c) => c != to)]) {
        if (visited.contains(next)) continue;
        final direct = rates[key(current.currency, next)];
        final reverse = rates[key(next, current.currency)];
        if (direct == null && reverse == null) continue;
        final edge = direct != null
            ? ConversionRate.parse(direct)
            : ConversionRate.parse(reverse!).inverse;
        final result = current.rate.times(edge);
        if (next == to) return result;
        visited.add(next);
        queue.add((currency: next, rate: result));
      }
    }
    return null;
  }

  int? convert(int amount, Currency from, Currency to) =>
      rate(from, to)?.convert(amount, from, to);
}
