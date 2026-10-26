import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/features/receipts/invoice.dart';
import 'package:moneva/features/receipts/invoice_image_preparation.dart';
import 'package:moneva/features/receipts/invoice_scan_screen.dart';
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class ControlledExtractor implements InvoiceExtractor {
  final requests = <Completer<InvoiceDraft>>[];
  final receivedImages = <List<File>>[];
  @override
  Future<InvoiceDraft> extract(List<File> images, Set<String> categories) {
    final request = Completer<InvoiceDraft>();
    receivedImages.add(List.of(images));
    requests.add(request);
    return request.future;
  }
}

class ControlledImagePreparation extends InvoiceImagePreparation {
  final sources = <File>[];
  final result = Completer<File>();
  @override
  Future<File> prepare(File source) {
    sources.add(source);
    return result.future;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late LedgerStore store;
  late ControlledExtractor extractor;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    extractor = ControlledExtractor();
  });
  tearDown(() async {
    for (final r in extractor.requests) {
      if (!r.isCompleted) {
        r.complete(const InvoiceDraft());
      }
    }
    await store.db.close();
    store.dispose();
  });
  Future<void> open(WidgetTester tester, {Duration? timeout}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => InvoiceScanScreen(
                    store: store,
                    extractor: extractor,
                    autoCapture: false,
                    initialImages: [File('synthetic-missing-image.jpg')],
                    extractionTimeout: timeout,
                  ),
                ),
              ),
              child: const Text('Open scanner'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'capture prepares pages before enabling Extract and reuses the prepared file',
    (tester) async {
      const channel = MethodChannel('cunning_document_scanner');
      final preparation = ControlledImagePreparation();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => ['synthetic-original.png'],
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: InvoiceScanScreen(
            store: store,
            extractor: extractor,
            autoCapture: false,
            imagePreparation: preparation,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan more pages'));
      await tester.pump();
      expect(preparation.sources.single.path, 'synthetic-original.png');
      expect(find.text('Optimizing image 1 of 1'), findsOneWidget);
      final button = find.ancestor(
        of: find.text('Extract'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final prepared = File('synthetic-prepared.jpg');
      preparation.result.complete(prepared);
      await tester.pumpAndSettle();
      expect(extractor.requests, isEmpty);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.tap(find.text('Extract'));
      await tester.pump();
      expect(extractor.receivedImages.single.single, same(prepared));
      await tester.tap(find.text('Cancel extraction'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scanner reads the saved timeout and does not stop at the old one-minute limit',
    (tester) async {
      await tester.runAsync(() => store.saveInvoiceTimeout(300));
      await open(tester);
      await tester.tap(find.text('Extract'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 100));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('Timeout: 300s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 201));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Extraction timed out after 300 seconds'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Extract starts directly, cancellation enables retry and ignores stale response',
    (tester) async {
      await open(tester);
      expect(find.text('Review manually without uploading'), findsNothing);
      expect(find.text('Extract with Gemini'), findsNothing);
      await tester.tap(find.text('Extract'));
      await tester.pump();
      expect(extractor.requests, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Cancel extraction'));
      await tester.pumpAndSettle();
      expect(find.text('Extraction cancelled.'), findsOneWidget);
      await tester.tap(find.text('Extract'));
      await tester.pump();
      expect(extractor.requests, hasLength(2));
      extractor.requests.first.complete(
        const InvoiceDraft(merchant: 'Stale result'),
      );
      await tester.pump();
      expect(find.text('Review invoice'), findsNothing);
      await tester.tap(find.text('Cancel extraction'));
      await tester.pumpAndSettle();
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('overall timeout stops loading and allows retry', (tester) async {
    await open(tester, timeout: const Duration(seconds: 2));
    await tester.tap(find.text('Extract'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.textContaining('Extraction timed out'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.tap(find.text('Extract'));
    await tester.pump();
    expect(extractor.requests, hasLength(2));
    await tester.tap(find.text('Cancel extraction'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Back exits during extraction and late response cannot open review',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Extract'));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open scanner'), findsOneWidget);
      extractor.requests.single.complete(const InvoiceDraft(merchant: 'Late'));
      await tester.pumpAndSettle();
      expect(find.text('Review invoice'), findsNothing);
      expect(store.entries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
