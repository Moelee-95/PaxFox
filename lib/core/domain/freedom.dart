import 'ledger.dart';

// Rates use basis points; all balances use integer minor units. Monthly
// growth rounds half away from zero at each monthly boundary.
int grow(int value, int annualBasisPoints) {
  final numerator = BigInt.from(value) * BigInt.from(annualBasisPoints);
  final rounded = (numerator.abs() + BigInt.from(60000)) ~/ BigInt.from(120000);
  final result =
      BigInt.from(value) + (numerator.isNegative ? -rounded : rounded);
  if (result.abs() > BigInt.from(9000000000000000)) {
    throw const FormatException('Projection exceeds supported money bounds.');
  }
  return result.toInt();
}

class FreedomPlan {
  const FreedomPlan({
    required this.currency,
    required this.start,
    required this.spending,
    required this.passive,
    required this.portfolio,
    required this.contribution,
    required this.earned,
    required this.cash,
    this.returnBps = 500,
    this.inflationBps = 200,
    this.passiveGrowthBps = 0,
    this.withdrawalBps = 400,
    this.years = 30,
  });
  final Currency currency;
  final DateTime start;
  final int spending, passive, portfolio, contribution, earned, cash;
  final int returnBps, inflationBps, passiveGrowthBps, withdrawalBps, years;

  Map<String, Object?> toMap() => {
    'currency': currency.name,
    'start': dayKey(start),
    'spending': spending,
    'passive': passive,
    'portfolio': portfolio,
    'contribution': contribution,
    'earned': earned,
    'cash': cash,
    'returnBps': returnBps,
    'inflationBps': inflationBps,
    'passiveGrowthBps': passiveGrowthBps,
    'withdrawalBps': withdrawalBps,
    'years': years,
  };
  factory FreedomPlan.fromMap(Map<String, dynamic> m) => FreedomPlan(
    currency: Currency.values.byName(m['currency'] as String),
    start: DateTime.parse(m['start'] as String),
    spending: m['spending'] as int,
    passive: m['passive'] as int,
    portfolio: m['portfolio'] as int,
    contribution: m['contribution'] as int,
    earned: m['earned'] as int,
    cash: m['cash'] as int,
    returnBps: m['returnBps'] as int,
    inflationBps: m['inflationBps'] as int,
    passiveGrowthBps: m['passiveGrowthBps'] as int,
    withdrawalBps: m['withdrawalBps'] as int,
    years: m['years'] as int,
  );
}

class ProjectionMonth {
  const ProjectionMonth(
    this.date,
    this.portfolio,
    this.target,
    this.cash,
    this.spending,
    this.passive,
    this.covered,
  );
  final DateTime date;
  final int portfolio, target, cash, spending, passive;
  final bool covered;
}

class FreedomProjection {
  FreedomProjection(
    this.months,
    this.firstFreedomDate,
    this.firstZeroCashDate,
    this.runwayMonths,
  );
  final List<ProjectionMonth> months;
  final DateTime? firstFreedomDate, firstZeroCashDate;
  final int? runwayMonths;
}

FreedomProjection projectFreedom(FreedomPlan plan, {bool loseSalary = false}) {
  if (plan.spending <= 0 ||
      plan.portfolio < 0 ||
      plan.cash < 0 ||
      plan.passive < 0 ||
      plan.contribution < 0 ||
      plan.earned < 0 ||
      plan.withdrawalBps <= 0 ||
      plan.withdrawalBps > 10000 ||
      plan.years < 1 ||
      plan.years > 50 ||
      plan.returnBps < -10000 ||
      plan.returnBps > 10000 ||
      plan.inflationBps < 0 ||
      plan.inflationBps > 10000 ||
      plan.passiveGrowthBps < -10000 ||
      plan.passiveGrowthBps > 10000) {
    throw const FormatException(
      'Check positive spending, withdrawal rate, and scenario bounds.',
    );
  }
  var spending = plan.spending,
      passive = plan.passive,
      portfolio = plan.portfolio,
      cash = plan.cash;
  final earned = loseSalary ? 0 : plan.earned;
  final initialBurn = spending + plan.contribution - passive - earned;
  final runway = initialBurn > 0 ? cash ~/ initialBurn : null;
  DateTime? freedom, zeroCash;
  final months = <ProjectionMonth>[];
  for (var i = 0; i <= plan.years * 12; i++) {
    final date = DateTime(plan.start.year, plan.start.month + i, 1);
    final gap = (spending - passive).clamp(0, 9000000000000000);
    final numerator = BigInt.from(gap) * BigInt.from(12 * 10000);
    final target =
        ((numerator + BigInt.from(plan.withdrawalBps - 1)) ~/
                BigInt.from(plan.withdrawalBps))
            .toInt();
    final covered =
        BigInt.from(passive) * BigInt.from(120000) +
            BigInt.from(portfolio) * BigInt.from(plan.withdrawalBps) >=
        BigInt.from(spending) * BigInt.from(120000);
    if (covered) {
      freedom ??= date;
    }
    if (cash <= 0) {
      zeroCash ??= date;
    }
    months.add(
      ProjectionMonth(
        date,
        portfolio,
        target,
        cash,
        spending,
        passive,
        covered,
      ),
    );
    // Contributions are an explicit external funding assumption, not inferred
    // from account cash. Cashflow deducts them to avoid counting money twice.
    portfolio = grow(portfolio, plan.returnBps) + plan.contribution;
    cash += earned + passive - spending - plan.contribution;
    spending = grow(spending, plan.inflationBps);
    passive = grow(passive, plan.passiveGrowthBps);
    if ([
      portfolio,
      cash,
      spending,
      passive,
    ].any((v) => v.abs() > 9000000000000000)) {
      throw const FormatException('Projection exceeds supported money bounds.');
    }
  }
  return FreedomProjection(months, freedom, zeroCash, runway);
}
