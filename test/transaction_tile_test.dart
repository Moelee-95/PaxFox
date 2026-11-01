import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/transaction_tile.dart';

void main() {
  final previewKey = GlobalKey();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final entry in {
      'PaxleeRoboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final boundary =
          previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  LedgerEntry entry(
    EntryType type, {
    Currency currency = Currency.eur,
    int amount = 1250,
  }) => LedgerEntry(
    type: type,
    amount: amount,
    currency: currency,
    date: DateTime(2026, 10, 31),
    description: 'Weekly shopping',
    category: 'Groceries',
    createdAt: DateTime.utc(2026, 10, 31, 9, 30),
  );

  testWidgets(
    'category badge keeps its color while prices show direction; actions stay connected',
    (tester) async {
      var taps = 0;
      var holds = 0;
      for (final type in EntryType.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: TransactionTile(
                entry: entry(type),
                categoryIcon: CategoryIcon.groceries,
                categoryColor: const Color(0xffef9167),
                selected: true,
                selectionMode: true,
                onTap: () => taps++,
                onLongPress: () => holds++,
              ),
            ),
          ),
        );
        final badge = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('transaction-category-badge')),
        );
        if (type != EntryType.transfer) {
          expect(
            (badge.decoration as BoxDecoration).color,
            const Color(0xffef9167),
          );
        }
        final price = tester.widget<Text>(
          find.byKey(const ValueKey('transaction-price')),
        );
        expect(price.data, switch (type) {
          EntryType.expense => '-€12.50',
          EntryType.income || EntryType.refund => '+€12.50',
          EntryType.transfer => '€12.50',
        });
        expect(price.style!.color, switch (type) {
          EntryType.expense => Colors.red.shade700,
          EntryType.income || EntryType.refund => Colors.green.shade700,
          EntryType.transfer => Colors.blue.shade700,
        });
        expect(find.text('Groceries'), findsNothing);
        expect(find.text('Transfer'), findsNothing);
        expect(find.text('Weekly shopping'), findsOneWidget);
        final title = tester.widget<Text>(find.text('Weekly shopping'));
        expect(title.style!.fontWeight, FontWeight.w700);
        expect(title.style!.fontSize, 16);
        expect(find.textContaining('Added on '), findsOneWidget);
        expect(find.textContaining('Date: 2026-10-31'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('transaction-created-info')),
          findsNothing,
        );
        expect(tester.getSize(find.byType(Card)).height, lessThanOrEqualTo(80));
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.selected == true,
          ),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        await tester.tap(find.text('Weekly shopping'));
        await tester.longPress(find.text('Weekly shopping'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(taps, 4);
      expect(holds, 4);
    },
  );

  testWidgets(
    'phone row previews in light and dark; large IQD values and long descriptions wrap',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Widget app({bool large = false}) => RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Scaffold(
            appBar: AppBar(title: const Text('Transaction row preview')),
            body: ListView(
              children: [
                for (final type in EntryType.values)
                  TransactionTile(
                    entry: large
                        ? LedgerEntry(
                            type: type,
                            amount: 9000000000000000,
                            currency: Currency.iqd,
                            date: DateTime(2026, 10, 31),
                            description: 'A longer description that stays visible on small phones',
                            category:
                                'Household shopping and family essentials',
                          )
                        : entry(type),
                    categoryIcon: type == EntryType.income
                        ? CategoryIcon.salary
                        : CategoryIcon.groceries,
                    categoryColor: type == EntryType.income
                        ? const Color(0xff39bbcc)
                        : const Color(0xffef9167),
                    onTap: () {},
                    onLongPress: () {},
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await capture(tester, 'transaction-rows-light');
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'transaction-rows-dark');
      tester.view.physicalSize = const Size(320, 740);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pumpWidget(app(large: true));
      await tester.pumpAndSettle();
      await capture(tester, 'transaction-rows-large-text');
      expect(tester.takeException(), isNull);
      expect(find.text('-IQD 9,000,000,000,000.000'), findsOneWidget);
    },
  );
}
