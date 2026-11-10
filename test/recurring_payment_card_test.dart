import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/domain/recurring.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/recurring_payment_card.dart';

void main() {
  final key = GlobalKey();
  final today = DateTime(2026, 11, 10);
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    final bytes = await File('assets/fonts/Roboto-Regular.ttf').readAsBytes();
    for (final family in ['PaxFoxRoboto', 'Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    final icons = await File(
      'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  RecurringRule rule({
    int id = 1,
    EntryType type = EntryType.expense,
    bool active = true,
    DateTime? next,
    DateTime? end,
    String title = 'Bills',
    int amount = 5500,
    RecurrenceFrequency frequency = RecurrenceFrequency.month,
    int interval = 1,
  }) => RecurringRule(
    id: id,
    description: title,
    amount: amount,
    category: 'Other',
    accountId: 1,
    day: frequency == RecurrenceFrequency.week ? 7 : 1,
    nextDate: next ?? today,
    endDate: end,
    active: active,
    type: type,
    frequency: frequency,
    interval: interval,
  );
  Widget card(
    RecurringRule r, {
    Currency currency = Currency.eur,
    DateTime? pendingDate,
    ValueChanged<bool>? onChanged,
  }) => RecurringPaymentCard(
    rule: r,
    currency: currency,
    accountName: 'Euro account',
    today: today,
    categoryIcon: r.type == EntryType.income
        ? CategoryIcon.bank
        : CategoryIcon.receipt,
    pendingDate: pendingDate,
    onActiveChanged: onChanged ?? (_) {},
    onEdit: () {},
    onDelete: () {},
  );
  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final dark in [false, true]) {
    testWidgets(
      'recurring cards match reference in ${dark ? 'dark narrow large text' : 'light'}',
      (tester) async {
        tester.view.physicalSize = Size(dark ? 320 : 430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final expense = rule();
        final income = rule(
          id: 2,
          title: 'Rent income',
          type: EntryType.income,
          amount: 6600,
          frequency: RecurrenceFrequency.week,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(dark ? 320 : 430, 932),
                textScaler: TextScaler.linear(dark ? 1.8 : 1),
              ),
              child: RepaintBoundary(
                key: key,
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [card(expense), card(income)],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('TODAY'), findsNWidgets(2));
        expect(find.text('Due today!'), findsNWidgets(2));
        expect(find.text('Monthly · Day 1'), findsOneWidget);
        expect(find.text('Weekly · Sunday'), findsOneWidget);
        expect(find.byType(Switch), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          'recurring-reference-${dark ? 'dark-narrow' : 'light'}',
        );
      },
    );
  }
  testWidgets(
    'pending date outranks advanced next date; paused and ended labels are accurate',
    (tester) async {
      final future = DateTime(2027, 1, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                card(rule(next: future), pendingDate: DateTime(2026, 11, 9)),
                card(rule(id: 2, active: false, next: future)),
                card(rule(id: 3, next: future, end: today)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('ENDED'), findsOneWidget);
      expect(find.text('Overdue · 2026-11-09'), findsOneWidget);
      expect(find.text('Due today!'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'long foreign amounts wrap without shrinking and disabled switch cannot edit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edits = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 932),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RecurringPaymentCard(
                    rule: rule(
                      title: 'Apartment rent for the family home',
                      amount: 177200000,
                    ),
                    currency: Currency.iqd,
                    accountName: 'Foreign currency account',
                    today: today,
                    onEdit: () => edits++,
                    onDelete: null,
                    onActiveChanged: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(Currency.iqd.display(177200000)), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(edits, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
