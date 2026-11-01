import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/presentation/month_selector.dart';

void main() {
  testWidgets('rapid month taps commit only the settled destination', (
    tester,
  ) async {
    var month = DateTime(2026, 12);
    final changes = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => MonthSelector(
              month: month,
              onChanged: (value) => update(() {
                month = value;
                changes.add(value);
              }),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Next month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 35));
    expect(
      changes,
      isEmpty,
      reason: 'Do not rebuild the ledger during a slide.',
    );
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(changes, [DateTime(2027, 2)]);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(month, DateTime(2027, 2));
    expect(changes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'month swipe publishes once after settling and follows external changes',
    (tester) async {
      var month = DateTime(2026, 10);
      late StateSetter update;
      final changes = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return MonthSelector(
                  month: month,
                  onChanged: (value) => setState(() {
                    changes.add(value);
                    month = value;
                  }),
                );
              },
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('month-pages'))),
      );
      await gesture.moveBy(const Offset(-450, 0));
      await tester.pump();
      expect(changes, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, [DateTime(2026, 11)]);
      update(() => month = DateTime(2025, 1));
      await tester.pumpAndSettle();
      expect(changes, hasLength(1));
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(month, DateTime(2024, 12));
      expect(tester.takeException(), isNull);
    },
  );
}
