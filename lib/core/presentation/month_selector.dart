import 'package:flutter/material.dart';

/// A real pager so the month follows the drag and settles like screen navigation.
class MonthSelector extends StatefulWidget {
  const MonthSelector({
    super.key,
    required this.month,
    required this.onChanged,
  });
  final DateTime month;
  final ValueChanged<DateTime> onChanged;
  @override
  State<MonthSelector> createState() => _MonthSelectorState();
}

class _MonthSelectorState extends State<MonthSelector> {
  static const center = 12000;
  late final DateTime origin = widget.month;
  late final PageController pages = PageController(initialPage: center);
  late int _targetPage = center;
  DateTime dateFor(int page) =>
      DateTime(origin.year, origin.month + page - center);
  @override
  void didUpdateWidget(covariant MonthSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target =
        center +
        (widget.month.year - origin.year) * 12 +
        widget.month.month -
        origin.month;
    if (oldWidget.month == widget.month) return;
    _targetPage = target;
    if (pages.hasClients && pages.page!.round() != target) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pages.hasClients) pages.jumpToPage(target);
      });
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void move(int delta) => pages.animateToPage(
    _targetPage += delta,
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('month-selector'),
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: () => move(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: SizedBox(
            height: 64 * MediaQuery.textScalerOf(context).scale(1),
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (notification) {
                if (notification.depth != 0) return false;
                final page = pages.page!.round();
                _targetPage = page;
                final month = dateFor(page);
                if (month.year != widget.month.year ||
                    month.month != widget.month.month) {
                  widget.onChanged(month);
                }
                return false;
              },
              child: PageView.builder(
                key: const ValueKey('month-pages'),
                controller: pages,
                itemBuilder: (context, index) => Center(
                  child: Text(
                    MaterialLocalizations.of(context)
                        .formatMonthYear(dateFor(index)),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: () => move(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
  );
}
