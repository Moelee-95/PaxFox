import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/data/recurring_notifications.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const timeChannel = MethodChannel('flutter_timezone');
  late LedgerStore store;
  late RecurringNotifications reminders;
  final calls = <MethodCall>[];
  late List<MethodCall> startupCalls;
  var zone = 'Europe/Berlin';
  var exact = true;
  Map<String, Object?>? launchResponse;
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sqfliteFfiInit();
    calls.clear();
    exact = true;
    launchResponse = null;
    zone = 'Europe/Berlin';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': launchResponse != null,
              'notificationResponse': ?launchResponse,
            },
            'pendingNotificationRequests' ||
            'getActiveNotifications' => <Map<String, Object?>>[],
            'canScheduleExactNotifications' => exact,
            'requestNotificationsPermission' ||
            'requestExactAlarmsPermission' => true,
            _ => null,
          };
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timeChannel, (_) async => zone);
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.addAccount(
      Account(
        name: 'Bank',
        currency: Currency.eur,
        opening: 100000,
        asOf: DateTime(2020),
        includeOnAsOf: true,
      ),
    );
    reminders = RecurringNotifications(store, testPlatform: true);
    await reminders.initialize();
    await reminders.settled;
    startupCalls = List.of(calls);
    calls.clear();
  });
  tearDown(() async {
    reminders.dispose();
    await reminders.settled;
    await store.db.close();
    store.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timeChannel, null);
  });

  test('startup requests notifications before any recurring rule exists', () {
    expect(store.recurringRules, isEmpty);
    expect(
      startupCalls.where(
        (call) => call.method == 'requestNotificationsPermission',
      ),
      hasLength(1),
    );
    expect(
      startupCalls.where(
        (call) => call.method == 'requestExactAlarmsPermission',
      ),
      isEmpty,
    );
    expect(store.entries, isEmpty);
  });

  Future<void> add(DateTime day) async {
    await store.saveRecurring(
      RecurringRule(
        description: 'Manual daily rent',
        amount: 100,
        category: store.categoriesFor(EntryType.expense).first.name,
        accountId: store.accounts.single.id!,
        nextDate: day,
        day: day.day,
        frequency: RecurrenceFrequency.day,
        automatic: false,
        reminderMinutes: 23 * 60 + 59,
      ),
      today: day,
    );
    await reminders.settled;
  }

  test('manual reminders use local time and bounded separate IDs with explicit confirm actions', () async {
    final today = dateOnly(DateTime.now());
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    await add(tomorrow);
    final scheduled = calls.where((c) => c.method == 'zonedSchedule').toList();
    expect(
      reminders.message.value,
      isNull,
      reason: calls.map((c) => c.method).join(','),
    );
    expect(scheduled.length, 60);
    final first = scheduled.first.arguments as Map;
    expect(first['timeZoneName'], 'Europe/Berlin');
    expect(first['scheduledDateTime'], contains('23:59'));
    final android = first['platformSpecifics'] as Map;
    expect(android['ongoing'], isTrue);
    expect(android['autoCancel'], isFalse);
    expect(
      (android['actions'] as List).singleWhere(
        (a) => a['id'] == 'confirm',
      )['id'],
      'confirm',
    );
    expect(
      (android['actions'] as List).singleWhere(
        (a) => a['id'] == 'confirm',
      )['showsUserInterface'],
      isTrue,
    );
    expect(
      (android['actions'] as List).singleWhere(
        (a) => a['id'] == 'confirm',
      )['cancelNotification'],
      isFalse,
    );
    expect(scheduled.map((c) => (c.arguments as Map)['id']).toSet().length, 60);
    expect(store.entries, isEmpty);
    zone = 'America/New_York';
    calls.clear();
    reminders.sync();
    await reminders.settled;
    expect(
      (calls.firstWhere((c) => c.method == 'zonedSchedule').arguments
          as Map)['timeZoneName'],
      zone,
    );
    expect(reminders.message.value, isNull);
  });

  test(
    'notification body tap queues matching occurrence without posting money',
    () async {
      final today = dateOnly(DateTime.now());
      await add(today);
      await store.processRecurring();
      final occurrence = store.recurringOccurrences.single;
      final response = const StandardMethodCodec().encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', {
          'notificationResponseType': 0,
          'id': 1,
          'payload': jsonEncode({
            'rule': occurrence.ruleId,
            'date': dayKey(occurrence.date),
          }),
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, response, (_) {});
      for (var i = 0; i < 30 && reminders.occurrenceToOpen.value == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(reminders.occurrenceToOpen.value, occurrence.id);
      expect(store.entries, isEmpty);
    },
  );

  test('settings disable cancels reminders and preserves pending payments across startup', () async {
    final today = dateOnly(DateTime.now());
    await add(today);
    await store.processRecurring();
    await reminders.settled;
    final pendingIds = store.recurringOccurrences.map((o) => o.id).toList();
    calls.clear();
    await store.saveNotificationsEnabled(false);
    await reminders.settled;
    expect(calls.where((c) => c.method == 'cancelAll'), isNotEmpty);
    expect(store.recurringOccurrences.map((o) => o.id).toList(), pendingIds);
    expect(store.entries, isEmpty);
    reminders.dispose();
    await reminders.settled;
    calls.clear();
    reminders = RecurringNotifications(store, testPlatform: true);
    await reminders.initialize();
    await reminders.settled;
    expect(
      calls.where((c) => c.method == 'requestNotificationsPermission'),
      isEmpty,
    );
    expect(
      calls.where((c) => c.method == 'zonedSchedule' || c.method == 'show'),
      isEmpty,
    );
    calls.clear();
    await store.saveNotificationsEnabled(true);
    await reminders.settled;
    expect(calls.where((c) => c.method == 'zonedSchedule'), isNotEmpty);
    expect(store.entries, isEmpty);
  });

  test('terminated launch retains target until navigation is ready', () async {
    final today = dateOnly(DateTime.now());
    await add(today);
    await store.processRecurring();
    final occurrence = store.recurringOccurrences.single;
    reminders.dispose();
    await reminders.settled;
    launchResponse = {
      'notificationResponseType': 0,
      'notificationId': 1,
      'payload': jsonEncode({
        'rule': occurrence.ruleId,
        'date': dayKey(occurrence.date),
      }),
    };
    reminders = RecurringNotifications(store, testPlatform: true);
    await reminders.initialize();
    await reminders.settled;
    expect(reminders.occurrenceToOpen.value, occurrence.id);
    expect(store.entries, isEmpty);
  });

  test(
    'native Add to debts action creates one debt without charging the account',
    () async {
      final today = dateOnly(DateTime.now());
      await add(today);
      await store.processRecurring();
      await reminders.settled;
      final occurrence = store.recurringOccurrences.single;
      final response = const StandardMethodCodec().encodeMethodCall(
        MethodCall('didReceiveNotificationResponse', {
          'notificationResponseType': 1,
          'actionId': 'debt',
          'id': 1,
          'payload': jsonEncode({
            'rule': occurrence.ruleId,
            'date': dayKey(occurrence.date),
          }),
        }),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, response, (_) {});
      for (var i = 0; i < 50 && store.debts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await reminders.settled;
      expect(store.debts.single.amount, occurrence.amount);
      expect(store.entries, isEmpty);
      expect(store.recurringOccurrences.single.status, 'skipped');
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, response, (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await reminders.settled;
      expect(store.debts.length, 1);
    },
  );

  test('confirmation notification posts on confirmation date and repeated action cannot double post', () async {
    final today = dateOnly(DateTime.now());
    await add(DateTime(today.year, today.month, today.day - 1));
    await store.processRecurring();
    await reminders.settled;
    final occurrence = store.recurringOccurrences.last;
    final payload = jsonEncode({
      'rule': occurrence.ruleId,
      'date': dayKey(occurrence.date),
    });
    final response = const StandardMethodCodec().encodeMethodCall(
      MethodCall('didReceiveNotificationResponse', {
        'notificationResponseType': 1,
        'id': 1,
        'actionId': 'confirm',
        'payload': payload,
      }),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, response, (_) {});
    for (var i = 0; i < 30 && store.entries.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await reminders.settled;
    expect(store.entries.single.date, today);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, response, (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await reminders.settled;
    expect(store.entries.length, 1);
    expect(
      store.recurringOccurrences.where((o) => o.manual && o.status == 'failed'),
      isNotEmpty,
    );
  });
  test('debt deadlines schedule local actions, route to debt without posting, cancel when kept', () async {
    final now = DateTime.now();
    final deadline = DateTime(now.year, now.month, now.day + 1, 10, 30);
    await store.saveDebt(
      Debt(
        name: 'Loan deadline',
        amount: 5000,
        currency: Currency.eur,
        deadline: deadline,
      ),
    );
    await reminders.settled;
    final d = store.debts.single;
    final request = calls.lastWhere((c) => c.method == 'zonedSchedule');
    final args = request.arguments as Map;
    expect(args['id'], -d.id!);
    expect(args['scheduledDateTime'], contains('10:30'));
    final payload = args['payload'] as String;
    final response = const StandardMethodCodec().encodeMethodCall(
      MethodCall('didReceiveNotificationResponse', {
        'notificationResponseType': 1,
        'id': -d.id!,
        'actionId': 'keep',
        'payload': payload,
      }),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, response, (_) {});
    expect(reminders.occurrenceToOpen.value, -d.id!);
    expect(reminders.debtAction, 'keep');
    expect(store.entries, isEmpty);
    expect(store.debts.single.amount, 5000);
    calls.clear();
    await store.acknowledgeDebtDeadline(d.id!, deadline);
    await reminders.settled;
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    reminders.occurrenceToOpen.value = null;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channel.name, response, (_) {});
    expect(reminders.occurrenceToOpen.value, isNull);
  });
  test(
    'debt deadlines share the 60 request cap with recurring reminders',
    () async {
      final now = DateTime.now();
      final first = DateTime(now.year, now.month, now.day + 1, 9);
      for (var i = 0; i < 3; i++) {
        await store.saveDebt(
          Debt(
            name: 'Due $i',
            amount: 500,
            currency: Currency.eur,
            deadline: first.add(Duration(days: i)),
          ),
        );
      }
      await reminders.settled;
      calls.clear();
      await add(dateOnly(first));
      await reminders.settled;
      final requests = calls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => c.arguments as Map)
          .toList();
      // Mock OS returns no pending requests, so the final sync reissues the shared window.
      expect(requests.length, 60);
      expect(requests.where((a) => (a['id'] as int) < 0).length, 3);
    },
  );
}
