import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/debt_balance_card.dart';
import 'package:moneva/core/presentation/debt_editor.dart';
import 'package:moneva/screens/debt_settlement_form.dart';
import 'package:moneva/screens/currency_exchange_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

import 'package:moneva/screens/overview_screen.dart';

void main() {
  late LedgerStore store;
  final previewKey = GlobalKey();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    final bytes = await File('assets/fonts/Roboto-Regular.ttf').readAsBytes();
    for (final family in ['PaxFoxRoboto', 'Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = await File(
      'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Euro bank',
        currency: Currency.eur,
        opening: 100000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    await store.saveExchangeRates({'eur_iqd': '1772', 'eur_usd': '1.1'});
    await store.saveDebt(
      Debt(
        name: 'Apartment rent',
        amount: Currency.iqd.parse('177200'),
        currency: Currency.iqd,
      ),
    );
    await store.saveDebt(
      const Debt(
        name: 'Rent owed to me',
        amount: 25000,
        currency: Currency.usd,
        isReceivable: true,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<void> preview(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final image =
          await (previewKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  void phone(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final dark in [false, true]) {
    testWidgets(
      'compact debt cards ${dark ? 'dark narrow large text' : 'light'} retain both currencies and matching actions',
      (tester) async {
        phone(tester, dark ? 320 : 430);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(dark ? 320 : 430, 900),
                textScaler: TextScaler.linear(dark ? 1.8 : 1),
              ),
              child: RepaintBoundary(
                key: previewKey,
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Debts', style: const TextStyle(fontSize: 22)),
                      for (final d in store.debts)
                        DebtBalanceCard(
                          debt: d,
                          mainCurrency: store.currency,
                          mainAmount: store.debtMainAmount(d),
                          onEdit: () {},
                          onSettle: () {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(Currency.eur.display(10000)), findsOneWidget);
        expect(
          find.text(Currency.iqd.display(Currency.iqd.parse('177200'))),
          findsOneWidget,
        );
        expect(find.text('Pay debt'), findsOneWidget);
        expect(find.text('Receive payment'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await preview(
          tester,
          'native_debt_cards_${dark ? 'dark_narrow' : 'light'}',
        );
      },
    );
  }
  testWidgets(
    'cross currency editor prefills rate, updates balance and saves fee separately',
    (tester) async {
      phone(tester, 430);
      final d = store.debts.firstWhere((d) => !d.isReceivable);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(
            key: previewKey,
            child: Scaffold(
              body: DebtSettlementForm(store: store, debt: d),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, '3,544');
      final fee = find.widgetWithText(TextFormField, 'Fee (EUR)');
      await tester.ensureVisible(fee);
      await tester.enterText(fee, '1');
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Balance after payment: ${Currency.eur.display(99700)}',
        ),
        findsOneWidget,
      );
      await preview(tester, 'native_debt_payment');
      await tester.tap(find.text('Confirm payment'));
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.length == 2),
      );
      await tester.pumpAndSettle();
      expect(
        store.debts.firstWhere((x) => x.id == d.id).amount,
        Currency.iqd.parse('173656'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same currency hides conversion and fee; editor Save remains readable',
    (tester) async {
      phone(tester, 320);
      await tester.runAsync(
        () => store.saveDebt(
          const Debt(name: 'Euro debt', amount: 10000, currency: Currency.eur),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebtSettlementForm(
              store: store,
              debt: store.debts.firstWhere((d) => d.currency == Currency.eur),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Fee ('), findsNothing);
      expect(find.textContaining(' = X '), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: DebtEditor(
                currency: Currency.eur,
                debt: store.debts.first,
                onSave: (_) async {},
                onDelete: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(FittedBox), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'exchange screen edits shared rate and revalues debts without ledger posting',
    (tester) async {
      phone(tester, 430);
      await tester.pumpWidget(
        MaterialApp(home: CurrencyExchangeScreen(store: store)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 EUR = 1772 IQD'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2000');
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.exchangeTable.rates['eur_iqd'] == '2000',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        store.debtMainAmount(store.debts.firstWhere((d) => !d.isReceivable)),
        8860,
      );
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing rate shortcut opens required IQD to EUR pair and focuses only rate input',
    (tester) async {
      phone(tester, 430);
      await tester.runAsync(() => store.saveExchangeRates({}));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(store: store, onOpenRecurring: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shortcut = find.text('Set EUR conversion').first;
      await tester.scrollUntilVisible(
        shortcut,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(find.text('Add exchange rate'), findsOneWidget);
      final selections = tester
          .widgetList<DropdownButtonFormField<Currency>>(
            find.byType(DropdownButtonFormField<Currency>),
          )
          .toList();
      expect(selections[0].initialValue, Currency.iqd);
      expect(selections[1].initialValue, Currency.eur);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
      await tester.enterText(find.byType(TextFormField), '0.0005');
      await tester.tap(find.text('Save'));
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.exchangeTable.rates['iqd_eur'] == '0.0005',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        store.debtMainAmount(
          store.debts.firstWhere((d) => d.currency == Currency.iqd),
        ),
        8860,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
