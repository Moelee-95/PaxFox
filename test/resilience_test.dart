import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/app_failure.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/async_action.dart';
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:moneva/features/receipts/gemini_key_provider.dart';
import 'package:moneva/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('safe retryable actions', () {
    test('ignores double submit and resets busy after a failure', () async {
      final action = AsyncAction();
      addTearDown(action.dispose);
      final request = Completer<void>();
      final first = action.run(() => request.future, failureMessage: 'Retry');
      expect(action.busy, isTrue);
      expect(
        await action.run(
          () async => fail('Duplicate'),
          failureMessage: 'Retry',
        ),
        isFalse,
      );
      request.completeError(const SocketException('private host'));
      expect(await first, isFalse);
      expect(action.busy, isFalse);
      expect(action.error, contains('internet connection'));
      expect(action.error, isNot(contains('private host')));
      expect(await action.run(() async {}, failureMessage: 'Retry'), isTrue);
      expect(action.error, isNull);
    });

    test('completion after disposal does not notify or navigate', () async {
      final action = AsyncAction();
      final request = Completer<void>();
      var notifications = 0;
      action.addListener(() => notifications++);
      final result = action.run(() => request.future, failureMessage: 'Retry');
      action.dispose();
      request.complete();
      expect(await result, isFalse);
      expect(notifications, 1);
    });
  });

  group('invoice failures', () {
    late Directory directory;
    late File image;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('moneva_resilience_');
      image = await File('${directory.path}/receipt.jpg')
          .writeAsBytes(img.encodeJpg(img.Image(width: 10, height: 10)));
    });
    tearDown(() async {
      await image.delete();
      await directory.delete();
    });

    Future<void> failsSafely(http.Client client, String message) async {
      addTearDown(client.close);
      await expectLater(
        GeminiInvoiceExtractor(
          client: client,
          keyLoader: () async => 'synthetic-test-key',
        ).extract([image], {'Groceries'}),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
      expect(await image.exists(), isTrue);
    }

    for (final (status, message) in [
      (401, 'access'),
      (403, 'access'),
      (429, 'usage limit'),
      (503, 'temporarily unavailable'),
      (504, 'too long'),
    ]) {
      test(
        'HTTP $status gives recovery guidance without exposing response data',
        () async {
          await failsSafely(
            MockClient(
              (_) async => http.Response('private provider payload', status),
            ),
            message,
          );
        },
      );
    }

    test('offline failure leaves images available', () async {
      await failsSafely(
        MockClient((_) async => throw const SocketException('secret hostname')),
        'internet connection',
      );
    });

    for (final body in [
      'not json',
      '[]',
      '{"candidates":{}}',
      '{"candidates":[null]}',
      '{"candidates":[{"finishReason":"STOP","content":null}]}',
    ]) {
      test('malformed response is safe: $body', () async {
        await failsSafely(
          MockClient((_) async => http.Response(body, 200)),
          'unreadable response',
        );
      });
    }

    test('timeout includes key loading and ignores late completion', () async {
      final key = Completer<String>();
      final entered = Completer<void>();
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final extractor = GeminiInvoiceExtractor(
        client: client,
        keyLoader: () {
          entered.complete();
          return key.future;
        },
        timeout: const Duration(seconds: 1),
      );
      final result = extractor.extract([image], {});
      final assertion = expectLater(
        result,
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      await entered.future;
      await assertion;
      key.complete('synthetic-test-key');
      await Future<void>.delayed(Duration.zero);
      expect(requests, 0);
    });

    test(
      'a stalled HTTP request times out and ignores its late response',
      () async {
        final response = Completer<http.Response>();
        final client = MockClient((_) => response.future);
        addTearDown(client.close);
        final result = GeminiInvoiceExtractor(
          client: client,
          keyLoader: () async => 'synthetic-test-key',
          timeout: const Duration(seconds: 1),
        ).extract([image], {});
        await expectLater(
          result,
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('timed out'),
            ),
          ),
        );
        response.complete(http.Response(jsonEncode({'candidates': []}), 200));
      },
    );

    test(
      'key service failures are safe and retain their recovery guidance',
      () async {
        final client = MockClient(
          (_) async => http.Response('private configuration', 503),
        );
        addTearDown(client.close);
        await expectLater(
          GeminiKeyProvider.fetchKey(client: client),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.message,
              'message',
              contains('temporarily unavailable'),
            ),
          ),
        );
      },
    );
  });

  group('committed storage recovery', () {
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
          asOf: DateTime(2026),
          kind: AccountKind.cash,
          includeOnAsOf: true,
        ),
      ]);
    });
    tearDown(() async {
      store.dispose();
      await store.db.close();
    });

    Future<void> failReload() => store.db.update(
      'settings',
      {'value': 'invalid'},
      where: 'key = ?',
      whereArgs: ['app_currency'],
    );
    Future<void> repair() => store.db.update(
      'settings',
      {'value': 'eur'},
      where: 'key = ?',
      whereArgs: ['app_currency'],
    );
    Future<void> save() => store.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 100,
        currency: Currency.eur,
        date: DateTime(2026, 10, 26),
        description: 'Saved once',
        category: 'Groceries',
        accountId: store.accounts.single.id,
      ),
    );

    test('commit followed by failed reload returns success; reload does not duplicate', () async {
      final progress = <bool>[];
      store.refreshing.addListener(() => progress.add(store.refreshing.value));
      await failReload();
      await save();
      expect(store.snapshotNeedsRefresh, isTrue);
      expect(store.entries, isEmpty);
      expect(await store.db.query('transactions'), hasLength(1));
      await repair();
      await store.refresh();
      expect(store.snapshotNeedsRefresh, isFalse);
      expect(store.entries.single.description, 'Saved once');
      expect(progress, [true, false, true, false]);
      expect(store.refreshing.value, isFalse);
    });

    testWidgets('recovery banner retries safely while preserving navigation', (
      tester,
    ) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await failReload();
        await save();
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Changes saved. Reload data to continue.'),
        findsOneWidget,
      );
      Future<void> retry() => tester.runAsync(
        tester
                .widget<TextButton>(find.widgetWithText(TextButton, 'Retry'))
                .onPressed!
            as Future<void> Function(),
      );
      await retry();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await tester.runAsync(repair);
      await retry();
      await tester.pumpAndSettle();
      expect(
        find.text('Changes saved. Reload data to continue.'),
        findsNothing,
      );
      expect(find.text('Account wealth'), findsOneWidget);
      expect(store.entries, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
