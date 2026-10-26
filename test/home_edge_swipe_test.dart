import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 10000,
        asOf: dateOnly(DateTime.now()),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  testWidgets(
    'left drag from info moves the main pager with the finger and settles on Overview',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Monthly overview'));
      await tester.pumpAndSettle();
      final pages = find.byKey(const ValueKey('main-pages'));
      final controller = tester.widget<PageView>(pages).controller!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TabBarView)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();
      expect(controller.page, greaterThan(0));
      expect(controller.page, lessThan(1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.text('Account balances today'), findsOneWidget);
      // Returning Home retains the info tab; right swipes still go to Income.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Net cashflow:'), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(650, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
      expect(controller.page, 0);
      await tester.drag(find.byType(TabBarView), const Offset(-650, 0));
      await tester.pumpAndSettle();
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(controller.page, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'reversing the edge drag restores Home without changing its info tab',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Monthly overview'));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<PageView>(find.byKey(const ValueKey('main-pages')))
          .controller!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TabBarView)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-150, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(controller.page, 0);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
