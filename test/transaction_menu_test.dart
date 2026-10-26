import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/features/receipts/invoice_scan_screen.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: ':memory:',
      factory: databaseFactoryFfi,
    );
    await store.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 10000,
        asOf: dateOnly(DateTime.now()),
        includeOnAsOf: true,
        kind: AccountKind.cash,
      ),
    ]);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  testWidgets(
    'floating choices dismiss with X, outside taps or Back and block navigation',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Scan invoice'), findsNothing);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      final anchor = tester.getRect(find.byTooltip('Add transaction'));
      final navigationPoint = tester.getCenter(find.text('Transactions'));
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Add manually'), findsOneWidget);
      expect(find.text('Scan invoice'), findsOneWidget);
      expect(
        tester.getRect(find.byTooltip('Cancel adding transaction')),
        anchor,
      );
      await tester.tap(find.byTooltip('Cancel adding transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Add manually'), findsNothing);
      expect(find.text('Monthly overview'), findsOneWidget);

      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tapAt(navigationPoint);
      await tester.pumpAndSettle();
      expect(find.text('Add manually'), findsNothing);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );

      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Add manually'), findsNothing);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual and scan choices open their respective routes with no header scan shortcut',
    (tester) async {
      const channel = MethodChannel('cunning_document_scanner');
      var scans = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        scans++;
        return <String>[];
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add manually'));
      await tester.pumpAndSettle();
      expect(find.text('Save transaction'), findsOneWidget);
      expect(find.byTooltip('Scan invoice'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan invoice'));
      await tester.pumpAndSettle();
      expect(find.byType(InvoiceScanScreen), findsOneWidget);
      expect(scans, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
