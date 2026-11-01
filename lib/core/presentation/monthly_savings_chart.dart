import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import '../domain/ledger_queries.dart';

/// A bounded chart over existing indexed reports; never scans the ledger.
/// The owner refreshes it when its snapshot changes. Touch state stays local.
class MonthlySavingsChart extends StatefulWidget {
  const MonthlySavingsChart({
    super.key,
    required this.currency,
    required this.summaryForMonth,
    this.today,
  });

  final Currency currency;
  final MonthlyLedger Function(DateTime) summaryForMonth;
  final DateTime? today;

  @override
  State<MonthlySavingsChart> createState() => _MonthlySavingsChartState();
}

class _MonthlySavingsChartState extends State<MonthlySavingsChart> {
  static const names = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  DateTime get current {
    final date = widget.today ?? DateTime.now();
    return DateTime(date.year, date.month);
  }

  late DateTime end = current;
  late DateTime selected = end;

  void move(int count) => setState(() {
    final target = DateTime(end.year, end.month + count);
    end = target.isAfter(current) ? current : target;
    selected = end;
  });

  String monthName(DateTime month) => '${names[month.month - 1]} ${month.year}';
  String compact(double value) {
    final absolute = value.abs();
    if (absolute >= 1000000000000) {
      return '${(value / 1000000000000).toStringAsFixed(1)}T';
    }
    if (absolute >= 1000000000) {
      return '${(value / 1000000000).toStringAsFixed(1)}B';
    }
    if (absolute >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (absolute >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(
      absolute < 10 && value != value.roundToDouble() ? 2 : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const count = 6;
        final denseText = MediaQuery.textScalerOf(context)
            .clamp(maxScaleFactor: 1.15);
        final months = List.generate(
          count,
          (i) => DateTime(end.year, end.month - count + 1 + i),
        );
        final totals = [
          for (final month in months)
            widget.summaryForMonth(month).totalsFor(widget.currency),
        ];
        final selectedIndex = months.indexOf(selected);
        final index = selectedIndex < 0 ? count - 1 : selectedIndex;
        final active = totals[index];
        final values = [
          for (final total in totals) total.net / widget.currency.scale,
        ];
        final low = values.fold<double>(0, math.min);
        final high = values.fold<double>(0, math.max);
        final padding = math.max((high - low) * .15, 1.0);
        final negative = colors.error;
        final positive = colors.primary;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Monthly savings',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Earlier months',
                      onPressed: end.year > 1 ? () => move(-count) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'Later months',
                      onPressed: end.isBefore(current)
                          ? () => move(count)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Text(
                  '${monthName(months.first)} - ${monthName(end)} | ${widget.currency.code}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                RepaintBoundary(
                  child: MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: denseText),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 190,
                        child: BarChart(
                          BarChartData(
                            minY: low < 0 ? low - padding : 0,
                            maxY: high + padding,
                            alignment: BarChartAlignment.spaceAround,
                            borderData: FlBorderData(show: false),
                            gridData: FlGridData(
                              drawVerticalLine: false,
                              getDrawingHorizontalLine: (value) => FlLine(
                                color: value == 0
                                    ? colors.outline
                                    : colors.outlineVariant.withValues(
                                        alpha: .5,
                                      ),
                                strokeWidth: 1,
                              ),
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: false,
                                  reservedSize: 0,
                                ),
                              ),
                            ),
                            barTouchData: BarTouchData(
                              touchCallback: (event, response) {
                                final touched =
                                    response?.spot?.touchedBarGroupIndex;
                                if (event.isInterestedForInteractions &&
                                    touched != null &&
                                    months[touched] != selected) {
                                  setState(() => selected = months[touched]);
                                }
                              },
                              touchTooltipData: BarTouchTooltipData(
                                fitInsideHorizontally: true,
                                fitInsideVertically: true,
                                getTooltipColor: (_) => colors.inverseSurface,
                                getTooltipItem:
                                    (
                                      group,
                                      groupIndex,
                                      rod,
                                      rodIndex,
                                    ) => BarTooltipItem(
                                      '${monthName(months[groupIndex])}\n${widget.currency.display(totals[groupIndex].net)}',
                                      TextStyle(
                                        color: colors.onInverseSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < count; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: values[i],
                                      width: constraints.maxWidth < 360
                                          ? 18
                                          : 22,
                                      label: BarChartRodLabel(
                                        show: true,
                                        text: compact(values[i]),
                                        style: TextStyle(
                                          color: colors.onSurface,
                                          fontSize: constraints.maxWidth < 360
                                              ? 10
                                              : 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        offset: const Offset(0, 5),
                                      ),
                                      color:
                                          (values[i] < 0 ? negative : positive)
                                              .withValues(
                                                alpha: i == index ? 1 : .5,
                                              ),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < count; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == index,
                          label:
                              '${monthName(months[i])}, net savings ${widget.currency.display(totals[i].net)}',
                          child: TextButton(
                            key: ValueKey(
                              'savings-month-${months[i].year}-${months[i].month}',
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              minimumSize: const Size(0, 48),
                              backgroundColor: i == index
                                  ? colors.primaryContainer
                                  : Colors.transparent,
                              foregroundColor: i == index
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                            ),
                            onPressed: () =>
                                setState(() => selected = months[i]),
                            child: Column(
                              children: [
                                Text(
                                  names[months[i].month - 1],
                                  textScaler: denseText,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '${months[i].year}',
                                  textScaler: denseText,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${monthName(months[index])}${months[index] == current ? ' - In progress' : ''}',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Net savings: ${widget.currency.display(active.net)}',
                          key: const ValueKey('selected-savings'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: active.net < 0 ? negative : positive,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 20,
                          runSpacing: 4,
                          children: [
                            Text(
                              'Income: ${widget.currency.display(active.income)}',
                            ),
                            Text(
                              'Expenses: ${widget.currency.display(active.spending)}',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  values.every((v) => v == 0) &&
                          totals.every((t) => t.income == 0 && t.spending == 0)
                      ? 'No income or expenses in this period. Tap a month to view its totals.'
                      : 'Income minus expenses. Refunds reduce expenses; transfers are excluded.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
