import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/account_picker.dart';

void main() {
  final accounts = List.generate(
    4,
    (index) => Account(
      id: index + 1,
      name: ['Wallet', 'Everyday', 'Savings', 'Reserve'][index],
      currency: Currency.eur,
      opening: 0,
      asOf: DateTime(2026),
      kind: index == 0 ? AccountKind.cash : AccountKind.bank,
    ),
  );

  testWidgets(
    'selecting the last account moves it to the start with its numeric balance',
    (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) => AccountPicker(
                    accounts: accounts,
                    balances: const {1: 12345, 2: 20000, 3: 30000, 4: -506},
                    selectedId: selected,
                    onChanged: (id) => setState(() => selected = id),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('123.45'), findsOneWidget);
      expect(find.text('Cash'), findsNothing);
      expect(find.text('Bank'), findsNothing);
      expect(find.textContaining('Available balance'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(-700, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reserve'));
      await tester.pumpAndSettle();

      expect(selected, 4);
      final card = find.byKey(const ValueKey('account-card-4'));
      expect(
        tester.getTopLeft(card).dx,
        tester.getTopLeft(find.byType(ListView)).dx,
      );
      expect(tester.getSize(card).height, lessThanOrEqualTo(56));
      expect(
        find.descendant(of: card, matching: find.text('-5.06')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.check_circle)),
        findsOneWidget,
      );
      expect(accounts.map((account) => account.id), [1, 2, 3, 4]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact cards fit larger text and do not invent an unassigned balance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: AccountPicker(
                accounts: accounts,
                balances: const {1: 12345},
                selectedId: null,
                allowUnassigned: true,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final unassigned = find.byKey(const ValueKey('account-card-unassigned'));
      expect(
        find.descendant(of: unassigned, matching: find.text('0.00')),
        findsNothing,
      );
      expect(find.text('Unassigned'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
