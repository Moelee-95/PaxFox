import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/screens/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late LedgerStore store;
  setUp(() async {
    sqfliteFfiInit();
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await store.db.close();
    store.dispose();
  });
  test(
    'timeout defaults, validates limits and reloads persisted values',
    () async {
      expect(store.invoiceTimeoutSeconds, 180);
      for (final invalid in [0, 29, 901]) {
        await expectLater(
          store.saveInvoiceTimeout(invalid),
          throwsArgumentError,
        );
      }
      await store.saveInvoiceTimeout(600);
      store.invoiceTimeoutSeconds = 180;
      await store.refresh();
      expect(store.invoiceTimeoutSeconds, 600);
      expect(
        (await store.db.query(
          'settings',
          where: 'key = ?',
          whereArgs: ['invoice_timeout_seconds'],
        )).single['value'],
        '600',
      );
    },
  );
  test('Gemini source and manual key persist independently', () async {
    await store.saveInvoiceSettings(
      seconds: 240,
      configUrl: 'https://example.com/config.json?app=paxfox',
      useManualKey: true,
      manualKey: 'synthetic-manual-key-for-tests',
    );
    await store.refresh();
    expect(store.geminiUseManualKey, isTrue);
    expect(store.geminiManualKey, 'synthetic-manual-key-for-tests');
    expect(store.geminiConfigUrl, 'https://example.com/config.json?app=paxfox');
    await store.saveInvoiceSettings(
      seconds: 240,
      configUrl: store.geminiConfigUrl,
      useManualKey: false,
      manualKey: store.geminiManualKey,
    );
    expect(store.geminiUseManualKey, isFalse);
    expect(store.geminiManualKey, 'synthetic-manual-key-for-tests');
    for (final url in [
      'http://example.com/key',
      'invalid',
      'https://user:pass@example.com',
    ]) {
      await expectLater(
        store.saveInvoiceSettings(
          seconds: 240,
          configUrl: url,
          useManualKey: false,
          manualKey: '',
        ),
        throwsArgumentError,
      );
    }
    await expectLater(
      store.saveInvoiceSettings(
        seconds: 240,
        configUrl: store.geminiConfigUrl,
        useManualKey: true,
        manualKey: '',
      ),
      throwsArgumentError,
    );
    expect(store.geminiManualKey, 'synthetic-manual-key-for-tests');
  });
  testWidgets('manual source toggles key input and info sits in scanning row', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.info_outline),
      ),
      findsNothing,
    );
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Manual API key').last);
    await tester.pumpAndSettle();
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields[1].enabled, isFalse);
    expect(fields[2].enabled, isTrue);
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'synthetic-key-entered-in-settings',
    );
    await tester.ensureVisible(find.text('Save settings'));
    await tester.tap(find.text('Save settings'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.geminiUseManualKey, isTrue);
    expect(store.geminiManualKey, 'synthetic-key-entered-in-settings');
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings validate and save custom extraction timeout', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    await tester.enterText(find.byType(TextFormField).first, '10');
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 30 to 900.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '420');
    await tester.tap(find.text('Save settings'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(store.invoiceTimeoutSeconds, 420);
    expect(tester.takeException(), isNull);
  });

  testWidgets('key help opens AI Studio and keeps a copyable link on failure', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final requests = <MethodCall>[];
    var succeeds = false;
    var throwsError = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requests.add(call);
      if (throwsError) throw PlatformException(code: 'no_browser');
      return succeeds;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: SettingsScreen(store: store)));
    final help = find.byWidgetPredicate(
      (widget) =>
          widget is Icon && widget.semanticLabel == 'Get a Gemini API key',
    );
    await tester.ensureVisible(help);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.text('Get a Gemini API key'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'https://aistudio.google.com/apikey',
    );
    final open = find.text('Open Google AI Studio');
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(requests.single.method, 'launch');
    expect(
      requests.single.arguments['url'],
      'https://aistudio.google.com/apikey',
    );
    expect(requests.single.arguments['useSafariVC'], isFalse);
    expect(requests.single.arguments['useWebView'], isFalse);
    expect(find.textContaining('Could not open the browser.'), findsOneWidget);
    throwsError = true;
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open the browser.'), findsOneWidget);
    throwsError = false;
    succeeds = true;
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open the browser.'), findsNothing);
    expect(store.geminiUseManualKey, isFalse);
    expect(tester.takeException(), isNull);
  });
}
