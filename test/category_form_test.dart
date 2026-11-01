import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneva/core/data/ledger_store.dart';
import 'package:moneva/core/domain/category.dart';
import 'package:moneva/core/domain/ledger.dart';
import 'package:moneva/core/presentation/app_theme.dart';
import 'package:moneva/core/presentation/category_colors.dart';
import 'package:moneva/core/presentation/category_icons.dart';
import 'package:moneva/core/presentation/transaction_tile.dart';
import 'package:moneva/screens/categories_screen.dart';
import 'package:moneva/screens/category_form.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/wait_for_store.dart';

void main() {
  late LedgerStore store;
  final previewKey = GlobalKey();
  setUpAll(() async {
    sqfliteFfiInit();
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    for (final entry in {
      'PaxFoxRoboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'packages/font_awesome_flutter/FontAwesomeBrands': 'C:/Users/moham/AppData/Local/Pub/Cache/hosted/pub.dev/font_awesome_flutter-11.0.0/lib/fonts/Font-Awesome-7-Brands-Regular-400.otf',
      'packages/font_awesome_flutter/FontAwesomeSolid': 'C:/Users/moham/AppData/Local/Pub/Cache/hosted/pub.dev/font_awesome_flutter-11.0.0/lib/fonts/Font-Awesome-7-Free-Solid-900.otf',
    }.entries) {
      final bytes = await File(entry.value).readAsBytes();
      await (FontLoader(
        entry.key,
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

  Future<void> launch(
    WidgetTester tester, {
    LedgerCategory? category,
    CategoryKind kind = CategoryKind.expense,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => CategoryForm(
                      store: store,
                      kind: kind,
                      category: category,
                    ),
                  ),
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String query) async {
    final field = find.widgetWithText(TextField, 'Search icons');
    await tester.ensureVisible(field);
    await tester.enterText(field, query);
    await tester.pumpAndSettle();
  }

  test('category color and new icon persist; omitted color preserves value and rename cascades', () async {
    final grocery = store.categories.singleWhere((c) => c.name == 'Groceries');
    await store.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 100,
        currency: Currency.eur,
        date: DateTime(2026, 10, 31),
        description: 'Food',
        category: grocery.name,
        accountId: store.accounts.single.id,
      ),
    );
    await store.saveCategory(
      id: grocery.id,
      kind: grocery.kind,
      name: 'Food',
      icon: CategoryIcon.spotify,
      color: 0xff4956cc,
    );
    final loaded = LedgerStore(store.db);
    addTearDown(loaded.dispose);
    await loaded.refresh();
    final edited = loaded.categories.singleWhere((c) => c.id == grocery.id);
    expect(edited.icon, CategoryIcon.spotify);
    expect(edited.color, 0xff4956cc);
    expect(loaded.entries.single.category, 'Food');
    expect(loaded.colorFor(loaded.entries.single), 0xff4956cc);
    await store.saveCategory(id: grocery.id, kind: grocery.kind, name: 'Meals');
    expect(
      store.categories.singleWhere((c) => c.id == grocery.id).color,
      0xff4956cc,
    );
    await expectLater(
      store.saveCategory(
        id: grocery.id,
        kind: grocery.kind,
        name: 'Broken',
        color: 0x80556677,
      ),
      throwsArgumentError,
    );
    expect(store.entries.single.category, 'Meals');
    expect(store.entries.single.amount, 100);
  });

  test('v12 upgrade adds colors without losing categories, setup, entries or balances', () async {
    final directory = await Directory.systemTemp.createTemp(
      'paxfox_category_v12_',
    );
    final path = '${directory.path}/ledger.sqlite';
    final old = await LedgerStore.open(path: path, factory: databaseFactoryFfi);
    await old.completeSetup([
      Account(
        name: 'Cash',
        currency: Currency.eur,
        opening: 5000,
        asOf: DateTime(2026),
        kind: AccountKind.cash,
        includeOnAsOf: true,
      ),
    ]);
    await old.saveEntry(
      LedgerEntry(
        type: EntryType.expense,
        amount: 125,
        currency: Currency.eur,
        date: DateTime(2026, 10, 31),
        description: 'Migration test',
        category: 'Groceries',
        accountId: old.accounts.single.id,
      ),
    );
    final ids = old.categories.map((c) => c.id).toList();
    await old.db.execute('ALTER TABLE categories DROP COLUMN color');
    await old.db.setVersion(12);
    old.dispose();
    await old.db.close();
    final migrated = await LedgerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect(await migrated.db.getVersion(), 13);
      expect(migrated.categories.map((c) => c.id).toList(), ids);
      expect(migrated.categories.every((c) => c.color == null), isTrue);
      expect(migrated.entries.single.description, 'Migration test');
      expect(migrated.currentBalances.available, 4875);
      expect(migrated.setupCompleted, isTrue);
      expect(await migrated.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      migrated.dispose();
      await migrated.db.close();
      await directory.delete(recursive: true);
    }
  });

  testWidgets(
    'new category switches type, selects color and searchable brand icon, then saves',
    (tester) async {
      await launch(tester);
      await tester.tap(find.text('Save category'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a category name.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('category-kind-income')));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Streaming income',
      );
      await tester.tap(find.byKey(const ValueKey('category-color-indigo')));
      await search(tester, 'spotify');
      final icon = find.byKey(const ValueKey('pick-icon-spotify'));
      await tester.ensureVisible(icon);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.byType(CategoryForm), findsOneWidget);
      await tester.tap(find.text('Save category'));
      await tester.runAsync(
        () => waitForStore(
          store,
          () => store.categories.any((c) => c.name == 'Streaming income'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CategoryForm), findsNothing);
      final saved = store.categories.singleWhere(
        (c) => c.name == 'Streaming income',
      );
      expect(saved.kind, CategoryKind.income);
      expect(saved.color, 0xff4956cc);
      expect(saved.icon, CategoryIcon.spotify);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'edit keeps historical type; cancel discards draft and duplicate save remains retryable',
    (tester) async {
      final grocery = store.categories.singleWhere(
        (c) => c.name == 'Groceries',
      );
      await launch(tester, category: grocery);
      await tester.tap(find.byKey(const ValueKey('category-kind-income')));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Dining out',
      );
      await tester.tap(find.text('Save category'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsOneWidget);
      expect(find.byType(CategoryForm), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Category name'),
        'Cancelled draft',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        store.categories.singleWhere((c) => c.id == grocery.id).name,
        'Groceries',
      );
      expect(
        store.categories.singleWhere((c) => c.id == grocery.id).kind,
        CategoryKind.expense,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected category color reaches lists and transactions', (
    tester,
  ) async {
    await tester.runAsync(
      () => store.saveCategory(
        kind: CategoryKind.expense,
        name: 'Colored',
        icon: CategoryIcon.coffee,
        color: 0xff4956cc,
      ),
    );
    await tester.pumpWidget(MaterialApp(home: CategoriesScreen(store: store)));
    await tester.pumpAndSettle();
    final row = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'Colored'),
    );
    expect(
      (row.leading! as CircleAvatar).backgroundColor,
      const Color(0xff4956cc),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionTile(
            entry: LedgerEntry(
              type: EntryType.expense,
              amount: 100,
              currency: Currency.eur,
              date: DateTime(2026),
              description: 'Color test',
              category: 'Colored',
            ),
            categoryColor: const Color(0xff4956cc),
            categoryIcon: CategoryIcon.coffee,
            onTap: () {},
            onLongPress: () {},
          ),
        ),
      ),
    );
    final badge = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('transaction-category-badge')),
    );
    expect((badge.decoration as BoxDecoration).color, const Color(0xff4956cc));
  });

  testWidgets(
    'phone editor previews include color palette, grouped icons, dark and large text',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await launch(tester);
      await capture(tester, 'category-editor-light');
      await search(tester, 'brands');
      await tester.ensureVisible(
        find.byKey(const ValueKey('pick-icon-youtube')),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'category-icons-brands');
      await search(tester, 'no matching icon');
      expect(find.text('No matching icons.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear icon search'));
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      scroll.position.jumpTo(0);
      tester.binding.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.binding.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'category-editor-dark');
      tester.view.physicalSize = const Size(320, 740);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );
      await tester.pumpAndSettle();
      await capture(tester, 'category-editor-large-text');
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.text('Save category')).dy,
        lessThan(740),
      );
      expect(categoryColors.length, 21);
      expect(
        categoryIconData(CategoryIcon.spotify).fontPackage,
        'font_awesome_flutter',
      );
    },
  );
}
