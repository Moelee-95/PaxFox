import 'package:flutter/material.dart';

import '../core/domain/ledger_queries.dart';
import '../core/presentation/month_selector.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.month,
    required this.summary,
    required this.onMonthChanged,
    required this.hasLegacyCurrencyData,
  });

  final DateTime month;
  final MonthlyLedger summary;
  final ValueChanged<DateTime> onMonthChanged;
  final bool hasLegacyCurrencyData;

  Widget _summary(BuildContext context) => Column(
    children: [
      if (hasLegacyCurrencyData)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Existing data in other currencies is retained locally and excluded from these totals. No conversion has been applied.',
          ),
        ),
      if (summary.entries.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No transactions in this month. Add your first expense or income.',
          ),
        ),
      for (final entry in summary.totalsByCurrency.entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key.symbol,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Income: ${entry.key.display(entry.value.income)}'),
                Text(
                  'Spending after refunds: ${entry.key.display(entry.value.spending)}',
                ),
                Text('Net cashflow: ${entry.key.display(entry.value.net)}'),
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      MonthSelector(month: month, onChanged: onMonthChanged),
      _summary(context),
      const Text('Spending by category', style: TextStyle(fontSize: 22)),
      for (final item in summary.spendingByCategory.entries)
        ListTile(
          title: Text('${item.key.$1.symbol} · ${item.key.$2}'),
          trailing: Text(item.key.$1.display(item.value)),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Transfers are excluded. Refunds reduce spending. Future-dated entries appear in their selected month.',
        ),
      ),
    ],
  );
}
