import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/freedom.dart';

class FreedomScreen extends StatefulWidget {
  const FreedomScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<FreedomScreen> createState() => _FreedomScreenState();
}

class _FreedomScreenState extends State<FreedomScreen> {
  bool loseSalary = false;
  FreedomPlan? _projectedPlan;
  bool? _projectedSalaryLoss;
  FreedomProjection? _projection;

  FreedomProjection _projectionFor(FreedomPlan plan) {
    if (_projectedPlan != plan || _projectedSalaryLoss != loseSalary) {
      _projection = projectFreedom(plan, loseSalary: loseSalary);
      _projectedPlan = plan;
      _projectedSalaryLoss = loseSalary;
    }
    return _projection!;
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.store.plan;
    if (plan == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cashflow & Financial Freedom',
                style: TextStyle(fontSize: 24),
              ),
              const SizedBox(height: 16),
              const Text(
                'Insufficient data. Enter your spending target, net passive income, eligible invested portfolio and available cash. These are separate assumptions; account cash is never automatically treated as invested.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: edit,
                child: const Text('Configure plan'),
              ),
            ],
          ),
        ),
      );
    }
    final projection = _projectionFor(plan);
    final now = projection.months.first;
    final currency = plan.currency;
    String money(int value) => currency.display(value);
    final draw =
        (BigInt.from(plan.portfolio) *
                BigInt.from(plan.withdrawalBps) ~/
                BigInt.from(120000))
            .toInt();
    final coverage = ((plan.passive + draw) * 10000 ~/ plan.spending) / 100;
    final net = (loseSalary ? 0 : plan.earned) + plan.passive - plan.spending;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Cashflow & Freedom', style: TextStyle(fontSize: 24)),
            ),
            IconButton(
              tooltip: 'Edit plan assumptions',
              onPressed: edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        const Text(
          'Educational estimates, not guaranteed outcomes. Values are manual assumptions in one currency. No FX conversions or account balances are inferred.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Scenario: loss of earned salary'),
          value: loseSalary,
          onChanged: (v) => setState(() => loseSalary = v),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Cashflow forecast', style: TextStyle(fontSize: 22)),
                Text('Monthly net before investments: ${money(net)}'),
                Text(
                  net >= 0
                      ? 'Cashflow break-even reached under these assumptions.'
                      : 'Spending exceeds current income.',
                ),
                Text('Monthly contribution: ${money(plan.contribution)}'),
                Text(
                  projection.runwayMonths == null
                      ? 'Currently self-funding under these assumptions.'
                      : 'Cash runway including contributions: ${projection.runwayMonths} whole months',
                ),
                Text(
                  projection.firstZeroCashDate == null
                      ? 'Cash does not reach zero within forecast.'
                      : 'Cash first reaches zero: ${dayKey(projection.firstZeroCashDate!)}',
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Freedom plan', style: TextStyle(fontSize: 22)),
                Text('Current FI coverage: ${coverage.toStringAsFixed(2)}%'),
                Text('Estimated portfolio target today: ${money(now.target)}'),
                Text('Illustrative portfolio draw/month: ${money(draw)}'),
                Text(
                  projection.firstFreedomDate == null
                      ? 'Not reached within forecast'
                      : 'First modeled FI month: ${dayKey(projection.firstFreedomDate!)}',
                ),
                if (projection.firstZeroCashDate != null)
                  const Text(
                    'Cash is depleted in this scenario. Later portfolio projections require continued external funding of the configured contribution; the FI date is conditional on that funding.',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Projected balances', style: TextStyle(fontSize: 22)),
        const Text(
          'Each row shows the start of that month. Negative cash indicates an unfunded shortfall.',
        ),
        for (final i in {
          0,
          3,
          6,
          12,
          24,
          60,
          plan.years * 12,
        }.where((i) => i < projection.months.length))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(dayKey(projection.months[i].date)),
            subtitle: Text(
              'Cash ${money(projection.months[i].cash)}\nPortfolio ${money(projection.months[i].portfolio)}\nFI target ${money(projection.months[i].target)}',
            ),
            isThreeLine: true,
          ),
        const ExpansionTile(
          title: Text('Formulas & assumptions'),
          children: [
            Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'FI target = max(0, monthly spending - net passive income) x 12 / withdrawal rate. Coverage = (passive income + portfolio x withdrawal rate / 12) / spending. Earned income is excluded from FI coverage. Runway = unrestricted cash / monthly burn, including contributions. Monthly return = annual nominal rate / 12; spending and passive income grow similarly. Growth rounds to minor units each month. Contributions continue throughout the horizon, even after FI; no retirement withdrawal simulation is performed. Net passive income must exclude property costs. Exclude property value, restricted funds and duplicate account cash from the eligible portfolio. Debt repayments must be included in spending.',
              ),
            ),
          ],
        ),
      ],
    );
  }

  void edit() => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => PlanForm(store: widget.store)),
  );
}

