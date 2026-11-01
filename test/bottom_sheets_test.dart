import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/app_sheet.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/category_picker.dart';
import 'package:moneva/core/presentation/entry_editor_sheet.dart';
import 'package:moneva/core/presentation/entry_type_picker.dart';
import 'package:moneva/screens/transaction_form.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/sheet_helpers.dart';
import 'helpers/wait_for_store.dart';

void main() {
  late LedgerStore store;
  final preview = GlobalKey();
  setUpAll(() async {
    sqfliteFfiInit();
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final item in {
      'PaxFoxRoboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(item.value).readAsBytes();
      await (FontLoader(
        item.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  setUp(() async {
    store = await LedgerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    await store.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 100000,
        asOf: DateTime(2025),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
  });
  tearDown(() async {
    store.dispose();
    await store.db.close();
  });

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          preview.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final shot = await boundary.toImage();
      final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
      await Directory('build/test-previews').create(recursive: true);
      await File('build/test-previews/sheet-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      shot.dispose();
    });
  }

  Future<void> launch(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showAppSheet<bool>(
                    context,
                    editor: true,
                    builder: (_) => TransactionForm(store: store),
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'combined category sheet cancels type changes and preserves draft input',
    (tester) async {
      await launch(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '12.34',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description / merchant'),
        'Draft',
      );
      await capture(tester, 'expense');
      await openCategoryPicker(tester);
      await capture(tester, 'expense-categories');
      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      await capture(tester, 'category-list-expense');
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      await capture(tester, 'category-list-income');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-type-income')));
      await capture(tester, 'income-categories');
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).type,
        EntryType.expense,
      );
      await openCategoryPicker(tester);
      await tester.tap(find.byKey(const ValueKey('category-type-income')));
      await chooseCategory(tester, 'Salary');
      expect(
        tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).type,
        EntryType.income,
      );
      expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Amount'))
            .controller!
            .text,
        '12.34',
      );
      await capture(tester, 'income');
      await tester.tap(
        find.byKey(ValueKey('account-card-${store.accounts.single.id}')),
      );
      await tester.tap(find.text('Save transaction'));
      await tester.runAsync(
        () => waitForStore(store, () => store.entries.isNotEmpty),
      );
      await tester.pumpAndSettle();
      expect(store.entries.single.type, EntryType.income);
      expect(store.entries.single.amount, 1234);
      expect(store.entries.single.description, 'Draft');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locked category context cannot switch to another financial type',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCategoryPicker(
                  context,
                  store: store,
                  type: EntryType.income,
                ),
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('category-type-expense')), findsNothing);
      expect(find.byTooltip('Transfer'), findsNothing);
      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Add income category'), findsOneWidget);
      expect(find.text('Income Category'), findsWidgets);
      expect(find.text('Expense Category'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add category'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('type-picker')))
            .enabled,
        isFalse,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'New income',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.categories.any((c) => c.name == 'New income'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Select Category'), findsOneWidget);
      await chooseCategory(tester, 'New income');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing selected category preserves its stable identity when sheet closes',
    (tester) async {
      CategorySelection? result;
      final original = store.categoryFor('Groceries', EntryType.expense)!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showCategoryPicker(
                    context,
                    store: store,
                    type: EntryType.expense,
                    selected: 'Groceries',
                  );
                },
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      expect(find.text('Categories'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit Groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Fresh groceries',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.categories.any((c) => c.name == 'Fresh groceries'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(result, (type: EntryType.expense, name: 'Fresh groceries'));
      expect(
        store.categoryFor('Fresh groceries', EntryType.expense)!.id,
        original.id,
      );
    },
  );

  testWidgets(
    'multi-select types copies draft and applies all selected types together',
    (tester) async {
      final selected = {EntryType.expense};
      Set<EntryType>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showEntryTypes(
                    context,
                    selected: selected,
                    multiple: true,
                  );
                },
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entry-type-income')));
      await tester.tap(find.byTooltip('Close').last);
      await tester.pumpAndSettle();
      expect(selected, {EntryType.expense});
      expect(result, isNull);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('entry-type-income')));
      await tester.tap(find.text('Apply types'));
      await tester.pumpAndSettle();
      expect(result, {EntryType.expense, EntryType.income});
    },
  );

  testWidgets('refund and transfer remain available from the combined picker', (
    tester,
  ) async {
    await launch(tester);
    await chooseEntryType(tester, 'refund');
    expect(
      tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).type,
      EntryType.refund,
    );
    await chooseEntryType(tester, 'transfer');
    expect(
      tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).type,
      EntryType.transfer,
    );
    expect(find.text('Destination account'), findsOneWidget);
    await openCategoryPicker(tester);
    await chooseCategory(tester, 'Groceries');
    expect(
      tester.widget<EntryEditorSheet>(find.byType(EntryEditorSheet)).type,
      EntryType.expense,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large category catalogs build lazily and can select the last item',
    (tester) async {
      await tester.runAsync(() async {
        final batch = store.db.batch();
        for (var i = 0; i < 250; i++) {
          batch.insert('categories', {
            'name': 'Stress ${i.toString().padLeft(3, '0')}',
            'kind': 'expense',
            'icon': 'general',
            'color': 0xff4956cc,
          });
        }
        await batch.commit(noResult: true);
        await store.refresh();
      });
      await launch(tester);
      await openCategoryPicker(tester);
      final grid = find.byType(GridView);
      expect(
        find
            .descendant(of: grid, matching: find.byType(InkWell))
            .evaluate()
            .length,
        lessThan(40),
      );
      expect(find.text('Stress 249'), findsNothing);
      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile).evaluate().length, lessThan(25));
      expect(find.text('Stress 249'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final scrolling = find.descendant(
        of: grid,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrolling).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Stress 249');
      expect(find.text('Stress 249'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dark large-text editor and category grid fit small phones and keyboard',
    (tester) async {
      await launch(tester, brightness: Brightness.dark, scale: 1.8);
      tester.view.physicalSize = const Size(320, 740);
      await tester.pumpAndSettle();
      await capture(tester, 'dark-large');
      await openCategoryPicker(tester);
      await capture(tester, 'dark-large-categories');
      await tester.tap(find.byTooltip('Edit categories'));
      await tester.pumpAndSettle();
      await capture(tester, 'category-list-dark-large');
      expect(find.byTooltip('Add expense category'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Groceries');
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Description / merchant'),
      );
      await capture(tester, 'keyboard');
      expect(
        tester.getBottomRight(find.text('Save transaction')).dy,
        lessThan(440),
      );
      expect(tester.takeException(), isNull);
      await openCategoryPicker(tester);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await chooseCategory(tester, 'Shopping');
      expect(find.byType(SelectionSheet), findsNothing);
      expect(find.text('Shopping'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
