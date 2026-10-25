import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/screens/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  test(
    'timeout defaults, validates limits and reloads persisted values',
    () async {
      expect(store.invoiceTimeoutSeconds, 180);
      for (final invalid in [0, 29, 901]) {
        await expectLater(
          store.saveInvoiceTimeout(invalid),
          throwsArgumentError,
        );
      }
      await store.saveInvoiceTimeout(600);
      store.invoiceTimeoutSeconds = 180;
      await store.refresh();
      expect(store.invoiceTimeoutSeconds, 600);
      expect(
        (await store.db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['invoice_timeout_seconds'],
        )).single['value'],
        '600',
      );
    },
  );
  testWidgets('settings validate and save custom extraction timeout', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    await tester.enterText(find.byType(TextFormField), '10');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 30 to 900.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '420');
    await tester.tap(find.text('Save settings'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.invoiceTimeoutSeconds, 420);
    expect(tester.takeException(), isNull);
  });
}
