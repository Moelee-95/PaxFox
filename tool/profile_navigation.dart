import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/main.dart';

/// See docs/PERFORMANCE.md. Uses a separate Android ID and an in-memory ledger.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('PAXFOX_BENCHMARK')) {
    throw StateError('Use the documented isolated benchmark command.');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
  );
  final store = await LedgerStore.open(path: ':memory:');
  final today = dateOnly(DateTime.now());
  await store.completeSetup([
    Account(
      name: 'Synthetic cash',
      kind: AccountKind.cash,
      currency: Currency.eur,
      opening: 1000000000,
      asOf: DateTime(today.year - 3),
      includeOnAsOf: true,
    ),
  ]);
  await store.db.transaction((txn) async {
    final batch = txn.batch();
    for (var i = 0; i < 24000; i++) {
      final date = DateTime(today.year, today.month - i % 24, 1 + i % 28);
      batch.insert('transactions', {
        ...LedgerEntry(
          type: i % 3 == 0 ? EntryType.income : EntryType.expense,
          amount: 100 + i,
          currency: Currency.eur,
          date: date,
          description: 'Synthetic transaction $i',
          category: i % 3 == 0 ? 'Salary' : 'Groceries',
          accountId: store.accounts.single.id,
        ).toMap(),
        'created_at': today.toUtc().toIso8601String(),
        'updated_at': today.toUtc().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  });
  final refresh = Stopwatch()..start();
  await store.refresh();
  refresh.stop();
  runApp(MyApp(store: store));
  await Future<void>.delayed(const Duration(seconds: 2));

  T findWidget<T extends Widget>(bool Function(T) match) {
    T? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is T && match(widget)) found = widget;
      if (found == null) element.visitChildElements(visit);
    }

    visit(WidgetsBinding.instance.rootElement!);
    return found ?? (throw StateError('Missing benchmark widget: $T'));
  }

  void month(int direction) => findWidget<IconButton>(
    (w) => w.tooltip == (direction < 0 ? 'Previous month' : 'Next month'),
  ).onPressed!();
  Future<void> pause() =>
      Future<void>.delayed(const Duration(milliseconds: 320));
  final frames = <FrameTiming>[];
  void record(List<FrameTiming> timings) => frames.addAll(timings);
  SchedulerBinding.instance.addTimingsCallback(record);
  final results = <String, Object?>{
    'entries': store.entries.length,
    'refreshMs': refresh.elapsedMilliseconds,
    'refreshRateHz': WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate,
  };
  Future<void> measure(String name, Future<void> Function() work) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    frames.clear();
    await work();
    // Frame timing reports are batched by the engine in profile mode.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    double percentile(List<double> values, double p) {
      values.sort();
      return values[(values.length * p).floor().clamp(0, values.length - 1)];
    }

    if (frames.isEmpty) throw StateError('No frame timings for $name');
    final build = frames
        .map((f) => f.buildDuration.inMicroseconds / 1000)
        .toList();
    final raster = frames
        .map((f) => f.rasterDuration.inMicroseconds / 1000)
        .toList();
    results[name] = {
      'frames': frames.length,
      'buildP95Ms': percentile(build, .95),
      'rasterP95Ms': percentile(raster, .95),
      'buildWorstMs': percentile(build, 1),
      'rasterWorstMs': percentile(raster, 1),
      'buildOver16ms': build.where((v) => v > 16.67).length,
      'rasterOver16ms': raster.where((v) => v > 16.67).length,
    };
  }

  try {
    // Warm font/icon rasterization without visiting the measured months.
    month(-1);
    await pause();
    month(1);
    await pause();
    await measure('firstMonthVisits', () async {
      for (var i = 0; i < 12; i++) {
        month(-1);
        await pause();
      }
    });
    findWidget<TabBar>((w) => w.controller != null).controller!.animateTo(2);
    await pause();
    await measure('monthlyOverview', () async {
      for (var i = 0; i < 12; i++) {
        month(1);
        await pause();
      }
    });
    // Warm all main destinations before measuring retained page switching.
    final nav = findWidget<NavigationBar>((_) => true).onDestinationSelected!;
    for (final index in [1, 3, 0]) {
      nav(index);
      await pause();
    }
    await measure('mainNavigation', () async {
      for (var i = 0; i < 4; i++) {
        for (final index in [1, 3, 0]) {
          nav(index);
          await pause();
        }
      }
    });
    debugPrint('PAXFOX_BENCHMARK ${jsonEncode(results)}');
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(record);
  }
}
