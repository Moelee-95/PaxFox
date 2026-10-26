import 'package:flutter/material.dart';

import '../core/domain/ledger.dart';
import '../core/domain/ledger_queries.dart';
import '../core/presentation/month_selector.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.month,
    this.currency = Currency.eur,
    required this.summary,
    required this.tab,
    required this.onTabChanged,
    required this.onMonthChanged,
    required this.tileBuilder,
  });

  final DateTime month;
  final Currency currency;
  final MonthlyLedger summary;
  final int tab;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<DateTime> onMonthChanged;
  final Widget Function(LedgerEntry) tileBuilder;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.tab;
    _tabs = TabController(length: 2, vsync: this, initialIndex: _tab);
    _tabs.addListener(_tabChanged);
  }

  void _tabChanged() {
    if (_tab == _tabs.index) return;
    _tab = _tabs.index;
    widget.onTabChanged(_tab);
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spending = widget.summary.spendingEntries;
    final income = widget.summary.incomeEntries;
    final totals = widget.summary.totalsFor(widget.currency);
    Widget list(String view, List<LedgerEntry> entries, String empty) =>
        ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          key: PageStorageKey(
            'home-$view-${widget.month.year}-${widget.month.month}',
          ),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          itemCount: entries.isEmpty ? 1 : entries.length,
          itemBuilder: (_, index) => entries.isEmpty
              ? Padding(padding: const EdgeInsets.all(20), child: Text(empty))
              : widget.tileBuilder(entries[index]),
        );
    return Column(
      children: [
        MonthSelector(month: widget.month, onChanged: widget.onMonthChanged),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: TabBar(
              controller: _tabs,
              padding: const EdgeInsets.all(4),
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              labelColor: Theme.of(context).colorScheme.onSurface,
              unselectedLabelColor: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
              splashBorderRadius: BorderRadius.circular(20),
              tabs: [
                for (final tab in [
                  (
                    label: 'Expenses',
                    amount: totals.spending,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.red.shade300
                        : Colors.red.shade700,
                  ),
                  (
                    label: 'Income',
                    amount: totals.income,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.green.shade400
                        : Colors.green.shade700,
                  ),
                ])
                  Tab(
                    height: 48 * MediaQuery.textScalerOf(context).scale(1),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          tab.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          widget.currency.display(tab.amount),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: tab.color,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              list(
                'expenses',
                spending,
                'No expenses or refunds in this month. Tap + to add one.',
              ),
              list(
                'income',
                income,
                'No income in this month. Tap + to add one.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
