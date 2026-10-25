import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/freedom.dart';
import 'package:moneva/core/domain/ledger.dart';

FreedomPlan plan({
  int portfolio = 0,
  int passive = 0,
  int earned = 0,
  int contribution = 0,
  int spending = 10000,
  int cash = 60000,
  int inflation = 0,
  int growth = 0,
}) => FreedomPlan(
  currency: Currency.eur,
  start: DateTime(2026, 10),
  spending: spending,
  passive: passive,
  portfolio: portfolio,
  contribution: contribution,
  earned: earned,
  cash: cash,
  returnBps: growth,
  inflationBps: inflation,
  years: 5,
);

void main() {
  test('exact FI target and never reached', () {
    final result = projectFreedom(plan());
    expect(result.months.first.target, 3000000);
    expect(result.firstFreedomDate, isNull);
    expect(result.runwayMonths, 6);
    expect(result.firstZeroCashDate, DateTime(2027, 4));
  });
  test('already FI and passive income reduces target', () {
    final result = projectFreedom(plan(portfolio: 1500000, passive: 5000));
    expect(result.months.first.target, 1500000);
    expect(result.firstFreedomDate, DateTime(2026, 10));
  });
  test(
    'contribution reaches first exact milestone without counting salary as FI',
    () {
      final result = projectFreedom(
        plan(portfolio: 2900000, contribution: 100000, earned: 200000),
      );
      expect(result.firstFreedomDate, DateTime(2026, 11));
      expect(result.runwayMonths, isNull);
      expect(projectFreedom(plan(earned: 1000000)).firstFreedomDate, isNull);
    },
  );
  test('inflation increases target and salary loss depletes cash', () {
    final result = projectFreedom(plan(earned: 20000, inflation: 1200));
    expect(result.months[1].spending, 10100);
    expect(result.months[1].target, 3030000);
    expect(
      projectFreedom(plan(earned: 20000), loseSalary: true).runwayMonths,
      6,
    );
  });
  test('zero target and invalid inputs rejected rather than inventing FI', () {
    expect(() => projectFreedom(plan(spending: 0)), throwsFormatException);
    expect(() => projectFreedom(plan(portfolio: -1)), throwsFormatException);
    expect(() => projectFreedom(plan(inflation: -1)), throwsFormatException);
  });
  test('monthly nominal growth rounds at currency boundary', () {
    expect(grow(10000, 1200), 10100);
    expect(grow(10000, -1200), 9900);
    expect(grow(1, 60000), 2);
  });
}
