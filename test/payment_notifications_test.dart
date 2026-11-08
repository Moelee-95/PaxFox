import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/recurring_notifications.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/main.dart';
import 'package:moneva/screens/payment_notifications_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

import 'package:moneva/core/presentation/debt_editor.dart';
import 'package:moneva/screens/debt_settlement_form.dart';

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
        asOf: DateTime(2020),
        includeOnAsOf: true,
        kind: AccountKind.cash,
      ),
    ]);
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });

  Future<void> seed(int amount) async {
    final today = dateOnly(DateTime.now());
    final start = DateTime(today.year, today.month, today.day - 2);
    await store.saveRecurring(
      RecurringRule(
        description: 'Manual rent',
        amount: amount,
        category: store.categoriesFor(EntryType.expense).first.name,
        accountId: store.accounts.single.id!,
        day: start.day,
        nextDate: start,
        endDate: DateTime(today.year, today.month, today.day - 1),
        frequency: RecurrenceFrequency.day,
        automatic: false,
      ),
      today: start,
    );
    await store.processRecurring();
  }

  testWidgets(
    'queued reminder opens inbox and later taps focus it without stacking routes',
    (tester) async {
      await tester.runAsync(() => seed(100));
      final service = RecurringNotifications(store);
      RecurringNotifications.instance = service;
      addTearDown(() {
        RecurringNotifications.instance = null;
        service.dispose();
      });
      final target = store.recurringOccurrences.first.id;
      service.occurrenceToOpen.value = target;
      await tester.pumpWidget(MyApp(store: store));
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump();
        await tester.runAsync(() => store.processRecurring());
      }
      await tester.pumpAndSettle();
      expect(find.byType(PaymentNotificationsScreen), findsOneWidget);
      expect(find.text('Opened from reminder'), findsOneWidget);
      final card = tester.widget<Card>(
        find.byKey(ValueKey('payment-notification-$target')),
      );
      expect((card.shape as RoundedRectangleBorder).side.width, 2);
      expect(service.occurrenceToOpen.value, isNull);
      final other = store.recurringOccurrences
          .firstWhere((o) => o.id != target)
          .id;
      service.occurrenceToOpen.value = other;
      await tester.pumpAndSettle();
      expect(find.text('Opened from reminder'), findsOneWidget);
      expect(
        (tester
                    .widget<Card>(
                      find.byKey(ValueKey('payment-notification-$other')),
                    )
                    .shape
                as RoundedRectangleBorder)
            .side
            .width,
        2,
      );
      expect(store.entries, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentNotificationsScreen), findsNothing);
      expect(find.text('PaxFox'), findsOneWidget);
    },
  );

  testWidgets(
    'bell opens each overdue payment and successful confirmation removes only that occurrence',
    (tester) async {
      await tester.runAsync(() => seed(100));
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.centerTitle, isTrue);
      expect(
        tester.getCenter(find.byTooltip('Notifications')).dx,
        lessThan(tester.getCenter(find.text('PaxFox')).dx),
      );
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pump();
      await tester.runAsync(() => store.processRecurring());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => waitForStore(store, () => store.recurringOccurrences.length == 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manual rent'), findsNWidgets(2));
      await tester.tap(find.text('Confirm paid').first);
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.length == 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manual rent'), findsOneWidget);
      expect(store.entries.single.date, dateOnly(DateTime.now()));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pump();
      await tester.runAsync(() => store.processRecurring());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm paid'));
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.length == 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('No payments awaiting confirmation.'), findsOneWidget);
      expect(pendingPaymentNotifications(store), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'adding a pending notification to debts removes it without a payment',
    (tester) async {
      await tester.runAsync(() => seed(100));
      await tester.pumpWidget(
        MaterialApp(home: PaymentNotificationsScreen(store: store)),
      );
      await tester.runAsync(() => store.processRecurring());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to debts').first);
      await tester.runAsync(
        () => waitForStore(store, () => store.debts.isNotEmpty),
      );
      await tester.pumpAndSettle();
      expect(store.debts.single.amount, 100);
      expect(pendingPaymentNotifications(store).length, 1);
      expect(find.text('Manual rent'), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed confirmation remains in the inbox without charging money',
    (tester) async {
      await tester.runAsync(() => seed(1000000));
      await tester.pumpWidget(
        MaterialApp(home: PaymentNotificationsScreen(store: store)),
      );
      await tester.runAsync(() => store.processRecurring());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm paid').first);
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.recurringOccurrences.any((o) => o.error != null),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Manual rent'), findsNWidgets(2));
      expect(pendingPaymentNotifications(store).length, 2);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'due debt Keep opens editor without money movement and Pay opens settlement',
    (tester) async {
      await tester.runAsync(
        () => store.saveDebt(
          Debt(
            name: 'Deadline loan',
            amount: 2000,
            currency: Currency.eur,
            deadline: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: PaymentNotificationsScreen(store: store)),
      );
      await tester.runAsync(() => store.processRecurring());
      await tester.pumpAndSettle();
      expect(find.text('Deadline loan'), findsOneWidget);
      await tester.tap(find.text('Keep / edit'));
      await tester.runAsync(
        () => waitForStore(store, () => store.dueDebts().isEmpty),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DebtEditor), findsOneWidget);
      expect(store.entries, isEmpty);
      expect(store.debts.single.amount, 2000);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('debt-notification-${store.debts.single.id}')),
        findsNothing,
      );
      await tester.runAsync(
        () => store.saveDebt(
          Debt(
            id: store.debts.single.id,
            name: 'Deadline loan',
            amount: 2000,
            currency: Currency.eur,
            deadline: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay debt'));
      await tester.pumpAndSettle();
      expect(find.byType(DebtSettlementForm), findsOneWidget);
      await tester.tap(find.text('Confirm payment'));
      await tester.runAsync(
        () => waitForStore(store, () => store.debts.single.amount == 0),
      );
      await tester.pumpAndSettle();
      expect(store.entries.single.amount, 2000);
      expect(
        find.byKey(ValueKey('debt-notification-${store.debts.single.id}')),
        findsNothing,
      );
    },
  );
}
