import 'package:flutter/material.dart' show Color;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;
import 'package:timezone/data/latest.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

import '../domain/ledger.dart';
import '../domain/recurring.dart';
import 'ledger_store.dart';

/// OS notifications are a reminder only. The SQLite occurrence is authoritative:
/// no financial write happens until an explicit confirmation action.
class RecurringNotifications {
  static RecurringNotifications? instance;
  RecurringNotifications(this.store, {this.testPlatform = false});
  final bool testPlatform;
  final LedgerStore store;
  final plugin = FlutterLocalNotificationsPlugin();
  final message = ValueNotifier<String?>(null);
  // Retained until the main navigator is ready, including terminated launches.
  final occurrenceToOpen = ValueNotifier<int?>(null);
  String? debtAction;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  bool _syncRequested = false;
  bool _syncRunning = false;
  final _scheduledFingerprints = <int, String>{};
  bool get supported => testPlatform || Platform.isAndroid || Platform.isIOS;

  Future<void> initialize() async {
    if (!supported) return;
    zones.initializeTimeZones();
    await plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              'debt_deadline',
              actions: [
                DarwinNotificationAction.plain(
                  'keep',
                  'Keep / edit',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  'pay',
                  'Pay / receive',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
            DarwinNotificationCategory(
              'payment',
              actions: [
                DarwinNotificationAction.plain(
                  'debt',
                  'Add to debts / receivables',
                  options: {
                    DarwinNotificationActionOption.foreground,
                    DarwinNotificationActionOption.destructive,
                  },
                ),
                DarwinNotificationAction.plain(
                  'confirm',
                  'Confirm payment',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          unawaited(_respond(response)),
    );
    store.addListener(sync);
    try {
      // Ask on startup, including before setup or any recurring rule exists.
      // Exact-alarm access is requested only when saving a manual reminder.
      if (store.notificationsEnabled) {
        await requestPermissions(requestExactTiming: false);
      }
    } catch (_) {
      message.value = 'Could not request notification permission. Enable notifications in your phone settings to receive payment reminders.';
    }
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      await _respond(launch!.notificationResponse!);
    }
    sync();
  }

  Future<bool> requestPermissions({bool requestExactTiming = true}) async {
    if (!supported) return false;
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = android != null
        ? await android.requestNotificationsPermission() ?? false
        : await plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
    if (requestExactTiming &&
        enabled &&
        android != null &&
        await android.canScheduleExactNotifications() != true) {
      await android.requestExactAlarmsPermission();
    }
    return enabled;
  }

  Future<void> _respond(NotificationResponse response) async {
    if (response.payload == null) return;
    final confirm = response.actionId == 'confirm';
    final toDebt = response.actionId == 'debt';
    if (!confirm &&
        !toDebt &&
        response.actionId != 'pay' &&
        response.actionId != 'keep' &&
        response.notificationResponseType !=
            NotificationResponseType.selectedNotification) {
      return;
    }
    try {
      final payload = jsonDecode(response.payload!) as Map<String, dynamic>;
      if (payload['debt'] is int) {
        final debt = store.debts
            .where(
              (d) =>
                  d.id == payload['debt'] &&
                  d.hasPendingDeadline &&
                  d.deadline!.toIso8601String() == payload['deadline'],
            )
            .firstOrNull;
        if (debt == null) return;
        debtAction = ['pay', 'keep'].contains(response.actionId)
            ? response.actionId
            : null;
        occurrenceToOpen.value = -debt.id!;
        return;
      }
      await store.processRecurring();
      final occurrence = store.recurringOccurrences
          .where(
            (o) =>
                o.ruleId == payload['rule'] &&
                dayKey(o.date) == payload['date'],
          )
          .firstOrNull;
      if (occurrence == null || !occurrence.manual) return;
      if (toDebt) {
        await store.moveRecurringToDebt(occurrence.id);
        message.value = occurrence.type == EntryType.income
            ? 'Added to money owed to you.'
            : 'Added to debts.';
        if (response.id != null) await plugin.cancel(id: response.id!);
        sync();
        return;
      }
      if (!confirm) {
        occurrenceToOpen.value = occurrence.id;
        return;
      }
      await store.retryRecurring(occurrence.id);
      final saved = store.recurringOccurrences.firstWhere(
        (o) => o.id == occurrence.id,
      );
      message.value = saved.status == 'posted'
          ? 'Payment confirmed.'
          : saved.error ?? 'Payment could not be confirmed. Open Recurring payments to retry.';
      if (saved.status == 'posted' && response.id != null) {
        await plugin.cancel(id: response.id!);
      }
    } catch (_) {
      message.value =
          'Payment could not be confirmed. Open Recurring payments to retry.';
    }
    sync();
  }

  void sync() {
    if (_disposed || !supported) return;
    _syncRequested = true;
    if (_syncRunning) return;
    _syncRunning = true;
    _queue = _queue.then((_) async {
      try {
        while (_syncRequested && !_disposed) {
          _syncRequested = false;
          try {
            await _sync();
          } catch (_) {
            message.value = 'Payment reminders could not be scheduled. Check notification permissions; pending payments remain in Recurring.';
          }
        }
      } finally {
        _syncRunning = false;
      }
    });
  }

  Future<void> _sync() async {
    if (!store.notificationsEnabled) {
      await plugin.cancelAll();
      _scheduledFingerprints.clear();
      return;
    }
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
    final now = tz.TZDateTime.now(tz.local);
    final candidates = <({RecurringRule rule, DateTime date, bool pending})>[];
    final allRules = (await store.db.query('recurring_rules'))
        .map(RecurringRule.fromMap);
    final byId = {for (final r in allRules) r.id: r};
    for (final occurrence in store.recurringOccurrences) {
      final rule = byId[occurrence.ruleId];
      if (!occurrence.manual || occurrence.status != 'failed' || rule == null) {
        continue;
      }
      candidates.add((rule: rule, date: occurrence.date, pending: true));
    }
    // The OS owns delivery while the process is closed. Fill a chronological
    // rolling window below iOS's 64-request limit, refreshed on every app resume.
    for (final rule in store.recurringRules.where(
      (r) => r.active && !r.automatic,
    )) {
      var date = rule.nextDate;
      for (var i = 0; i < 60; i++) {
        if (rule.endDate != null && date.isAfter(rule.endDate!)) break;
        candidates.add((rule: rule, date: date, pending: false));
        date = nextRecurringDate(
          date,
          rule.frequency,
          rule.interval,
          rule.day,
          rule.month,
        );
      }
    }
    candidates.sort((a, b) => a.date.compareTo(b.date));
    final wanted = <int>{};
    final scheduled = await plugin.pendingNotificationRequests();
    final activeNotifications = await plugin.getActiveNotifications();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final exact =
        android == null ||
        await android.canScheduleExactNotifications() == true;
    tz.TZDateTime debtTime(Debt debt) {
      final d = debt.deadline!;
      return tz.TZDateTime(tz.local, d.year, d.month, d.day, d.hour, d.minute);
    }

    final debtCandidates = store.debts
        .where((d) => d.hasPendingDeadline)
        .toList();
    final futureRequests =
        <({String key, tz.TZDateTime time})>[
          for (final d in debtCandidates)
            if (debtTime(d).isAfter(now)) (key: 'd${d.id}', time: debtTime(d)),
          for (final c in candidates)
            (
              key: 'r${c.rule.id}_${dayKey(c.date)}',
              time: tz.TZDateTime(
                tz.local,
                c.date.year,
                c.date.month,
                c.date.day,
                c.rule.reminderMinutes ~/ 60,
                c.rule.reminderMinutes % 60,
              ),
            ),
        ].where((c) => c.time.isAfter(now)).toList()..sort(
          (a, b) => a.time.compareTo(b.time),
        );
    final allowedFuture = futureRequests
        .map((r) => r.key)
        .toSet()
        .take(60)
        .toSet();
    for (final candidate in candidates) {
      final rule = candidate.rule;
      final date = candidate.date;
      final time = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        rule.reminderMinutes ~/ 60,
        rule.reminderMinutes % 60,
      );
      final future = time.isAfter(now);
      if (future && !allowedFuture.contains('r${rule.id}_${dayKey(date)}')) {
        continue;
      }
      if (!future && !candidate.pending) continue;
      final key = dayKey(date);
      await store.db.insert('recurring_reminders', {
        'rule_id': rule.id,
        'due_date': key,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final row = (await store.db.query(
        'recurring_reminders',
        where: 'rule_id = ? AND due_date = ?',
        whereArgs: [rule.id, key],
      )).single;
      final id = row['id'] as int;
      wanted.add(id);
      final payload = jsonEncode({'rule': rule.id, 'date': key});
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'manual_payments',
          'Payment confirmations',
          channelDescription:
              'Recurring payments waiting for your confirmation',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          actions: [
            AndroidNotificationAction(
              'debt',
              rule.type == EntryType.income
                  ? 'Add to receivables'
                  : 'Add to debts',
              titleColor: const Color(0xffce3541),
              showsUserInterface: true,
              cancelNotification: false,
            ),
            const AndroidNotificationAction(
              'confirm',
              'Confirm payment',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'payment',
          threadIdentifier: 'manual_payments',
        ),
      );
      final occurrence = store.recurringOccurrences
          .where((o) => o.ruleId == rule.id && dayKey(o.date) == key)
          .firstOrNull;
      final amount = occurrence?.amount ?? rule.amount;
      final currency = occurrence?.currency ?? rule.currency ?? store.currency;
      final title = occurrence?.description ?? rule.description;
      final body = '${currency.display(amount)} - due $key. Confirm when paid.';
      final fingerprint =
          '$title|$body|${time.toIso8601String()}|${info.identifier}|$exact';
      if (_scheduledFingerprints[id] == fingerprint &&
          (future
              ? scheduled.any((request) => request.id == id)
              : activeNotifications.any(
                  (notification) => notification.id == id,
                ))) {
        continue;
      }
      if (future) {
        // Rescheduling the same ID updates changes to time, amount, and time zone.
        await plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: time,
          notificationDetails: details,
          payload: payload,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } else {
        await plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload,
        );
      }
      _scheduledFingerprints[id] = fingerprint;
    }
    for (final debt in debtCandidates) {
      final id = -debt.id!;
      final time = debtTime(debt);
      final future = time.isAfter(now);
      if (future && !allowedFuture.contains('d${debt.id}')) continue;
      wanted.add(id);
      final payload = jsonEncode({
        'debt': debt.id,
        'deadline': debt.deadline!.toIso8601String(),
      });
      final title = debt.isReceivable
          ? 'Receivable due: ${debt.name}'
          : 'Debt due: ${debt.name}';
      final body =
          '${debt.currency.display(debt.amount)} - pay/receive or keep and edit.';
      final fingerprint =
          '$title|$body|${time.toIso8601String()}|${info.identifier}|$exact';
      if (_scheduledFingerprints[id] == fingerprint &&
          (future
              ? scheduled.any((r) => r.id == id)
              : activeNotifications.any((n) => n.id == id))) {
        continue;
      }
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'debt_deadlines',
          'Debt deadlines',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          actions: [
            const AndroidNotificationAction(
              'keep',
              'Keep / edit',
              showsUserInterface: true,
              cancelNotification: false,
            ),
            AndroidNotificationAction(
              'pay',
              debt.isReceivable ? 'Receive payment' : 'Pay debt',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          categoryIdentifier: 'debt_deadline',
          threadIdentifier: 'debt_deadlines',
        ),
      );
      if (future) {
        await plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: time,
          notificationDetails: details,
          payload: payload,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } else {
        await plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details,
          payload: payload,
        );
      }
      _scheduledFingerprints[id] = fingerprint;
    }
    _scheduledFingerprints.removeWhere((id, _) => !wanted.contains(id));
    for (final pending in scheduled) {
      if (!wanted.contains(pending.id)) await plugin.cancel(id: pending.id);
    }
    for (final active in activeNotifications) {
      if (active.id != null && !wanted.contains(active.id)) {
        await plugin.cancel(id: active.id!);
      }
    }
    if (!exact && candidates.isNotEmpty) message.value = 'Exact reminder timing is disabled. Enable Alarms & reminders for PaxFox in Android settings; reminders may arrive late until then.';
  }

  Future<void> get settled => _queue;

  void dispose() {
    _disposed = true;
    store.removeListener(sync);
  }
}
