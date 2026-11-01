import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/presentation/async_action.dart';
import 'package:moneva/core/presentation/bottom_action_bar.dart';
import 'package:moneva/core/presentation/store_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets('save shows an animated spinner and prevents duplicate submits', (
    tester,
  ) async {
    final action = AsyncAction();
    final completed = Completer<void>();
    var writes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: action,
            builder: (context, _) => BottomActionBar(
              label: 'Save',
              busy: action.busy,
              onPressed: () => action.run(() {
                writes++;
                return completed.future;
              }, failureMessage: 'Retry'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    final firstAngle = tester.binding.hasScheduledFrame;
    await tester.pump(const Duration(milliseconds: 100));
    expect(firstAngle, isTrue);
    expect(writes, 1);
    completed.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    action.dispose();
  });

  testWidgets(
    'refresh spinner stays responsive without rebuilding page content',
    (tester) async {
      sqfliteFfiInit();
      final store = (await tester.runAsync(
        () => LedgerStore.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      late Completer<void> release;
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StoreStatus(
            store: store,
            child: Builder(
              builder: (_) {
                builds++;
                return const Scaffold(body: Text('Current page'));
              },
            ),
          ),
        ),
      );
      late Future<void> blocker;
      late Future<void> refresh;
      await tester.runAsync(() async {
        release = Completer<void>();
        final locked = Completer<void>();
        blocker = store.db.transaction((txn) async {
          locked.complete();
          await release.future;
        });
        await locked.future;
        refresh = store.refresh();
      });
      await tester.pump();
      expect(store.refreshing.value, isTrue);
      expect(find.bySemanticsLabel('Loading data'), findsOneWidget);
      expect(find.text('Current page'), findsOneWidget);
      final priorBuilds = builds;
      await tester.pump(const Duration(milliseconds: 150));
      expect(builds, priorBuilds);
      await tester.runAsync(() async {
        release.complete();
        await blocker;
        await refresh;
      });
      await tester.pumpAndSettle();
      expect(store.refreshing.value, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(builds, priorBuilds);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await tester.runAsync(store.db.close);
    },
  );
}
