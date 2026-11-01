import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/main.dart';
import 'package:moneva/screens/more_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

void main() {
  late LedgerStore store;
  final previewKey = GlobalKey();

  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final entry in {
      'PaxFoxRoboto': 'assets/fonts/Roboto-Regular.ttf',
      'Roboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

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
        asOf: dateOnly(DateTime.now()),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
  });

  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(tab('More'));
    await tester.pumpAndSettle();
  }

  Future<void> showOption(
    WidgetTester tester,
    Finder finder, {
    bool fromTop = false,
  }) async {
    final scrollable = find
        .descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    if (fromTop) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
    }
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  test('profile persists together, validates before writing and leaves ledger unchanged', () async {
    expect(store.profileName, isEmpty);
    expect(store.profileEmail, isEmpty);
    await store.saveProfile(
      name: '  Alex Morgan  ',
      email: '  alex@example.com  ',
    );
    final reloaded = LedgerStore(store.db);
    addTearDown(reloaded.dispose);
    await reloaded.refresh();
    expect(reloaded.profileName, 'Alex Morgan');
    expect(reloaded.profileEmail, 'alex@example.com');
    await expectLater(
      store.saveProfile(name: 'Changed', email: 'invalid'),
      throwsArgumentError,
    );
    await expectLater(
      store.saveProfile(name: '', email: ''),
      throwsArgumentError,
    );
    await store.refresh();
    expect(store.profileName, 'Alex Morgan');
    expect(store.profileEmail, 'alex@example.com');
    await store.saveProfile(name: 'Alex', email: '');
    await reloaded.refresh();
    expect(reloaded.profileEmail, isEmpty);
    expect(store.setupCompleted, isTrue);
    expect(store.currency, Currency.eur);
    expect(store.currentBalances.available, 10000);
    expect(store.entries, isEmpty);
  });

  testWidgets(
    'More replaces the drawer and management and transaction Back return to More',
    (tester) async {
      await tester.pumpWidget(MyApp(store: store));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.byTooltip('Open menu'), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      await openMore(tester);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.byTooltip('Add transaction'), findsNothing);
      expect(find.text('Your profile'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Home'), findsNothing);
      for (final destination in MoreDestination.values) {
        final tile = find.widgetWithText(ListTile, destination.label);
        await showOption(tester, tile);
        expect(tile, findsOneWidget);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        if (destination == MoreDestination.transactions) {
          expect(find.byType(BackButton), findsOneWidget);
          await tester.tap(find.byType(BackButton));
        } else {
          expect(find.byType(MoreScreen), findsNothing);
          await tester.pageBack();
        }
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          3,
        );
        expect(find.byType(MoreScreen), findsOneWidget);
      }
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(find.byKey(const ValueKey('month-selector')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search filters options and support actions remain deferred', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await openMore(tester);
    await tester.enterText(find.byType(TextField), 'privacy');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Categories'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Privacy Policy'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    await showOption(tester, find.widgetWithText(ListTile, 'Help & FAQ'));
    for (final title in [
      'Help & FAQ',
      'Rate App',
      'Changelog',
      'Privacy Policy',
      'Terms and Conditions',
      'About',
    ]) {
      final tile = find.widgetWithText(ListTile, title);
      expect(tester.widget<ListTile>(tile).onTap, isNull);
    }
    await showOption(tester, find.byType(TextField), fromTop: true);
    await tester.enterText(find.byType(TextField), 'no such option');
    await tester.pumpAndSettle();
    expect(find.text('No matching options.'), findsOneWidget);
    expect(find.byTooltip('Edit profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile edit validates, saves and supports cancel', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await openMore(tester);
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Alex Morgan',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email (optional)'),
      'alex@example.com',
    );
    await tester.tap(find.text('Save profile'));
    await tester.runAsync(
      () => waitForStore(store, () => store.profileName == 'Alex Morgan'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('alex@example.com'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit profile'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Unsaved name',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.profileName, 'Alex Morgan');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone layouts render in light, dark and large text with long profile values',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () => store.saveProfile(name: 'Alex Morgan', email: 'alex@example.com'),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: previewKey,
          child: MyApp(store: store),
        ),
      );
      await tester.pumpAndSettle();
      await openMore(tester);
      await capture(tester, 'more-light');
      await showOption(tester, find.widgetWithText(ListTile, 'About'));
      await tester.pumpAndSettle();
      await capture(tester, 'more-support-light');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'more-support-dark');
      await showOption(
        tester,
        find.byKey(const ValueKey('more-profile-card')),
        fromTop: true,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'more-dark');
      tester.view.physicalSize = const Size(320, 740);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.runAsync(
        () => store.saveProfile(
          name: 'A longer profile name that wraps on a small phone',
          email: 'a.longer.email.address.for.layout@example.com',
        ),
      );
      await tester.pumpAndSettle();
      await showOption(
        tester,
        find.byKey(const ValueKey('more-profile-card')),
        fromTop: true,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'more-large-text');
      await showOption(
        tester,
        find.widgetWithText(ListTile, 'Terms and Conditions'),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'more-support-large-text');
      expect(tester.takeException(), isNull);
    },
  );
}
