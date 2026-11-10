import 'package:flutter/material.dart';

import '../domain/ledger.dart';

typedef InvoiceGroupInfo = ({int id, String label});

/// Groups only the currently visible results; the first matching item anchors
/// each invoice. Individual rows stay lazy even for very large scanned batches.
class SliverTransactionList extends StatefulWidget {
  const SliverTransactionList({
    super.key,
    required this.entries,
    required this.tileBuilder,
    required this.emptyMessage,
    this.invoiceGroups = const {},
  });
  final List<LedgerEntry> entries;
  final Widget Function(LedgerEntry) tileBuilder;
  final String emptyMessage;
  final Map<int, InvoiceGroupInfo> invoiceGroups;

  @override
  State<SliverTransactionList> createState() => _SliverTransactionListState();
}

class _SliverTransactionListState extends State<SliverTransactionList> {
  // Keep choices when snapshots refresh or an invoice temporarily leaves a filter.
  final _collapsed = <int>{};
  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(widget.emptyMessage),
        ),
      );
    }
    final buckets = <Object, List<LedgerEntry>>{};
    for (final entry in widget.entries) {
      final group = widget.invoiceGroups[entry.id];
      final Object key = group == null ? entry : ('invoice', group.id);
      (buckets[key] ??= []).add(entry);
    }
    final rows =
        <
          ({
            LedgerEntry entry,
            InvoiceGroupInfo? group,
            bool first,
            bool last,
            int count,
            String total,
          })
        >[];
    for (final bucket in buckets.values) {
      final group = widget.invoiceGroups[bucket.first.id];
      final collapsed = group != null && _collapsed.contains(group.id);
      final totals = <Currency, int>{};
      if (group != null) {
        for (final entry in bucket) {
          final amount = entry.type == EntryType.refund
              ? -entry.amount
              : entry.amount;
          totals.update(
            entry.currency,
            (value) => value + amount,
            ifAbsent: () => amount,
          );
        }
      }
      final total = totals.entries
          .map((entry) => entry.key.display(entry.value))
          .join(' / ');
      for (var i = 0; i < (collapsed ? 1 : bucket.length); i++) {
        rows.add((
          entry: bucket[i],
          group: widget.invoiceGroups[bucket[i].id],
          first: i == 0,
          last: collapsed || i == bucket.length - 1,
          count: bucket.length,
          total: total,
        ));
      }
    }
    final keys = [
      for (final row in rows)
        ValueKey<Object>(
          row.group != null && row.first
              ? ('invoice', row.group!.id)
              : ('entry', row.entry.id ?? row.entry),
        ),
    ];
    final indices = {for (var i = 0; i < keys.length; i++) keys[i]: i};
    return SliverList.builder(
      itemCount: rows.length,
      findChildIndexCallback: (key) => indices[key],
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.group == null) {
          return KeyedSubtree(
            key: keys[index],
            child: widget.tileBuilder(row.entry),
          );
        }
        final collapsed = _collapsed.contains(row.group!.id);
        final colors = Theme.of(context).colorScheme;
        final outline = colors.primary.withValues(alpha: .3);
        return KeyedSubtree(
          key: keys[index],
          child: Padding(
            padding: EdgeInsets.only(
              top: row.first ? 8 : 0,
              bottom: row.last ? 8 : 0,
            ),
            child: CustomPaint(
              foregroundPainter: _InvoiceOutline(
                color: outline,
                first: row.first,
                last: row.last,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  5,
                  row.first ? 4 : 0,
                  5,
                  row.last ? 5 : 0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (row.first)
                      _InvoiceHeader(
                        group: row.group!,
                        count: row.count,
                        total: row.total,
                        collapsed: collapsed,
                        onToggle: () => setState(() {
                          if (!_collapsed.add(row.group!.id)) {
                            _collapsed.remove(row.group!.id);
                          }
                        }),
                      ),
                    if (!collapsed) widget.tileBuilder(row.entry),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InvoiceHeader extends StatelessWidget {
  const _InvoiceHeader({
    required this.group,
    required this.count,
    required this.total,
    required this.collapsed,
    required this.onToggle,
  });
  final InvoiceGroupInfo group;
  final int count;
  final String total;
  final bool collapsed;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = Text(
      group.label,
      style: theme.textTheme.labelMedium?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
    final countLabel = Text(
      '$count ${count == 1 ? 'item' : 'items'}',
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );
    final totalLabel = Text(
      'Total $total',
      style: theme.textTheme.labelMedium?.copyWith(
        color: colors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
    final chevron = AnimatedRotation(
      turns: collapsed ? -.25 : 0,
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 150,
      ),
      child: Icon(Icons.expand_more_rounded, size: 20, color: colors.primary),
    );
    return Semantics(
      button: true,
      expanded: !collapsed,
      child: InkWell(
        key: ValueKey('invoice-header-${group.id}'),
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(7, 8, 7, 10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(14) > 18;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 17,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: title),
                      if (!compact) ...[
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .45,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [countLabel, totalLabel],
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      chevron,
                    ],
                  ),
                  if (compact)
                    Padding(
                      padding: const EdgeInsets.only(left: 24, top: 4),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [countLabel, totalLabel],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InvoiceOutline extends CustomPainter {
  const _InvoiceOutline({
    required this.color,
    required this.first,
    required this.last,
  });
  final Color color;
  final bool first, last;

  @override
  void paint(Canvas canvas, Size size) {
    const r = 16.0;
    const left = .5;
    final right = size.width - .5;
    final bottom = size.height - (last ? .5 : 0);
    final path = Path();
    if (first) {
      path.moveTo(left, r);
      path.quadraticBezierTo(left, .5, r, .5);
      path.lineTo(right - r, .5);
      path.quadraticBezierTo(right, .5, right, r);
    } else {
      path.moveTo(right, 0);
    }
    path.lineTo(right, bottom - (last ? r : 0));
    if (last) {
      path.quadraticBezierTo(right, bottom, right - r, bottom);
      path.lineTo(r, bottom);
      path.quadraticBezierTo(left, bottom, left, bottom - r);
    } else {
      path.moveTo(left, bottom);
    }
    path.lineTo(left, first ? r : 0);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_InvoiceOutline oldDelegate) =>
      color != oldDelegate.color ||
      first != oldDelegate.first ||
      last != oldDelegate.last;
}
