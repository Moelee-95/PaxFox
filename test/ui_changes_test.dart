import 'helpers/sheet_helpers.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'helpers/wait_for_store.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/account_picker.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/screens/csv_screen.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/invoice_review_screen.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> preview(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'two-column add menu keeps six actions accessible on small phones',
    (tester) async {
      phone(tester);
      await tester.runAsync(
        () => store.completeSetup([
          Account(
            name: 'Cash',
            currency: Currency.eur,
            opening: 10000,
            asOf: DateTime(2026),
            kind: AccountKind.cash,
          ),
        ]),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: MyApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      await preview(tester, 'add-expense-income-light');
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('create-expense-manual')))
            .dx,
        lessThan(
          tester
              .getCenter(find.byKey(const ValueKey('create-income-manual')))
              .dx,
        ),
      );
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      await preview(tester, 'add-expense-income-dark');
      tester.view.physicalSize = const Size(320, 740);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pumpAndSettle();
      await preview(tester, 'add-expense-income-large-text');
      for (final type in ['expense', 'income']) {
        for (final action in ['manual', 'scan', 'upload']) {
          final button = find.byKey(ValueKey('create-$type-$action'));
          await tester.ensureVisible(button);
          expect(button.hitTestable(), findsOneWidget);
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('CSV multi-select layout in light, dark and large text', (
    tester,
  ) async {
    phone(tester);
    await tester.runAsync(
      () => store.completeSetup([
        Account(
          name: 'Cash',
          currency: Currency.eur,
          opening: 1000,
          asOf: DateTime(2026),
          kind: AccountKind.cash,
        ),
        Account(
          name: 'Household bank account',
          currency: Currency.eur,
          opening: 10000,
          asOf: DateTime(2026),
        ),
      ]),
    );
    Widget app(Brightness brightness, {double scale = 1}) => RepaintBoundary(
      key: previewKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: CsvScreen(store: store),
      ),
    );
    await tester.pumpWidget(app(Brightness.light));
    await preview(tester, 'csv-multi-light');
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    await tester.pumpWidget(app(Brightness.dark));
    await preview(tester, 'csv-multi-dark');
    tester.view.physicalSize = const Size(320, 740);
    await tester.pumpWidget(app(Brightness.light, scale: 1.8));
    await preview(tester, 'csv-multi-large-text');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'first-run currency and debt appear in accounts and wealth, with outlined inputs',
    (tester) async {
      phone(tester);
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: MyApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<Currency>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IQD (IQD)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Cash balance (IQD)'),
        '100.123',
      );
      await preview(tester, 'setup-currency');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I do not have a bank account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add debt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lender / debt name'),
        'Family loan',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Outstanding amount (IQD)'),
        '20.001',
      );
      await preview(tester, 'setup-debt');
      await tester.tap(find.text('Save debt'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Finish setup'));
      await tester.tap(find.text('Finish setup'));
      await tester.runAsync(() async {
        await waitForStore(store, () => store.setupCompleted);
      });
      await tester.pumpAndSettle();
      expect(store.currency, Currency.iqd);
      expect(store.netWealth, 80122);
      expect(store.currentBalances.available, 100123);
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Account wealth'), findsOneWidget);
      await preview(tester, 'overview-debt');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('Account wealth'))).brightness,
        Brightness.dark,
      );
      await preview(tester, 'overview-dark');
      tester.binding.platformDispatcher.clearPlatformBrightnessTestValue();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Monthly overview'));
      await tester.pumpAndSettle();
      await preview(tester, 'home-monthly-overview');
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await tester.pumpAndSettle();
      await preview(tester, 'more-profile');
      await tester.ensureVisible(find.widgetWithText(ListTile, 'Accounts'));
      await tester.tap(find.widgetWithText(ListTile, 'Accounts'));
      await tester.pumpAndSettle();
      expect(find.text('Family loan'), findsOneWidget);
      await preview(tester, 'accounts-management');
      await closeTopPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Upload file'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('create-expense-manual')));
      await tester.pumpAndSettle();
      final fieldContext = tester.element(find.byType(TextFormField).first);
      expect(
        Theme.of(fieldContext).inputDecorationTheme.border,
        isA<OutlineInputBorder>(),
      );
      expect(find.byType(DropdownButtonFormField<EntryType>), findsNothing);
      await preview(tester, 'manual-inputs');
      await closeTopPage(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('More'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(ListTile, 'Recurring payments'),
      );
      await tester.tap(find.widgetWithText(ListTile, 'Recurring payments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add recurring payment'));
      await tester.pumpAndSettle();
      await chooseEntryType(tester, 'income');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (e.g. Rent)'),
        'Monthly salary',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount (IQD)'),
        '2400',
      );
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Salary');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await preview(tester, 'recurring-compact-form');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'review shows separate invoice dates and editing a date saves only that item date',
    (tester) async {
      phone(tester);
      await tester.runAsync(
        () => store.addAccount(
          Account(
            name: 'Cash',
            currency: Currency.eur,
            opening: 5000,
            asOf: DateTime(2026),
            includeOnAsOf: true,
            kind: AccountKind.cash,
          ),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: MaterialApp(
            home: InvoiceReviewScreen(
              store: store,
              draft: InvoiceDraft(
                merchant: 'Two shops',
                currency: 'EUR',
                multipleInvoices: true,
                total: 300,
                category: 'Groceries',
                items: [
                  InvoiceItem(
                    description: 'First invoice item',
                    quantity: '1',
                    total: 100,
                    category: 'Groceries',
                    date: DateTime(2026, 1, 2),
                  ),
                  InvoiceItem(
                    description: 'Second invoice item',
                    quantity: '1',
                    total: 200,
                    category: 'Groceries',
                    date: DateTime(2026, 2, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-01-02'), findsOneWidget);
      expect(find.textContaining('2026-02-02'), findsOneWidget);
      expect(find.textContaining('Invoice date:'), findsNothing);
      await preview(tester, 'invoice-dates');
      await tester.tap(find.text('First invoice item'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2026-01-02'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3').last);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply item'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AccountPicker),
          matching: find.text('Cash'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transactions'));
      await tester.runAsync(() async {
        await waitForStore(store, () => store.entries.length == 2);
      });
      await tester.pumpAndSettle();
      expect(
        store.entries
            .singleWhere((entry) => entry.description == 'First invoice item')
            .date,
        DateTime(2026, 1, 3),
      );
      expect(
        store.entries
            .singleWhere((entry) => entry.description == 'Second invoice item')
            .date,
        DateTime(2026, 2, 2),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
