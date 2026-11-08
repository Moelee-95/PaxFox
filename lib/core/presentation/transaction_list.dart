import 'package:flutter/material.dart';

import '../domain/ledger.dart';

typedef InvoiceGroupInfo = ({int id, String label});

/// Groups only the currently visible results; the first matching item anchors
/// each invoice. Individual rows stay lazy even for very large scanned batches.
class SliverTransactionList extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(emptyMessage),
        ),
      );
    }
    final buckets = <Object, List<LedgerEntry>>{};
    for (final entry in entries) {
      final group = invoiceGroups[entry.id];
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
          })
        >[];
    for (final bucket in buckets.values) {
      for (var i = 0; i < bucket.length; i++) {
        rows.add((
          entry: bucket[i],
          group: invoiceGroups[bucket[i].id],
          first: i == 0,
          last: i == bucket.length - 1,
          count: bucket.length,
        ));
      }
    }
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final tile = tileBuilder(row.entry);
        if (row.group == null) return tile;
        final colors = Theme.of(context).colorScheme;
        final outline = colors.primary.withValues(alpha: .3);
        return Padding(
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 8, 7, 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 17,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              row.group!.label,
                              style: Theme.of(context).textTheme.labelMedium
                                  ?.copyWith(
                                    color: colors.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${row.count} ${row.count == 1 ? 'item' : 'items'}',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  tile,
                ],
              ),
            ),
          ),
        );
      },
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
