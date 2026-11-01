import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/account_picker.dart';
import 'package:moneva/core/presentation/debt_editor.dart';
import 'package:moneva/main.dart';
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
    'Back requires a second press within two seconds on every main destination',
    (tester) async {
      var exits = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      for (final destination in ['Home', 'Overview', 'Cashflow', 'More']) {
        await tester.tap(find.text(destination));
        await tester.pumpAndSettle();
        final before = exits;
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(exits, before);
        expect(find.text('Tap back again to exit'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(exits, before);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(exits, before + 1);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transaction fields have spacing and payment account cards align with their input edge',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-expense-manual')));
      await tester.pumpAndSettle();
      final description = find.widgetWithText(
        TextFormField,
        'Description / merchant',
      );
      final amount = find.widgetWithText(TextFormField, 'Amount');
      expect(
        tester.getTopLeft(amount).dy - tester.getBottomLeft(description).dy,
        greaterThanOrEqualTo(16),
      );
      final account = find.byKey(
        ValueKey('account-card-${store.accounts.single.id}'),
      );
      await tester.ensureVisible(find.byType(AccountPicker));
      expect(tester.getTopLeft(account).dx, tester.getTopLeft(description).dx);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings and debt guidance is hidden until its info button is tapped',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Long invoices may need more time.'),
        findsNothing,
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Long invoices may need more time.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebtEditor(currency: Currency.eur, onSave: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter what you still owe'), findsNothing);
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.textContaining('Enter what you still owe'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