class PlanForm extends StatefulWidget {
  const PlanForm({super.key, required this.store});
  final LedgerStore store;
  @override
  State<PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends State<PlanForm> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  late Currency currency;
  late DateTime start;
  bool saving = false;
  String? error;
  static const moneyLabels = {
    'spending': 'Target monthly living expenses (include debt payments)',
    'passive': 'Net monthly passive income',
    'portfolio': 'Eligible invested portfolio',
    'contribution': 'Monthly investment contribution',
    'earned': 'Monthly earned income',
    'cash': 'Available unrestricted cash',
  };
  static const rateLabels = {
    'returnBps': 'Annual nominal investment return (%)',
    'inflationBps': 'Annual inflation (%)',
    'passiveGrowthBps': 'Annual passive income growth (%)',
    'withdrawalBps': 'Illustrative withdrawal rate (%)',
  };
  @override
  void initState() {
    super.initState();
    final plan = widget.store.plan;
    currency = plan?.currency ?? Currency.eur;
    start = plan?.start ?? DateTime(DateTime.now().year, DateTime.now().month);
    final values = plan?.toMap();
    for (final key in moneyLabels.keys) {
      fields[key] = TextEditingController(
        text: values == null ? '' : currency.format(values[key] as int),
      );
    }
    for (final key in rateLabels.keys) {
      fields[key] = TextEditingController(
        text: Currency.eur.format(
          (values?[key] as int?) ??
              switch (key) {
                'returnBps' => 500,
                'inflationBps' => 200,
                'withdrawalBps' => 400,
                _ => 0,
              },
        ),
      );
    }
    fields['years'] = TextEditingController(text: '${plan?.years ?? 30}');
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int rate(String key) {
    final input = fields[key]!.text.trim();
    return Currency.eur.parse(input.replaceFirst(RegExp(r'^-'), '')) *
        (input.startsWith('-') ? -1 : 1);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan assumptions')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Fill every balance and income explicitly; enter 0 when known to be zero. 4% withdrawal is an editable illustration. This model uses no live market data.',
          ),
          const Text('Currency: €'),
          ListTile(
            title: Text('Forecast start: ${dayKey(start)}'),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: start,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date != null && mounted) {
                setState(() => start = DateTime(date.year, date.month));
              }
            },
          ),
          for (final entry in moneyLabels.entries)
            TextFormField(
              controller: fields[entry.key],
              decoration: InputDecoration(labelText: entry.value),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (s) {
                try {
                  final n = currency.parse(s ?? '');
                  if (entry.key == 'spending' && n <= 0) {
                    return 'Target spending must be positive.';
                  }
                } on FormatException catch (e) {
                  return e.message;
                }
                return null;
              },
            ),
          for (final entry in rateLabels.entries)
            TextFormField(
              controller: fields[entry.key],
              decoration: InputDecoration(labelText: entry.value),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (_) {
                try {
                  final n = rate(entry.key);
                  final minimum = entry.key == 'withdrawalBps'
                      ? 1
                      : entry.key == 'inflationBps'
                      ? 0
                      : -10000;
                  if (n < minimum || n > 10000) {
                    return 'Use ${minimum / 100} to 100 percent.';
                  }
                } on FormatException catch (e) {
                  return e.message;
                }
                return null;
              },
            ),
          TextFormField(
            controller: fields['years'],
            decoration: const InputDecoration(
              labelText: 'Horizon (1–50 years)',
            ),
            keyboardType: TextInputType.number,
            validator: (s) {
              final n = int.tryParse(s ?? '');
              return n == null || n < 1 || n > 50 ? 'Use 1 to 50 years.' : null;
            },
          ),
          if (error != null) Text(error!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (!form.currentState!.validate()) {
                      return;
                    }
                    setState(() => saving = true);
                    try {
                      int money(String key) =>
                          currency.parse(fields[key]!.text);
                      await widget.store.savePlan(
                        FreedomPlan(
                          currency: currency,
                          start: start,
                          spending: money('spending'),
                          passive: money('passive'),
                          portfolio: money('portfolio'),
                          contribution: money('contribution'),
                          earned: money('earned'),
                          cash: money('cash'),
                          returnBps: rate('returnBps'),
                          inflationBps: rate('inflationBps'),
                          passiveGrowthBps: rate('passiveGrowthBps'),
                          withdrawalBps: rate('withdrawalBps'),
                          years: int.parse(fields['years']!.text),
                        ),
                      );
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          saving = false;
                          error = 'Could not save. Projection may exceed supported bounds; reduce inputs or horizon.';
                        });
                      }
                    }
                  },
            child: const Text('Save plan'),
          ),
        ],
      ),
    ),
  );
}
