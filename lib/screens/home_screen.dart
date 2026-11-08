import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../core/domain/ledger.dart';
import '../core/domain/number_format.dart';
import '../core/domain/ledger_queries.dart';
import '../core/presentation/month_selector.dart';
import '../core/presentation/retained_page.dart';
import 'monthly_overview.dart';
import '../core/presentation/outlined_tabs.dart';
import '../core/presentation/transaction_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.month,
    this.categoryIcon = _defaultCategoryIcon,
    this.categoryColor,
    this.currency = Currency.eur,
    required this.summary,
    required this.tab,
    required this.onTabChanged,
    required this.onMonthChanged,
    required this.tileBuilder,
    this.invoiceGroups = const {},
    this.selectedCategory,
    required this.onCategoryChanged,
    this.onOverviewDragStart,
    this.onOverviewDragUpdate,
    this.onOverviewDragEnd,
  });

  static IconData _defaultCategoryIcon(String _) => Icons.category_outlined;
  final IconData Function(String) categoryIcon;
  final Color? Function(String)? categoryColor;
  final String? selectedCategory;
  final ValueChanged<String?> onCategoryChanged;
  final GestureDragStartCallback? onOverviewDragStart;
  final GestureDragUpdateCallback? onOverviewDragUpdate;
  final GestureDragEndCallback? onOverviewDragEnd;
  final DateTime month;
  final Currency currency;
  final MonthlyLedger summary;
  final int tab;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<DateTime> onMonthChanged;
  final Widget Function(LedgerEntry) tileBuilder;
  final Map<int, InvoiceGroupInfo> invoiceGroups;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _tab;
  bool _startedOnInfo = false;
  bool _forwardingDrag = false;
  bool _draggingTabs = false;

  bool _handleTabScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      // Prepare the incoming page before a finger reveals it. Otherwise only
      // the active tab needs new month data and selection/layout updates.
      if (!_draggingTabs) setState(() => _draggingTabs = true);
      _startedOnInfo = _tabs.index == 2 && !_tabs.indexIsChanging;
    } else if (notification is OverscrollNotification &&
        _startedOnInfo &&
        widget.onOverviewDragStart != null &&
        notification.dragDetails != null &&
        (_forwardingDrag || notification.overscroll > 0)) {
      final details = notification.dragDetails!;
      if (!_forwardingDrag) {
        _forwardingDrag = true;
        widget.onOverviewDragStart!(
          DragStartDetails(
            globalPosition: details.globalPosition - details.delta,
            localPosition: details.localPosition - details.delta,
            sourceTimeStamp: details.sourceTimeStamp,
          ),
        );
      }
      // Only forward the distance rejected by the inner pager at its edge.
      widget.onOverviewDragUpdate?.call(
        DragUpdateDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          delta: Offset(-notification.overscroll, 0),
          primaryDelta: -notification.overscroll,
          sourceTimeStamp: details.sourceTimeStamp,
        ),
      );
    } else if (notification is ScrollEndNotification) {
      if (_draggingTabs) setState(() => _draggingTabs = false);
      if (_forwardingDrag) {
        _forwardingDrag = false;
        widget.onOverviewDragEnd?.call(
          notification.dragDetails ?? DragEndDetails(),
        );
      }
      _startedOnInfo = false;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.tab;
    _tabs = TabController(length: 3, vsync: this, initialIndex: _tab);
    _tabs.addListener(_tabChanged);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != _tabs.index) {
      _tab = widget.tab;
      _tabs.index = widget.tab;
    }
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
        CustomScrollView(
          // Keep a small scroll buffer without laying out several extra cards
          // every time the month changes. Rows are still built on demand.
          scrollCacheExtent: const ScrollCacheExtent.pixels(80),
          physics: const AlwaysScrollableScrollPhysics(),
          key: PageStorageKey(
            'home-$view-${widget.month.year}-${widget.month.month}',
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
              sliver: SliverTransactionList(
                entries: entries,
                tileBuilder: widget.tileBuilder,
                invoiceGroups: widget.invoiceGroups,
                emptyMessage: empty,
              ),
            ),
          ],
        );
    final tabHeight = 48 * MediaQuery.textScalerOf(context).scale(1);
    return Column(
      children: [
        MonthSelector(month: widget.month, onChanged: widget.onMonthChanged),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const infoWidth = 48.0;
              final moneyTabWidth = (constraints.maxWidth - 8 - infoWidth) / 2;
              return OutlinedTabs(
                controller: _tabs,
                colors: const [
                  OutlinedTabs.expense,
                  OutlinedTabs.income,
                  OutlinedTabs.overview,
                ],
                isScrollable: true,
                padding: const EdgeInsets.all(4),
                labelPadding: EdgeInsets.zero,
                tabs: [
                  for (final tab in [
                    (
                      label: 'Expenses',
                      amount: totals.spending,
                      color: OutlinedTabs.expense,
                    ),
                    (
                      label: 'Income',
                      amount: totals.income,
                      color: OutlinedTabs.income,
                    ),
                  ])
                    SizedBox(
                      width: moneyTabWidth,
                      child: Tab(
                        height: tabHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tab.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${widget.currency.symbol}${formatInteger(tab.amount ~/ widget.currency.scale)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: tab.color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    width: infoWidth,
                    child: Tab(
                      height: tabHeight,
                      child: const Tooltip(
                        message: 'Monthly overview',
                        child: Icon(
                          Icons.info_outline,
                          semanticLabel: 'Monthly overview',
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleTabScroll,
            child: TabBarView(
              physics: _HomeTabPhysics(lockAtEdge: () => _forwardingDrag),
              controller: _tabs,
              children: [
                RetainedPage(
                  active: _tab == 0 || _draggingTabs,
                  child: list(
                    'expenses',
                    spending,
                    'No expenses or refunds in this month. Tap + to add one.',
                  ),
                ),
                RetainedPage(
                  active: _tab == 1 || _draggingTabs,
                  child: list(
                    'income',
                    income,
                    'No income in this month. Tap + to add one.',
                  ),
                ),
                RetainedPage(
                  active: _tab == 2 || _draggingTabs,
                  child: MonthlyOverview(
                    summary: widget.summary,
                    currency: widget.currency,
                    categoryIcon: widget.categoryIcon,
                    categoryColor: widget.categoryColor,
                    selectedCategory: widget.selectedCategory,
                    onCategoryChanged: widget.onCategoryChanged,
                    tileBuilder: widget.tileBuilder,
                    invoiceGroups: widget.invoiceGroups,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Clamp the inner pager so its rejected distance can move the main pager.
// Once handed off, keep the info page fixed even if the finger reverses.
class _HomeTabPhysics extends ClampingScrollPhysics {
  const _HomeTabPhysics({required this.lockAtEdge, super.parent});
  final bool Function() lockAtEdge;
  @override
  _HomeTabPhysics applyTo(ScrollPhysics? ancestor) =>
      _HomeTabPhysics(lockAtEdge: lockAtEdge, parent: buildParent(ancestor));
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      lockAtEdge()
      ? value - position.pixels
      : super.applyBoundaryConditions(position, value);
}
