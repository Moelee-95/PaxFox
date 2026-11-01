import 'helpers/sheet_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/transaction_csv.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/number_format.dart';
import 'package:moneva/core/presentation/grouped_amount_formatter.dart';
import 'package:moneva/screens/transaction_form.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const formatter = GroupedAmountFormatter();
  TextEditingValue edit(String text, [int? caret]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  test('display groups exact money, signs and whole-unit totals without affecting serialization', () {
    expect(Currency.eur.display(123456789), '€1,234,567.89');
    expect(Currency.usd.display(-123456), r'$-1,234.56');
    expect(Currency.gbp.display(100000), '£1,000.00');
    expect(Currency.iqd.display(123456789), 'IQD 123,456.789');
    expect(Currency.eur.display(9000000000000000), '€90,000,000,000,000.00');
    expect(Currency.eur.format(123456), '1234.56');
    expect(Currency.iqd.parse('12,345'), 12345);
    expect(formatInteger(1234567), '1,234,567');
    expect(formatInteger(-1234), '-1,234');
    expect(formatInteger(0), '0');
  });

  test('UI parsing accepts grouping while validating precision and malformed input', () {
    expect(Currency.eur.parseInput('1,000'), 100000);
    expect(Currency.eur.parseInput('1,234,567.89'), 123456789);
    expect(Currency.iqd.parseInput('1,234.567'), 1234567);
    expect(Currency.eur.parseInput('12,50'), 1250);
    expect(Currency.eur.parseInput(' 1,234.50 '), 123450);
    for (final invalid in [
      '1,23,456',
      '1,000.001',
      '1,000.99oops',
      '-1,000',
      '900,000,000,000,000.01',
    ]) {
      expect(() => Currency.eur.parseInput(invalid), throwsFormatException);
    }
  });

  test('live editing preserves decimal precision, partial input and caret', () {
    expect(formatter.formatEditUpdate(edit('999'), edit('9999')).text, '9,999');
    var result = formatter.formatEditUpdate(edit('123'), edit('1234'));
    expect(result.text, '1,234');
    expect(result.selection.baseOffset, 5);
    result = formatter.formatEditUpdate(edit('1,234'), edit('1,2345'));
    expect(result.text, '12,345');
    expect(result.selection.baseOffset, 6);
    result = formatter.formatEditUpdate(edit('1,234', 3), edit('1,2934', 4));
    expect(result.text, '12,934');
    expect(result.selection.baseOffset, 4);
    expect(
      formatter.formatEditUpdate(edit(''), edit('-1234.560')).text,
      '-1,234.560',
    );
    expect(formatter.formatEditUpdate(edit(''), edit('1234.')).text, '1,234.');
    expect(formatter.formatEditUpdate(edit(''), edit('12,50')).text, '12.50');
    expect(
      formatter.formatEditUpdate(edit('1,234'), edit('1,234,')).text,
      '1,234.',
    );
    expect(
      formatter.formatEditUpdate(edit(''), edit('1,234.567')).text,
      '1,234.567',
    );
    expect(formatter.formatEditUpdate(edit(''), edit('-')).text, '-');
    expect(formatter.formatEditUpdate(edit('1,234'), edit('')).text, '');
    result = formatter.formatEditUpdate(edit('1,234', 1), edit('1234', 1));
    expect(result.text, '1,234');
    expect(
      result.selection.baseOffset,
      2,
    ); // Forward Delete skips the separator.
    result = formatter.formatEditUpdate(edit('1,234', 2), edit('1234', 1));
    expect(result.selection.baseOffset, 1); // Backspace skips it in reverse.
    expect(
      formatter.formatEditUpdate(edit('1,234'), edit('1,234x')).text,
      '1,234x',
    );
    final selected = TextEditingValue(
      text: '1,234',
      selection: const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(formatter.formatEditUpdate(selected, edit('12,50')).text, '12.50');
    final composing = edit('1234')
        .copyWith(composing: const TextRange(start: 0, end: 4));
    expect(formatter.formatEditUpdate(edit('123'), composing), composing);
  });

  testWidgets(
    'grouped transaction input saves exact minor units and reopens grouped',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LedgerStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      addTearDown(() async {
        await store.db.close();
        store.dispose();
      });
      await tester.runAsync(
        () => store.completeSetup([
          Account(
            name: 'Cash',
            currency: Currency.eur,
            opening: 1000000,
            asOf: dateOnly(DateTime.now()),
            kind: AccountKind.cash,
            includeOnAsOf: true,
          ),
        ]),
      );
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: TransactionForm(store: store)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Grouped purchase',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '1234.56',
      );
      expect(find.text('1,234.56'), findsOneWidget);
      await openCategoryPicker(tester);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Groceries');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save transaction'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(store.entries.single.amount, 123456);
      expect(store.currentBalances.wealth, 876544);
      expect(TransactionCsv.encode(store.entries), contains('1234.56'));
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('edit-app'),
          home: TransactionForm(
            key: const ValueKey('edit'),
            store: store,
            entry: store.entries.single,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1,234.56'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
