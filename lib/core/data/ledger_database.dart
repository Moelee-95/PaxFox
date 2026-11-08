import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/category.dart';

class LedgerDatabase {
  static Future<Database> open({String? path, DatabaseFactory? factory}) async {
    if (factory == null && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      factory = databaseFactoryFfi;
    }
    final location =
        path ??
        p.join((await getApplicationSupportDirectory()).path, 'moneva.sqlite');
    final db = await (factory ?? databaseFactorySqflitePlugin).openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 18,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          }
          if (oldVersion < 3) {
            await _createCategories(db);
          }
          if (oldVersion < 4) {
            await _upgradeAccounts(db);
          }
          if (oldVersion < 5) {
            await _addOverdraftPolicy(db);
          }
          if (oldVersion < 6) {
            await _createRecurring(db);
          }
          if (oldVersion < 7) {
            await _addCategoryIcons(db);
          }
          if (oldVersion < 8) {
            await _addRecurringTypes(db);
          }
          if (oldVersion < 9) {
            await _createReceipts(db);
          }
          if (oldVersion < 10) {
            await _createInvoiceBatches(db);
          }
          if (oldVersion < 11) {
            await _addRecurringClassification(db);
          }
          if (oldVersion < 12) {
            await _upgradeCurrencyAndDebts(db);
          }
          if (oldVersion < 13) {
            await _addCategoryColors(db);
          }
          if (oldVersion < 14) await _addForeignCurrencyAccounts(db);
          if (oldVersion < 15) await _addRecurringSchedules(db);
          if (oldVersion < 16) await _addDebtWorkflow(db);
          if (oldVersion < 17) await _addNativeDebts(db);
          if (oldVersion < 18) await _addDebtDeadlines(db);
        },
        // Table rebuild in v12 preserves dependent receipt/history links.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = OFF'),
        onOpen: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, currency TEXT NOT NULL CHECK(currency IN ('eur','iqd')), opening INTEGER NOT NULL, as_of TEXT NOT NULL, available INTEGER NOT NULL CHECK(available IN (0,1)))",
          );
          await db.execute(
            "CREATE TABLE transactions (id INTEGER PRIMARY KEY, type TEXT NOT NULL CHECK(type IN ('expense','income','refund','transfer')), amount INTEGER NOT NULL CHECK(amount > 0 AND amount <= 9000000000000000), currency TEXT NOT NULL CHECK(currency IN ('eur','iqd')), date TEXT NOT NULL, description TEXT NOT NULL, category TEXT NOT NULL, account_id INTEGER REFERENCES accounts(id), destination_id INTEGER REFERENCES accounts(id), notes TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, CHECK(type != 'transfer' OR (account_id IS NOT NULL AND destination_id IS NOT NULL AND account_id != destination_id)))",
          );
          for (final column in [
            'date',
            'category',
            'account_id',
            'destination_id',
          ]) {
            await db.execute(
              'CREATE INDEX transactions_$column ON transactions($column)',
            );
          }
          await _createCategories(db);
          await _upgradeAccounts(db);
          await _addOverdraftPolicy(db);
          await _createRecurring(db);
          await _addCategoryIcons(db);
          await _addRecurringTypes(db);
          await _createReceipts(db);
          await _createInvoiceBatches(db);
          await _addRecurringClassification(db);
          await _upgradeCurrencyAndDebts(db);
          await _addCategoryColors(db);
          await _addForeignCurrencyAccounts(db);
          await _addRecurringSchedules(db);
          await _addDebtWorkflow(db);
          await _addNativeDebts(db);
          await _addDebtDeadlines(db);
        },
      ),
    );
    return db;
  }

  static Future<void> _addDebtDeadlines(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(debts)');
    for (final name in ['deadline', 'deadline_acknowledged']) {
      if (!columns.any((c) => c['name'] == name)) {
        await db.execute('ALTER TABLE debts ADD COLUMN $name TEXT');
      }
    }
  }

  static Future<void> _addNativeDebts(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(debt_payments)');
    if (!columns.any((c) => c['name'] == 'details')) {
      await db.execute('ALTER TABLE debt_payments ADD COLUMN details TEXT');
    }
    if (!columns.any((c) => c['name'] == 'fee_transaction_id')) {
      await db.execute(
        'ALTER TABLE debt_payments ADD COLUMN fee_transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL',
      );
    }
    await db.execute('DROP TRIGGER IF EXISTS debt_payment_validate');
    await db.execute("""CREATE TRIGGER debt_payment_validate BEFORE INSERT ON debt_payments BEGIN
      SELECT CASE WHEN NEW.debt_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM debts d JOIN transactions t ON t.id = NEW.transaction_id
        WHERE d.id = NEW.debt_id AND d.amount >= NEW.amount
          AND (NEW.details IS NOT NULL OR (t.amount = NEW.amount AND t.currency = d.currency))
          AND lower(t.category) = 'debt'
          AND t.type = CASE WHEN d.is_receivable = 1 THEN 'income' ELSE 'expense' END
      ) THEN RAISE(ABORT, 'Invalid debt settlement or amount exceeds remaining balance.') END;
    END""");
    await db.execute('DROP TRIGGER IF EXISTS debt_transaction_change');
    await db.execute("""CREATE TRIGGER debt_transaction_change AFTER UPDATE OF amount,type,category,currency ON transactions
      WHEN EXISTS(SELECT 1 FROM debt_payments WHERE transaction_id = NEW.id AND debt_id IS NOT NULL) BEGIN
      SELECT CASE WHEN NOT EXISTS (
        SELECT 1 FROM debt_payments p JOIN debts d ON d.id = p.debt_id WHERE p.transaction_id = NEW.id
          AND (p.details IS NOT NULL OR NEW.currency = d.currency) AND lower(NEW.category) = 'debt'
          AND NEW.type = CASE WHEN d.is_receivable = 1 THEN 'income' ELSE 'expense' END
      ) THEN RAISE(ABORT, 'Keep the Debt category and settlement type for this payment.') END;
      UPDATE debt_payments SET amount = NEW.amount WHERE transaction_id = NEW.id AND details IS NULL AND amount != NEW.amount;
    END""");
    // Known user-entered bank rates are suitable initial defaults; never invent market rates.
    final rates = <String, String>{};
    for (final row in await db.query('accounts')) {
      final base = row['base_currency'] ?? row['currency'];
      if (base != row['currency']) {
        rates.putIfAbsent(
          '${base}_${row['currency']}',
          () => row['exchange_rate'] as String? ?? '1',
        );
      }
    }
    await db.insert('settings', {
      'key': 'currency_exchange_rates',
      'value': jsonEncode(rates),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static Future<void> _addDebtWorkflow(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(debts)');
    if (!columns.any((c) => c['name'] == 'is_receivable')) {
      await db.execute(
        'ALTER TABLE debts ADD COLUMN is_receivable INTEGER NOT NULL DEFAULT 0 CHECK(is_receivable IN (0,1))',
      );
    }
    for (final kind in ['expense', 'income']) {
      await db.execute(
        "INSERT OR IGNORE INTO categories(kind,name,icon,color) VALUES (?, 'Debt', 'loan', 4286279167)",
        [kind],
      );
    }
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS protect_debt_category_delete BEFORE DELETE ON categories WHEN lower(OLD.name) = 'debt' BEGIN SELECT RAISE(ABORT, 'The built-in Debt category cannot be deleted.'); END",
    );
    await db.execute(
      "CREATE TRIGGER IF NOT EXISTS protect_debt_category_name BEFORE UPDATE OF name,kind ON categories WHEN lower(OLD.name) = 'debt' AND (NEW.name != OLD.name OR NEW.kind != OLD.kind) BEGIN SELECT RAISE(ABORT, 'The built-in Debt category cannot be renamed.'); END",
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS debt_payments(transaction_id INTEGER PRIMARY KEY REFERENCES transactions(id) ON DELETE CASCADE, debt_id INTEGER REFERENCES debts(id) ON DELETE SET NULL, amount INTEGER NOT NULL CHECK(amount > 0))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recurring_debts(occurrence_id INTEGER PRIMARY KEY REFERENCES recurring_occurrences(id), debt_id INTEGER REFERENCES debts(id) ON DELETE SET NULL)',
    );
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_payment_validate BEFORE INSERT ON debt_payments BEGIN
      SELECT CASE WHEN NEW.debt_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM debts d JOIN transactions t ON t.id = NEW.transaction_id
        WHERE d.id = NEW.debt_id AND d.amount >= NEW.amount AND t.amount = NEW.amount
          AND t.currency = d.currency AND lower(t.category) = 'debt'
          AND t.type = CASE WHEN d.is_receivable = 1 THEN 'income' ELSE 'expense' END
      ) THEN RAISE(ABORT, 'Invalid debt settlement or amount exceeds remaining balance.') END;
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_payment_insert AFTER INSERT ON debt_payments BEGIN
      UPDATE debts SET amount = amount - NEW.amount, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = NEW.debt_id;
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_payment_change_validate BEFORE UPDATE OF amount ON debt_payments WHEN NEW.debt_id IS NOT NULL BEGIN
      SELECT CASE WHEN NEW.amount > (SELECT amount FROM debts WHERE id = NEW.debt_id) + OLD.amount THEN RAISE(ABORT, 'Amount exceeds remaining debt.') END;
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_payment_change AFTER UPDATE OF amount ON debt_payments WHEN NEW.debt_id IS NOT NULL BEGIN
      UPDATE debts SET amount = amount + OLD.amount - NEW.amount, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = NEW.debt_id;
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_payment_delete AFTER DELETE ON debt_payments WHEN OLD.debt_id IS NOT NULL BEGIN
      UPDATE debts SET amount = amount + OLD.amount, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id = OLD.debt_id;
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS debt_transaction_change AFTER UPDATE OF amount,type,category,currency ON transactions
      WHEN EXISTS(SELECT 1 FROM debt_payments WHERE transaction_id = NEW.id AND debt_id IS NOT NULL) BEGIN
      SELECT CASE WHEN NOT EXISTS (
        SELECT 1 FROM debt_payments p JOIN debts d ON d.id = p.debt_id WHERE p.transaction_id = NEW.id
          AND NEW.currency = d.currency AND lower(NEW.category) = 'debt'
          AND NEW.type = CASE WHEN d.is_receivable = 1 THEN 'income' ELSE 'expense' END
      ) THEN RAISE(ABORT, 'Keep the Debt category and settlement type for this payment.') END;
      UPDATE debt_payments SET amount = NEW.amount WHERE transaction_id = NEW.id AND amount != NEW.amount;
    END""");
  }

  static Future<void> _addRecurringSchedules(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS recurring_reminders (id INTEGER PRIMARY KEY AUTOINCREMENT, rule_id INTEGER NOT NULL REFERENCES recurring_rules(id), due_date TEXT NOT NULL, UNIQUE(rule_id, due_date))',
    );
    for (final column in {
      'frequency': "TEXT NOT NULL DEFAULT 'month'",
      'month': 'INTEGER NOT NULL DEFAULT 1',
      'automatic': 'INTEGER NOT NULL DEFAULT 1',
      'reminder_minutes': 'INTEGER NOT NULL DEFAULT 540',
    }.entries) {
      final columns = await db.rawQuery('PRAGMA table_info(recurring_rules)');
      if (!columns.any((row) => row['name'] == column.key)) {
        await db.execute(
          'ALTER TABLE recurring_rules ADD COLUMN ${column.key} ${column.value}',
        );
      }
    }
    final columns = await db.rawQuery(
      'PRAGMA table_info(recurring_occurrences)',
    );
    if (!columns.any((row) => row['name'] == 'manual')) {
      await db.execute(
        'ALTER TABLE recurring_occurrences ADD COLUMN manual INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  static Future<void> _addForeignCurrencyAccounts(DatabaseExecutor db) async {
    Future<void> add(String table, String name, String definition) async {
      final columns = await db.rawQuery('PRAGMA table_info($table)');
      if (!columns.any((row) => row['name'] == name)) {
        await db.execute('ALTER TABLE $table ADD COLUMN $name $definition');
      }
    }

    await add('accounts', 'base_currency', 'TEXT');
    await add('accounts', 'exchange_rate', "TEXT NOT NULL DEFAULT '1'");
    await db.execute(
      'UPDATE accounts SET base_currency = currency WHERE base_currency IS NULL',
    );
    for (final column in ['account_amount', 'destination_amount']) {
      await add(
        'transactions',
        column,
        'INTEGER CHECK($column IS NULL OR ($column > 0 AND $column <= 9000000000000000))',
      );
    }
    await add('transactions', 'fx_snapshot', 'TEXT');
    for (final table in ['recurring_rules', 'recurring_occurrences']) {
      await add(table, 'currency', 'TEXT');
    }
  }

  static Future<void> _addCategoryColors(DatabaseExecutor db) => db.execute(
    'ALTER TABLE categories ADD COLUMN color INTEGER CHECK(color IS NULL OR color BETWEEN 4278190080 AND 4294967295)',
  );

  static Future<void> _upgradeCurrencyAndDebts(DatabaseExecutor db) async {
    for (final table in ['accounts', 'transactions']) {
      final sql =
          (await db.rawQuery(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                [table],
              )).single['sql']
              as String;
      if (sql.contains("'usd'")) continue;
      final widened = sql
          .replaceFirst(
            RegExp('CREATE TABLE ["`]?$table["`]?'),
            'CREATE TABLE ${table}_v12',
          )
          .replaceAll("'eur','iqd'", "'eur','iqd','usd','gbp'");
      await db.execute(widened);
      await db.execute('INSERT INTO ${table}_v12 SELECT * FROM $table');
      await db.execute('DROP TABLE $table');
      await db.execute('ALTER TABLE ${table}_v12 RENAME TO $table');
    }
    for (final column in ['date', 'category', 'account_id', 'destination_id']) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS transactions_$column ON transactions($column)',
      );
    }
    final columns = await db.rawQuery('PRAGMA table_info(receipt_items)');
    if (!columns.any((row) => row['name'] == 'item_date')) {
      await db.execute('ALTER TABLE receipt_items ADD COLUMN item_date TEXT');
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS debts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount >= 0 AND amount <= 9000000000000000), currency TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
    );
    final violations = await db.rawQuery('PRAGMA foreign_key_check');
    if (violations.isNotEmpty) {
      throw StateError('Migration contains invalid links.');
    }
  }

  static Future<void> _addOverdraftPolicy(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE accounts ADD COLUMN allow_overdraft INTEGER NOT NULL DEFAULT 0 CHECK(allow_overdraft IN (0,1))',
    );
    // Existing bank accounts previously allowed overdrafts; preserve their policy.
    await db.execute(
      "UPDATE accounts SET allow_overdraft = 1 WHERE kind = 'bank'",
    );
  }

  static Future<void> _addRecurringClassification(DatabaseExecutor db) async {
    for (final column in ['is_asset', 'is_liability']) {
      await db.execute(
        'ALTER TABLE recurring_rules ADD COLUMN $column INTEGER NOT NULL DEFAULT 0 CHECK($column IN (0,1))',
      );
    }
  }

  static Future<void> _upgradeAccounts(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE accounts ADD COLUMN kind TEXT NOT NULL DEFAULT 'bank' CHECK(kind IN ('cash','bank'))",
    );
    await db.execute(
      'ALTER TABLE accounts ADD COLUMN include_on_as_of INTEGER NOT NULL DEFAULT 0 CHECK(include_on_as_of IN (0,1))',
    );
  }

  static Future<void> _createCategories(DatabaseExecutor db) async {
    await db.execute(
      "CREATE TABLE categories (id INTEGER PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('expense','income')), name TEXT NOT NULL CHECK(length(trim(name)) > 0), UNIQUE(kind, name COLLATE NOCASE))",
    );
    // Preserve every existing label exactly, before adding suggestions.
    final existing = await db.rawQuery(
      "SELECT DISTINCT category AS name, CASE WHEN type = 'income' THEN 'income' ELSE 'expense' END AS kind FROM transactions WHERE type != 'transfer'",
    );
    for (final row in existing) {
      await db.insert(
        'categories',
        row,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    for (final kind in CategoryKind.values) {
      final names = kind == CategoryKind.expense
          ? [
              'Other',
              'Groceries',
              'Dining out',
              'Transport',
              'Rent & utilities',
              'Health',
              'Shopping',
              'Entertainment',
              'Education',
              'Insurance',
              'Subscriptions',
              'Travel',
            ]
          : [
              'Other',
              'Salary',
              'Freelance',
              'Rental income',
              'Investment income',
              'Gifts',
            ];
      for (final name in names) {
        await db.insert('categories', {
          'kind': kind.name,
          'name': name,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
  }

  static Future<void> _addCategoryIcons(DatabaseExecutor db) async {
    await db.execute(
      "ALTER TABLE categories ADD COLUMN icon TEXT NOT NULL DEFAULT 'general'",
    );
    const defaults = <String, CategoryIcon>{
      'Groceries': CategoryIcon.groceries,
      'Dining out': CategoryIcon.dining,
      'Transport': CategoryIcon.transport,
      'Rent & utilities': CategoryIcon.home,
      'Health': CategoryIcon.health,
      'Shopping': CategoryIcon.shopping,
      'Entertainment': CategoryIcon.entertainment,
      'Education': CategoryIcon.education,
      'Insurance': CategoryIcon.insurance,
      'Subscriptions': CategoryIcon.subscriptions,
      'Travel': CategoryIcon.travel,
      'Salary': CategoryIcon.salary,
      'Freelance': CategoryIcon.freelance,
      'Rental income': CategoryIcon.home,
      'Investment income': CategoryIcon.investments,
      'Gifts': CategoryIcon.gifts,
    };
    for (final entry in defaults.entries) {
      await db.update(
        'categories',
        {'icon': entry.value.name},
        where: 'name = ?',
        whereArgs: [entry.key],
      );
    }
  }

  static Future<void> _addRecurringTypes(DatabaseExecutor db) async {
    for (final table in ['recurring_rules', 'recurring_occurrences']) {
      await db.execute(
        "ALTER TABLE $table ADD COLUMN type TEXT NOT NULL DEFAULT 'expense' CHECK(type IN ('expense','income'))",
      );
    }
  }

  static Future<void> _createRecurring(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE recurring_rules (id INTEGER PRIMARY KEY, description TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0), category TEXT NOT NULL, account_id INTEGER NOT NULL REFERENCES accounts(id), day INTEGER NOT NULL CHECK(day BETWEEN 1 AND 31), interval INTEGER NOT NULL CHECK(interval BETWEEN 1 AND 120), next_date TEXT NOT NULL, end_date TEXT, active INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0)',
    );
    await db.execute(
      "CREATE TABLE recurring_occurrences (id INTEGER PRIMARY KEY, rule_id INTEGER NOT NULL REFERENCES recurring_rules(id), scheduled_date TEXT NOT NULL, description TEXT NOT NULL, amount INTEGER NOT NULL, category TEXT NOT NULL, account_id INTEGER NOT NULL REFERENCES accounts(id), status TEXT NOT NULL CHECK(status IN ('posted','failed','skipped')), error TEXT, transaction_id INTEGER REFERENCES transactions(id) ON DELETE SET NULL, UNIQUE(rule_id, scheduled_date))",
    );
    await db.execute(
      'CREATE INDEX recurring_due ON recurring_rules(active, archived, next_date)',
    );
  }

  static Future<void> _createReceipts(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE receipts (id INTEGER PRIMARY KEY, transaction_id INTEGER NOT NULL UNIQUE REFERENCES transactions(id) ON DELETE CASCADE, total INTEGER NOT NULL, draft TEXT NOT NULL, image_paths TEXT NOT NULL, raw_response TEXT NOT NULL, scanned_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE receipt_items (id INTEGER PRIMARY KEY, transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE, description TEXT NOT NULL, quantity TEXT NOT NULL, unit_price INTEGER, total INTEGER NOT NULL, category TEXT NOT NULL, edited INTEGER NOT NULL, position INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX receipt_items_transaction ON receipt_items(transaction_id)',
    );
  }

  static Future<void> _createInvoiceBatches(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE scanned_invoices (id INTEGER PRIMARY KEY, draft TEXT NOT NULL, image_paths TEXT NOT NULL, raw_response TEXT NOT NULL, created_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE scanned_invoice_entries (transaction_id INTEGER PRIMARY KEY REFERENCES transactions(id) ON DELETE CASCADE, batch_id INTEGER NOT NULL REFERENCES scanned_invoices(id) ON DELETE CASCADE)',
    );
    await db.execute(
      'CREATE INDEX scanned_invoice_batch ON scanned_invoice_entries(batch_id)',
    );
  }
}
