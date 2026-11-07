import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/entry_editor_sheet.dart';
import 'package:moneva/core/presentation/account_picker.dart';
import 'package:moneva/core/presentation/transaction_tile.dart';
import 'package:moneva/screens/accounts_screen.dart';
import 'package:moneva/screens/recurring_screen.dart';
import 'package:moneva/screens/transaction_form.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
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
        opening: 10000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    await store.addAccount(
      Account(
        name: 'IQD bank',
        currency: Currency.iqd,
        baseCurrency: Currency.eur,
        exchangeRate: '1772',
        opening: Currency.iqd.parse('177200'),
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Finder field, String choice) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'account currency and grouped rate show converted balance and save native units',
    (tester) async {
      final bank = store.accounts.firstWhere((a) => a.name == 'Euro bank');
      await mount(tester, AccountForm(store: store, account: bank));
      await tester.enterText(find.byType(TextFormField).at(1), '120');
      await choose(
        tester,
        find.byType(DropdownButtonFormField<Currency>),
        'IQD',
      );
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), '1,772');
      await tester.pump();
      expect(
        tester.widget<TextFormField>(fields.at(2)).controller!.text,
        '212,640.000',
      );
      expect(find.text('Equivalent: €120.00'), findsOneWidget);
      await tester.enterText(fields.at(2), '180,000');
      await tester.ensureVisible(find.text('Save account'));
      await tester.tap(find.text('Save account'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      final saved = store.accounts.firstWhere((a) => a.id == bank.id);
      expect(saved.currency, Currency.iqd);
      expect(saved.exchangeRate, '1772');
      expect(
        store.currentBalances.byAccount[bank.id],
        Currency.iqd.parse('180000'),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual foreign account defaults to euros and currency toggle converts entered amount',
    (tester) async {
      await mount(tester, TransactionForm(store: store));
      await tester.tap(find.text('IQD bank'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).currency,
        Currency.eur,
      );
      final amount = tester
          .widget<EntryEditorSheet>(find.byType(EntryEditorSheet))
          .amount;
      amount.text = '2';
      await tester.pump();
      expect(find.textContaining('IQD 3,544.000'), findsOneWidget);
      await choose(
        tester,
        find.byType(DropdownButtonFormField<Currency>),
        'IQD',
      );
      expect(
        tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).currency,
        Currency.iqd,
      );
      expect(amount.text, '3,544.000');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recurring foreign account defaults to native currency', (
    tester,
  ) async {
    await mount(tester, RecurringForm(store: store));
    await choose(
      tester,
      find.byType(DropdownButtonFormField<int>).first,
      'IQD bank',
    );
    expect(
      tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).currency,
      Currency.iqd,
    );
    final amount = tester
        .widget<EntryEditorSheet>(find.byType(EntryEditorSheet))
        .amount;
    amount.text = '1772';
    await tester.pump();
    expect(find.text('Current equivalent: €1.00'), findsOneWidget);
    await choose(tester, find.byType(DropdownButtonFormField<Currency>), 'EUR');
    expect(amount.text, '1.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'transfer history shows actual supplied bank amounts and rate at narrow large text',
    (tester) async {
      final source = store.accounts.firstWhere((a) => a.name == 'IQD bank');
      final target = store.accounts.firstWhere((a) => a.name == 'Euro bank');
      final entry = store.entryFromInput(
        type: EntryType.transfer,
        inputAmount: Currency.iqd.parse('17720'),
        inputCurrency: Currency.iqd,
        date: DateTime(2026),
        description: 'Transfer',
        category: 'Transfer',
        accountId: source.id,
        destinationId: target.id,
        receivedAmount: 950,
      );
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: TransactionTile(
                entry: entry,
                onTap: null,
                onLongPress: null,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('IQD 17,720.000 → €9.50'), findsOneWidget);
      expect(find.textContaining('1 IQD = 0.000536117 EUR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native manual amount saves euros and description edits keep the saved rate',
    (tester) async {
      final bank = store.accounts.firstWhere((a) => a.name == 'IQD bank');
      await tester.runAsync(
        () => store.saveEntry(
          store.entryFromInput(
            type: EntryType.expense,
            inputAmount: 200,
            inputCurrency: Currency.eur,
            date: DateTime(2026),
            description: 'Original',
            category: store.categoriesFor(EntryType.expense).first.name,
            accountId: bank.id,
          ),
        ),
      );
      await mount(
        tester,
        TransactionForm(store: store, entry: store.entries.single),
      );
      await choose(
        tester,
        find.byType(DropdownButtonFormField<Currency>),
        'IQD',
      );
      tester
              .widget<EntryEditorSheet>(find.byType(EntryEditorSheet))
              .amount
              .text =
          '1772';
      await tester.ensureVisible(find.text('Save transaction'));
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.amount, 100);
      expect(store.entries.single.accountAmount, 1772000);
      await tester.runAsync(
        () => store.updateAccount(
          Account(
            id: bank.id,
            name: bank.name,
            currency: bank.currency,
            baseCurrency: Currency.eur,
            exchangeRate: '1800',
            opening: bank.opening,
            asOf: bank.asOf,
            includeOnAsOf: true,
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await mount(
        tester,
        TransactionForm(store: store, entry: store.entries.single),
      );
      final description = find.widgetWithText(
        TextFormField,
        'Description / merchant',
      );
      await tester.enterText(description, 'Renamed');
      await tester.ensureVisible(find.text('Save transaction'));
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.description, 'Renamed');
      expect(store.entries.single.amount, 100);
      expect(store.entries.single.accountAmount, 1772000);
      expect(store.entries.single.fx!.sourceRate, '1772');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer editor saves independent deducted and received amounts',
    (tester) async {
      await mount(
        tester,
        TransactionForm(store: store, initialType: EntryType.transfer),
      );
      final pickers = find.byType(AccountPicker);
      await tester.tap(
        find.descendant(of: pickers.first, matching: find.text('IQD bank')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: pickers.last, matching: find.text('Euro bank')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).currency,
        Currency.iqd,
      );
      tester
              .widget<EntryEditorSheet>(find.byType(EntryEditorSheet))
              .amount
              .text =
          '17720';
      final description = find.widgetWithText(
        TextFormField,
        'Description / merchant',
      );
      await tester.enterText(description, 'Actual transfer');
      final received = find.widgetWithText(
        TextFormField,
        'Amount received (EUR)',
      );
      await tester.ensureVisible(received);
      await tester.enterText(received, '9.50');
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.accountAmount, 17720000);
      expect(store.entries.single.destinationAmount, 950);
      expect(store.entries.single.fx!.transferRate, '1 IQD = 0.000536117 EUR');
      expect(tester.takeException(), isNull);
    },
  );
}
