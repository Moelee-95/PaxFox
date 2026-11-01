import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/ledger_queries.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/monthly_savings_chart.dart';

void main() {
  final preview = GlobalKey();
  final today = DateTime(2026, 11, 15);
  LedgerEntry entry(
    EntryType type,
    int amount,
    int month, [
    Currency currency = Currency.eur,
  ]) => LedgerEntry(
    type: type,
    amount: amount,
    currency: currency,
    date: DateTime(2026, month, 10),
    description: 'Example',
    category: 'Other',
  );
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final font in {
      'PaxFoxRoboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(font.value).readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  Future<void> launch(
    WidgetTester tester,
    LedgerIndex ledger, {
    bool dark = false,
    double scale = 1,
    double width = 430,
    Currency currency = Currency.eur,
  }) async {
    tester.view.physicalSize = Size(width, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: MonthlySavingsChart(
                  currency: currency,
                  summaryForMonth: ledger.forMonth,
                  today: today,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/savings-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  final fixture = LedgerIndex([
    entry(EntryType.income, 240000, 6),
    entry(EntryType.expense, 210000, 6),
    entry(EntryType.income, 240000, 7),
    entry(EntryType.expense, 200000, 7),
    entry(EntryType.income, 240000, 8),
    entry(EntryType.expense, 265000, 8),
    entry(EntryType.income, 260000, 9),
    entry(EntryType.expense, 205000, 9),
    entry(EntryType.income, 240000, 10),
    entry(EntryType.expense, 180000, 10),
    entry(EntryType.refund, 10000, 10),
    entry(EntryType.transfer, 999999, 10),
    entry(EntryType.income, 100000, 11),
    entry(EntryType.expense, 120000, 11),
    entry(EntryType.income, 999999, 11, Currency.usd),
  ]);
  testWidgets(
    'net savings excludes transfers and other currencies and includes refunds',
    (tester) async {
      await launch(tester, fixture);
      final chart = tester.widget<BarChart>(find.byType(BarChart));
      expect(chart.data.barGroups.map((g) => g.barRods.single.toY), [
        300,
        400,
        -250,
        550,
        700,
        -200,
      ]);
      expect(
        chart.data.barGroups.map((group) => group.barRods.single.label.text),
        ['300', '400', '-250', '550', '700', '-200'],
      );
      expect(
        chart.data.barGroups.every((group) => group.barRods.single.label.show),
        isTrue,
      );
      expect(find.text('Net savings: \u20ac-200.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('savings-month-2026-10')));
      await tester.pumpAndSettle();
      expect(find.text('Net savings: \u20ac700.00'), findsOneWidget);
      expect(find.text('Expenses: \u20ac1,700.00'), findsOneWidget);
      await capture(tester, 'light');
      final rect = tester.getRect(find.byType(BarChart));
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      final gutter = data.titlesData.leftTitles.sideTitles.reservedSize;
      await tester.tapAt(
        Offset(
          rect.left + gutter + (rect.width - gutter) / 12,
          rect.top + (data.maxY - 150) / (data.maxY - data.minY) * rect.height,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Net savings: \u20ac300.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('history crosses years and cannot advance beyond current month', (
    tester,
  ) async {
    await launch(tester, fixture);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Later months'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Earlier months'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('savings-month-2025-12')), findsOneWidget);
    await tester.tap(find.byTooltip('Later months'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('savings-month-2026-11')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty and zero-net months have finite axes and selectable totals',
    (tester) async {
      await launch(tester, LedgerIndex([]));
      final data = tester.widget<BarChart>(find.byType(BarChart)).data;
      expect(data.minY, 0);
      expect(data.maxY, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('savings-month-2026-6')));
      await tester.pumpAndSettle();
      expect(find.text('Net savings: \u20ac0.00'), findsOneWidget);
      expect(find.textContaining('No income or expenses'), findsOneWidget);
      await capture(tester, 'empty');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'snapshot changes refresh selected totals without resetting history',
    (tester) async {
      await launch(tester, fixture);
      await tester.tap(find.byTooltip('Earlier months'));
      await tester.pumpAndSettle();
      await launch(tester, LedgerIndex([entry(EntryType.income, 12345, 5)]));
      expect(
        find.byKey(const ValueKey('savings-month-2026-5')),
        findsOneWidget,
      );
      expect(find.text('Net savings: \u20ac123.45'), findsOneWidget);
    },
  );
  testWidgets('dark large text keeps six labeled months and IQD precision', (
    tester,
  ) async {
    await launch(
      tester,
      LedgerIndex([entry(EntryType.income, 1234567, 11, Currency.iqd)]),
      dark: true,
      scale: 1.8,
      width: 320,
      currency: Currency.iqd,
    );
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).data.barGroups,
      hasLength(6),
    );
    final rods = tester.widget<BarChart>(find.byType(BarChart)).data.barGroups;
    expect(rods.map((group) => group.barRods.single.label.text), [
      '0',
      '0',
      '0',
      '0',
      '0',
      '1.2K',
    ]);
    expect(find.byKey(const ValueKey('savings-month-2026-6')), findsOneWidget);
    expect(find.text('Net savings: IQD 1,234.567'), findsOneWidget);
    await capture(tester, 'dark-large');
    expect(tester.takeException(), isNull);
  });
}
