import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/main.dart';
import 'package:moneva/screens/more_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('warm navigation reuses page content with a large ledger', (
    tester,
  ) async {
    sqfliteFfiInit();
    final store = await tester.runAsync(() async {
      final store = await LedgerStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      final now = dateOnly(DateTime.now());
      await store.completeSetup([
        Account(
          name: 'Synthetic cash',
          kind: AccountKind.cash,
          currency: Currency.eur,
          opening: 100000000,
          asOf: DateTime(now.year - 1),
          includeOnAsOf: true,
          allowOverdraft: false,
        ),
      ]);
      await store.db.transaction((txn) async {
        final batch = txn.batch();
        for (var i = 0; i < 5000; i++) {
          batch.insert('transactions', {
            ...LedgerEntry(
              type: i.isEven ? EntryType.expense : EntryType.income,
              amount: 100 + i,
              currency: Currency.eur,
              date: now,
              description: 'Synthetic transaction $i',
              category: i.isEven ? 'Groceries' : 'Salary',
              accountId: store.accounts.single.id,
            ).toMap(),
            'created_at': now.toUtc().toIso8601String(),
            'updated_at': now.toUtc().toIso8601String(),
          });
        }
        await batch.commit(noResult: true);
      });
      await store.refresh();
      return store;
    });
    addTearDown(() async {
      store!.dispose();
      await store.db.close();
    });
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    Future<void> select(String label) async {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final label in ['Overview', 'Cashflow', 'More', 'Home']) {
      await select(label);
    }
    final counts = <String, int>{};
    final prior = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      final type = element.widget.runtimeType.toString();
      if (const {
        'HomeScreen',
        'OverviewScreen',
        'MoreScreen',
        'MonthSelector',
        'TransactionTile',
      }.contains(type)) {
        counts.update(type, (count) => count + 1, ifAbsent: () => 1);
      }
      prior?.call(element, builtOnce);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = prior);
    for (var i = 0; i < 3; i++) {
      for (final label in ['Overview', 'More', 'Home']) {
        await select(label);
      }
    }
    if (const bool.fromEnvironment('BENCHMARK_NAVIGATION')) {
      // Debug widget work counts, not real-device frame timings.
      debugPrint('Warm navigation / 9 switches / 5000 entries: $counts');
    }
    expect(store!.entries.length, 5000);
    final summary = store.monthSummary(DateTime.now());
    final totals = Totals();
    for (final entry in store.entries) {
      totals.add(entry);
    }
    expect(summary.eurTotals.net, totals.net);
    expect(
      store.currentBalances.wealth,
      accountBalance(
        store.accounts.single,
        store.entries,
        dateOnly(DateTime.now()),
      ),
    );
    expect(
      counts,
      isEmpty,
      reason: 'Changing main tabs must not rebuild retained page content.',
    );

    // Retaining a page must preserve its view state without freezing its data.
    debugOnRebuildDirtyWidget = prior;
    await select('More');
    await tester.enterText(find.byType(TextField), 'privacy');
    await tester.pumpAndSettle();
    await select('Home');
    await tester.runAsync(
      () => store.saveProfile(name: 'Updated while hidden', email: ''),
    );
    await select('More');
    expect(find.text('Updated while hidden'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Privacy Policy'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'privacy',
    );
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.widgetWithText(ListTile, 'Settings'),
      250,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    final scrollOffset = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    expect(scrollOffset, greaterThan(0));
    await select('Home');
    await select('Overview');
    await select('More');
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      scrollOffset,
    );
    expect(tester.takeException(), isNull);
  });
}
