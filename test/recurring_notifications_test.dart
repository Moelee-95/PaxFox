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
  setUp(() async {
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    sqfliteFfiInit();
    calls.clear();
    exact = true;
    zone = 'Europe/Berlin';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => {
              'notificationLaunchedApp': false,
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
    expect((android['actions'] as List).single['id'], 'confirm');
    expect((android['actions'] as List).single['showsUserInterface'], isTrue);
    expect((android['actions'] as List).single['cancelNotification'], isFalse);
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
}
