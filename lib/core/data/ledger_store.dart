import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/receipts/invoice.dart';
import '../../features/receipts/invoice_images.dart';
import '../domain/category.dart';
import '../domain/ledger.dart';
import '../domain/ledger_queries.dart';
import '../domain/recurring.dart';
import 'ledger_database.dart';
import 'transaction_csv.dart';

typedef _SnapshotInput = ({
  List<Map<String, Object?>> rows,
  List<Account> accounts,
  DateTime today,
});

({LedgerIndex ledger, AccountBalances balances}) _prepareLedger(
  _SnapshotInput input,
) {
  final ledger = LedgerIndex.prepared(input.rows.map(LedgerEntry.fromMap));
  return (
    ledger: ledger,
    balances: AccountBalances(input.accounts, ledger.entries, input.today),
  );
}

class LedgerStore extends ChangeNotifier {
  LedgerStore(this.db);
  final Database db;
  LedgerIndex _ledger = LedgerIndex(const []);
  List<LedgerEntry> get entries => _ledger.entries;
  List<Account> _accounts = const [];
  List<Account> get accounts => _accounts;
  Set<int> _deletableBankIds = const {};
  Set<int> _receiptTransactionIds = const {};
  Set<int> get receiptTransactionIds => _receiptTransactionIds;
  Set<int> _scannedInvoiceTransactionIds = const {};
  Set<int> get scannedInvoiceTransactionIds => _scannedInvoiceTransactionIds;
  List<LedgerCategory> _categories = const [];
  List<LedgerCategory> get categories => _categories;
  Map<CategoryKind, List<LedgerCategory>> _categoriesByKind = const {};
  Map<(CategoryKind, String), LedgerCategory> _categoriesByName = const {};

  List<LedgerCategory> categoriesFor(EntryType type) =>
      _categoriesByKind[categoryKind(type)] ?? const [];

  LedgerCategory? categoryFor(String name, EntryType type) =>
      _categoriesByName[(categoryKind(type), name)];

  CategoryIcon iconFor(LedgerEntry entry) =>
      categoryFor(entry.category, entry.type)?.icon ?? CategoryIcon.general;

  int? colorFor(LedgerEntry entry) =>
      categoryFor(entry.category, entry.type)?.color;

  MonthlyLedger monthSummary(DateTime month) => _ledger.forMonth(month);

  List<LedgerEntry> searchEntries({String query = '', EntryType? type}) =>
      _ledger.search(query: query, type: type);

  AccountBalances? _balances;
  DateTime? _balanceDate;
  AccountBalances get currentBalances {
    final today = dateOnly(DateTime.now());
    if (_balances == null || _balanceDate != today) {
      _balances = AccountBalances(accounts, entries, today);
      _balanceDate = today;
    }
    return _balances!;
  }

  bool hasLegacyCurrencyData = false;
  bool setupCompleted = false;
  Currency _currency = Currency.eur;
  Currency get currency => _currency;
  List<Debt> _debts = const [];
  List<Debt> get debts => _debts;
  int get totalDebt => debts.fold(0, (sum, debt) => sum + debt.amount);
  int get netWealth => currentBalances.wealth - totalDebt;
  int invoiceTimeoutSeconds = 180;
  String _profileName = '';
  String get profileName => _profileName;
  String _profileEmail = '';
  String get profileEmail => _profileEmail;
  bool _snapshotNeedsRefresh = false;
  bool get snapshotNeedsRefresh => _snapshotNeedsRefresh;
  // Separate from snapshot notifications: a spinner must not rebuild pages.
  final refreshing = ValueNotifier(false);
  int _refreshes = 0;
  int _refreshGeneration = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    refreshing.dispose();
    super.dispose();
  }

  Future<void> _refreshAfterWrite() async {
    try {
      await refresh();
    } catch (_) {
      // The commit succeeded. Retrying the write could duplicate a payment.
      _snapshotNeedsRefresh = true;
      notifyListeners();
    }
  }

  Future<void> saveInvoiceTimeout(int seconds) async {
    if (seconds < 30 || seconds > 900) {
      throw ArgumentError('Use a timeout between 30 and 900 seconds.');
    }
    await db.insert('settings', {
      'key': 'invoice_timeout_seconds',
      'value': '$seconds',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _refreshAfterWrite();
  }

  Future<void> saveProfile({
    required String name,
    required String email,
  }) async {
    final trimmedName = name.trim();
    final trimmedEmail = email.trim();
    if (trimmedName.isEmpty || trimmedName.length > 80) {
      throw ArgumentError('Enter a name with up to 80 characters.');
    }
    if (trimmedEmail.length > 254 ||
        (trimmedEmail.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmedEmail))) {
      throw ArgumentError('Enter a valid email address or leave it empty.');
    }
    await db.transaction((txn) async {
      for (final setting in {
        'profile_name': trimmedName,
        'profile_email': trimmedEmail,
      }.entries) {
        await txn.insert('settings', {
          'key': setting.key,
          'value': setting.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await _refreshAfterWrite();
  }

  List<RecurringRule> _recurringRules = const [];
  List<RecurringRule> get recurringRules => _recurringRules;
  List<RecurringOccurrence> _recurringOccurrences = const [];
  List<RecurringOccurrence> get recurringOccurrences => _recurringOccurrences;

  static Future<LedgerStore> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final db = await LedgerDatabase.open(path: path, factory: factory);
    final store = LedgerStore(db);
    try {
      await store.refresh();
      return store;
    } catch (_) {
      store.dispose();
      await db.close();
      rethrow;
    }
  }

  Future<void> refresh() async {
    final generation = ++_refreshGeneration;
    _refreshes++;
    if (!_disposed) refreshing.value = true;
    try {
      await _readSnapshot(generation);
    } finally {
      _refreshes--;
      if (!_disposed) refreshing.value = _refreshes > 0;
    }
  }

  Future<void> _readSnapshot(int generation) async {
    final snapshot = await db.transaction((txn) async {
      final settingRows = await txn.query('settings');
      final settingsByKey = {
        for (final row in settingRows)
          row['key'] as String: row['value'] as String,
      };
      final activeCurrency = Currency.values.byName(
        settingsByKey['app_currency'] ?? 'eur',
      );
      final debtList = (await txn.query(
        'debts',
        where: 'currency = ?',
        whereArgs: [activeCurrency.name],
        orderBy: 'name',
      )).map(Debt.fromMap).toList();
      final savedTimeout = int.tryParse(
        settingsByKey['invoice_timeout_seconds'] ?? '',
      );
      final timeout =
          savedTimeout != null && savedTimeout >= 30 && savedTimeout <= 900
          ? savedTimeout
          : 180;
      final receiptIds = (await txn.query(
        'receipts',
        columns: ['transaction_id'],
      )).map((r) => r['transaction_id'] as int).toSet();
      final scannedIds = (await txn.query(
        'scanned_invoice_entries',
        columns: ['transaction_id'],
      )).map((r) => r['transaction_id'] as int).toSet();
      final rules = (await txn.query(
        'recurring_rules',
        where: 'archived = 0',
        orderBy: 'next_date',
      )).map(RecurringRule.fromMap).toList();
      final occurrences = (await txn.query(
        'recurring_occurrences',
        orderBy: 'scheduled_date DESC, id DESC',
      )).map(RecurringOccurrence.fromMap).toList();
      final setup = settingsByKey['setup_completed'] == 'true';
      final categoryList = (await txn.query(
        'categories',
        orderBy: 'name COLLATE NOCASE',
      )).map(LedgerCategory.fromMap).toList();
      final legacy =
          (await txn.query(
            'transactions',
            columns: ['id'],
            where: 'currency != ?',
            whereArgs: [activeCurrency.name],
            limit: 1,
          )).isNotEmpty ||
          (await txn.query(
            'accounts',
            columns: ['id'],
            where: 'currency != ?',
            whereArgs: [activeCurrency.name],
            limit: 1,
          )).isNotEmpty;
      final entryList = await txn.query(
        'transactions',
        where: 'currency = ?',
        whereArgs: [activeCurrency.name],
        orderBy: 'date DESC, id DESC',
      );
      final accountList = (await txn.query(
        'accounts',
        where: 'currency = ?',
        whereArgs: [activeCurrency.name],
        orderBy: 'name',
      )).map(Account.fromMap).toList();
      final deletableBankIds = (await txn.rawQuery(
        "SELECT a.id FROM accounts a WHERE a.kind = 'bank' "
        'AND NOT EXISTS (SELECT 1 FROM transactions t WHERE t.account_id = a.id OR t.destination_id = a.id) '
        'AND NOT EXISTS (SELECT 1 FROM recurring_rules r WHERE r.account_id = a.id) '
        'AND NOT EXISTS (SELECT 1 FROM recurring_occurrences o WHERE o.account_id = a.id)',
      )).map((row) => row['id'] as int).toSet();
      return (
        profileName: settingsByKey['profile_name'] ?? '',
        profileEmail: settingsByKey['profile_email'] ?? '',
        deletableBankIds: deletableBankIds,
        currency: activeCurrency,
        debts: debtList,
        timeout: timeout,
        receiptIds: receiptIds,
        scannedIds: scannedIds,
        rules: rules,
        occurrences: occurrences,
        setup: setup,
        categories: categoryList,
        legacy: legacy,
        entries: entryList,
        accounts: accountList,
      );
    });
    // Decode transactions, index months and prepare reports away from the UI
    // for large ledgers. Small snapshots avoid isolate startup overhead.
    final today = dateOnly(DateTime.now());
    final input = (
      rows: snapshot.entries,
      accounts: snapshot.accounts,
      today: today,
    );
    final prepared = snapshot.entries.length >= 1000
        ? await compute(_prepareLedger, input)
        : _prepareLedger(input);
    if (_disposed || generation != _refreshGeneration) return;
    _currency = snapshot.currency;
    _profileName = snapshot.profileName;
    _profileEmail = snapshot.profileEmail;
    _debts = List.unmodifiable(snapshot.debts);
    invoiceTimeoutSeconds = snapshot.timeout;
    _receiptTransactionIds = Set.unmodifiable(snapshot.receiptIds);
    _scannedInvoiceTransactionIds = Set.unmodifiable(snapshot.scannedIds);
    _recurringRules = List.unmodifiable(snapshot.rules);
    _recurringOccurrences = List.unmodifiable(snapshot.occurrences);
    setupCompleted = snapshot.setup;
    _categories = List.unmodifiable(snapshot.categories);
    _categoriesByKind = {
      for (final kind in CategoryKind.values)
        kind: List.unmodifiable(categories.where((c) => c.kind == kind)),
    };
    _categoriesByName = {
      for (final category in categories)
        (category.kind, category.name): category,
    };
    hasLegacyCurrencyData = snapshot.legacy;
    _ledger = prepared.ledger;
    _accounts = List.unmodifiable(snapshot.accounts);
    _deletableBankIds = Set.unmodifiable(snapshot.deletableBankIds);
    _balances = prepared.balances;
    _balanceDate = today;
    _snapshotNeedsRefresh = false;
    notifyListeners();
  }

  Future<void> saveEntry(LedgerEntry entry) async {
    await db.transaction((txn) async {
      await _writeEntry(txn, entry);
      if (entry.id != null &&
          (await txn.query(
            'scanned_invoice_entries',
            where: 'transaction_id = ?',
            whereArgs: [entry.id],
          )).isNotEmpty) {
        await txn.update(
          'receipt_items',
          {
            'description': entry.description,
            'item_date': dayKey(entry.date),
            'total': entry.type == EntryType.refund
                ? -entry.amount
                : entry.amount,
            'category': entry.category,
            'edited': 1,
          },
          where: 'transaction_id = ?',
          whereArgs: [entry.id],
        );
      }
    });
    await _refreshAfterWrite();
  }

  /// Imports the whole file atomically, including any new categories.
  /// Matching existing rows are consumed as a multiset: repeated purchases
  /// inside a file remain repeated purchases rather than being collapsed.
  Future<({int imported, int skipped})> importCsv(
    List<CsvTransactionRow> rows, {
    bool skipExisting = true,
  }) async {
    if (rows.isEmpty || rows.length > TransactionCsv.maxRows) {
      throw ArgumentError('Choose between 1 and 5,000 transactions.');
    }
    var imported = 0;
    var skipped = 0;
    await db.transaction((txn) async {
      String signature(LedgerEntry e) => jsonEncode(e.toMap());
      final existing = <String, int>{};
      if (skipExisting) {
        for (final record in await txn.query('transactions')) {
          final key = signature(LedgerEntry.fromMap(record));
          existing[key] = (existing[key] ?? 0) + 1;
        }
      }
      final categories = (await txn.query('categories'))
          .map(LedgerCategory.fromMap)
          .toList();
      final affectedRows = <int, int>{};
      final ordered = [...rows]
        ..sort((a, b) {
          final date = a.entry.date.compareTo(b.entry.date);
          return date != 0 ? date : a.number.compareTo(b.number);
        });
      for (final row in ordered) {
        try {
          final source = row.entry;
          if (source.id != null) {
            throw ArgumentError('CSV imports create new transactions.');
          }
          var categoryName = 'Transfer';
          if (source.type != EntryType.transfer) {
            final kind = categoryKind(source.type);
            var category = categories
                .where(
                  (c) =>
                      c.kind == kind &&
                      c.name.toLowerCase() ==
                          source.category.trim().toLowerCase(),
                )
                .firstOrNull;
            if (category == null) {
              if (source.category.trim().isEmpty) {
                throw ArgumentError('Category is required.');
              }
              final id = await txn.insert('categories', {
                'kind': kind.name,
                'name': source.category.trim(),
                'icon': 'general',
              });
              category = LedgerCategory(
                id: id,
                name: source.category.trim(),
                kind: kind,
              );
              categories.add(category);
            }
            categoryName = category.name;
          }
          final entry = LedgerEntry(
            type: source.type,
            amount: source.amount,
            currency: source.currency,
            date: source.date,
            description: source.description,
            category: categoryName,
            accountId: source.accountId,
            destinationId: source.destinationId,
            notes: source.notes,
          );
          final key = signature(entry);
          if ((existing[key] ?? 0) > 0) {
            existing[key] = existing[key]! - 1;
            skipped++;
            continue;
          }
          await _writeEntry(
            txn,
            entry,
            allowUnassigned: true,
            checkFunds: false,
          );
          for (final id in [
            entry.accountId,
            entry.destinationId,
          ].whereType<int>()) {
            affectedRows[id] = row.number;
          }
          imported++;
        } on ArgumentError catch (e) {
          throw FormatException('Row ${row.number}: ${e.message}');
        }
      }
      // Validate the complete batch by ledger day. Same-day income/transfers
      // may fund expenses regardless of CSV row order; later days cannot.
      for (final affected in affectedRows.entries) {
        try {
          await _checkFunds(txn, [affected.key]);
        } on ArgumentError catch (e) {
          throw FormatException('Row ${affected.value}: ${e.message}');
        }
      }
    });
    await _refreshAfterWrite();
    return (imported: imported, skipped: skipped);
  }

  Future<int> _writeEntry(
    DatabaseExecutor txn,
    LedgerEntry entry, {
    bool allowUnassigned = false,
    bool checkFunds = true,
  }) async {
    if (entry.id != null) {
      final rows = await txn.query(
        'receipts',
        where: 'transaction_id = ?',
        whereArgs: [entry.id],
      );
      if (rows.isNotEmpty &&
          (entry.type != EntryType.expense ||
              rows.single['total'] != entry.amount)) {
        throw ArgumentError('Use invoice review to change the receipt total.');
      }
    }
    if (entry.currency != currency) {
      throw ArgumentError('Use the app currency.');
    }
    if (entry.amount <= 0 ||
        entry.amount > 9000000000000000 ||
        entry.description.trim().isEmpty ||
        entry.category.trim().isEmpty) {
      throw ArgumentError('Enter a positive amount, description and category.');
    }
    final previous = entry.id == null
        ? <Map<String, Object?>>[]
        : await txn.query(
            'transactions',
            where: 'id = ?',
            whereArgs: [entry.id],
          );
    if ((entry.type == EntryType.expense || entry.type == EntryType.income) &&
        entry.accountId == null &&
        !allowUnassigned &&
        (previous.isEmpty || previous.single['account_id'] != null)) {
      throw ArgumentError(
        'Choose cash or a bank account for this transaction.',
      );
    }
    if (entry.type != EntryType.transfer) {
      final valid = await txn.query(
        'categories',
        where: 'kind = ? AND name = ?',
        whereArgs: [categoryKind(entry.type).name, entry.category],
      );
      if (valid.isEmpty) {
        throw ArgumentError(
          'Select a category from the list for this transaction type.',
        );
      }
    }
    for (final id in [entry.accountId, entry.destinationId].whereType<int>()) {
      final rows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty || rows.single['currency'] != entry.currency.name) {
        throw ArgumentError(
          'Account must exist and match transaction currency.',
        );
      }
    }
    if ((entry.type == EntryType.expense || entry.type == EntryType.transfer) &&
        entry.accountId != null) {
      final source = (await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [entry.accountId],
      )).single;
      if (source['available'] != 1) {
        throw ArgumentError(
          'This account is blocked and cannot be used for spending or transfers out.',
        );
      }
    }
    if (entry.type == EntryType.transfer &&
        (entry.accountId == null ||
            entry.destinationId == null ||
            entry.accountId == entry.destinationId)) {
      throw ArgumentError('Choose two different accounts for a transfer.');
    }
    if (entry.type != EntryType.transfer && entry.destinationId != null) {
      throw ArgumentError('Only transfers have a destination account.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {...entry.toMap(), 'updated_at': now};
    var savedId = entry.id;
    if (entry.id == null) {
      savedId = await txn.insert('transactions', {
        ...values,
        'created_at': now,
      });
    } else {
      final count = await txn.update(
        'transactions',
        values,
        where: 'id = ?',
        whereArgs: [entry.id],
      );
      if (count != 1) {
        throw StateError('Transaction no longer exists.');
      }
    }
    if (checkFunds) {
      await _checkFunds(
        txn,
        {
          entry.accountId,
          entry.destinationId,
          if (previous.isNotEmpty) previous.single['account_id'] as int?,
          if (previous.isNotEmpty) previous.single['destination_id'] as int?,
        }.whereType<int>(),
      );
    }
    return savedId!;
  }

  Future<void> deleteEntry(int id) => deleteEntries({id});

  Future<void> updateEntries(
    Set<int> ids, {
    String? category,
    int? accountId,
    bool changeAccount = false,
  }) async {
    await db.transaction((txn) async {
      final affected = <int>{};
      for (final id in ids) {
        final rows = await txn.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isEmpty) {
          throw ArgumentError('A selected transaction no longer exists.');
        }
        final old = LedgerEntry.fromMap(rows.single);
        if (old.type == EntryType.transfer) {
          throw ArgumentError(
            'Edit transfers individually to choose both accounts.',
          );
        }
        if (category != null &&
            (await txn.query(
              'receipts',
              where: 'transaction_id = ?',
              whereArgs: [id],
            )).isNotEmpty) {
          throw ArgumentError(
            'Change categories on older single-expense invoices in invoice review.',
          );
        }
        final updated = LedgerEntry.fromMap({
          ...old.toMap(),
          'id': id,
          'category': ?category,
          if (changeAccount) 'account_id': accountId,
        });
        affected.addAll([old.accountId, updated.accountId].whereType<int>());
        await _writeEntry(
          txn,
          updated,
          allowUnassigned: changeAccount,
          checkFunds: false,
        );
        if (category != null) {
          await txn.update(
            'receipt_items',
            {'category': category, 'edited': 1},
            where: 'transaction_id = ?',
            whereArgs: [id],
          );
        }
      }
      await _checkFunds(txn, affected);
    });
    await _refreshAfterWrite();
  }

  Future<void> deleteEntries(Set<int> ids) async {
    final imagePaths = <String>[];
    await db.transaction((txn) async {
      final affected = <int>{};
      for (final id in ids) {
        final links = await txn.query(
          'scanned_invoice_entries',
          where: 'transaction_id = ?',
          whereArgs: [id],
        );
        for (final receipt in await txn.query(
          'receipts',
          where: 'transaction_id = ?',
          whereArgs: [id],
        )) {
          imagePaths.addAll(
            (jsonDecode(receipt['image_paths'] as String) as List)
                .cast<String>(),
          );
        }
        final rows = await txn.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
        for (final row in rows) {
          affected.addAll(
            [row['account_id'], row['destination_id']].whereType<int>(),
          );
        }
        for (final link in links) {
          final batchId = link['batch_id'];
          if ((await txn.query(
            'scanned_invoice_entries',
            where: 'batch_id = ?',
            whereArgs: [batchId],
          )).isEmpty) {
            final batches = await txn.query(
              'scanned_invoices',
              where: 'id = ?',
              whereArgs: [batchId],
            );
            for (final batch in batches) {
              imagePaths.addAll(
                (jsonDecode(batch['image_paths'] as String) as List)
                    .cast<String>(),
              );
            }
            await txn.delete(
              'scanned_invoices',
              where: 'id = ?',
              whereArgs: [batchId],
            );
          }
        }
      }
      await _checkFunds(txn, affected);
    });
    if (imagePaths.isNotEmpty) {
      await InvoiceImages().remove(imagePaths);
    }
    await _refreshAfterWrite();
  }

  Future<void> addAccount(Account account) async {
    _validateAccount(account);
    await db.insert('accounts', account.toMap());
    await _refreshAfterWrite();
  }

  static Future<bool> _canDeleteBankAccount(
    DatabaseExecutor txn,
    int id,
  ) async {
    final account = await txn.query(
      'accounts',
      where: "id = ? AND kind = 'bank'",
      whereArgs: [id],
    );
    if (account.isEmpty) return false;
    final transactions = await txn.query(
      'transactions',
      columns: ['id'],
      where: 'account_id = ? OR destination_id = ?',
      whereArgs: [id, id],
      limit: 1,
    );
    if (transactions.isNotEmpty) return false;
    for (final table in ['recurring_rules', 'recurring_occurrences']) {
      if ((await txn.query(
        table,
        columns: ['id'],
        where: 'account_id = ?',
        whereArgs: [id],
        limit: 1,
      )).isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  bool canDeleteBankAccount(int id) => _deletableBankIds.contains(id);

  Future<void> deleteBankAccount(int id) async {
    await db.transaction((txn) async {
      // Recheck atomically: an editor's earlier eligibility result may be stale.
      if (!await _canDeleteBankAccount(txn, id)) {
        throw ArgumentError(
          'Only bank accounts without transactions or recurring payment links can be deleted.',
        );
      }
      await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
    });
    await _refreshAfterWrite();
  }

  void _validateAccount(Account account, {Currency? selectedCurrency}) {
    if (account.currency != (selectedCurrency ?? currency)) {
      throw ArgumentError('Use the app currency.');
    }
    if (account.name.trim().isEmpty ||
        account.opening.abs() > 9000000000000000) {
      throw ArgumentError('Invalid account.');
    }
    if (!account.canOverdraw && account.opening < 0) {
      throw ArgumentError(
        'Cash and banks without overdraft cannot have a negative balance.',
      );
    }
  }

  Future<void> updateAccount(Account account) async {
    _validateAccount(account);
    if (account.id == null) {
      throw ArgumentError('Account no longer exists.');
    }
    await db.transaction((txn) async {
      final count = await txn.update(
        'accounts',
        account.toMap(),
        where: 'id = ?',
        whereArgs: [account.id],
      );
      if (count != 1) {
        throw ArgumentError('Account no longer exists.');
      }
      await _checkFunds(txn, [account.id!]);
    });
    await _refreshAfterWrite();
  }

  static Future<void> _checkFunds(
    DatabaseExecutor db,
    Iterable<int> ids,
  ) async {
    for (final id in ids.toSet()) {
      final rows = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) {
        continue;
      }
      final account = Account.fromMap(rows.single);
      if (account.canOverdraw) {
        continue;
      }
      final entries = (await db.query(
        'transactions',
        where: 'account_id = ? OR destination_id = ?',
        whereArgs: [id, id],
        orderBy: 'date, id',
      )).map(LedgerEntry.fromMap).toList();
      var balance = account.opening;
      final daily = <String, int>{};
      for (final entry in entries) {
        if (entry.currency != account.currency ||
            (account.includeOnAsOf
                ? entry.date.isBefore(account.asOf)
                : !entry.date.isAfter(account.asOf))) {
          continue;
        }
        var delta = 0;
        if (entry.accountId == id) {
          delta = entry.accountChange;
        }
        if (entry.type == EntryType.transfer && entry.destinationId == id) {
          delta += entry.amount;
        }
        daily.update(
          dayKey(entry.date),
          (value) => value + delta,
          ifAbsent: () => delta,
        );
      }
      if (balance < 0) {
        throw ArgumentError(
          'Insufficient funds in ${account.name}. Correct its starting balance first.',
        );
      }
      for (final change in daily.values) {
        balance += change;
        if (balance < 0) {
          throw ArgumentError(
            'Insufficient funds in ${account.name}. This change would make its balance negative.',
          );
        }
      }
    }
  }

  Future<void> completeSetup(
    List<Account> newAccounts, {
    Currency? selectedCurrency,
    List<Debt> initialDebts = const [],
  }) async {
    final setupCurrency = selectedCurrency ?? currency;
    if (setupCurrency != currency &&
        (accounts.isNotEmpty || entries.isNotEmpty)) {
      throw ArgumentError(
        'Existing amounts cannot be relabeled to another currency.',
      );
    }
    for (final debt in initialDebts) {
      _validateDebt(debt, setupCurrency);
    }
    for (final account in newAccounts) {
      _validateAccount(account, selectedCurrency: setupCurrency);
    }
    await db.transaction((txn) async {
      final done = await txn.query(
        'settings',
        where: 'key = ? AND value = ?',
        whereArgs: ['setup_completed', 'true'],
      );
      if (done.isNotEmpty) {
        return;
      }
      final existing = (await txn.query(
        'accounts',
        where: 'currency = ?',
        whereArgs: [setupCurrency.name],
      )).map(Account.fromMap);
      if (![
        ...existing,
        ...newAccounts,
      ].any((a) => a.kind == AccountKind.cash)) {
        throw ArgumentError('Set up your cash balance, even if it is zero.');
      }
      for (final account in newAccounts) {
        await txn.insert('accounts', account.toMap());
      }
      for (final debt in initialDebts) {
        await _writeDebt(txn, debt);
      }
      await txn.insert('settings', {
        'key': 'app_currency',
        'value': setupCurrency.name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('settings', {
        'key': 'setup_completed',
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await _refreshAfterWrite();
  }

  static void _validateDebt(Debt debt, Currency expected) {
    if (debt.name.trim().isEmpty ||
        debt.amount < 0 ||
        debt.amount > 9000000000000000 ||
        debt.currency != expected) {
      throw ArgumentError(
        'Enter a lender and a valid outstanding amount in the app currency.',
      );
    }
  }

  static Future<void> _writeDebt(DatabaseExecutor txn, Debt debt) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'name': debt.name.trim(),
      'amount': debt.amount,
      'currency': debt.currency.name,
      'updated_at': now,
    };
    if (debt.id == null) {
      await txn.insert('debts', {...values, 'created_at': now});
    } else {
      final count = await txn.update(
        'debts',
        values,
        where: 'id = ?',
        whereArgs: [debt.id],
      );
      if (count != 1) throw ArgumentError('Debt no longer exists.');
    }
  }

  Future<void> saveDebt(Debt debt) async {
    _validateDebt(debt, currency);
    await db.transaction((txn) => _writeDebt(txn, debt));
    await _refreshAfterWrite();
  }

  Future<void> deleteDebt(int id) async {
    await db.delete('debts', where: 'id = ?', whereArgs: [id]);
    await _refreshAfterWrite();
  }

  Future<void> saveCategory({
    int? id,
    required CategoryKind kind,
    required String name,
    CategoryIcon? icon,
    int? color,
  }) async {
    if (color != null && (color < 0xff000000 || color > 0xffffffff)) {
      throw ArgumentError('Choose an opaque category color.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Use a category name between 1 and 80 characters.');
    }
    await db.transaction((txn) async {
      final duplicate = await txn.query(
        'categories',
        where: 'kind = ? AND name = ? COLLATE NOCASE AND id != ?',
        whereArgs: [kind.name, trimmed, id ?? -1],
      );
      if (duplicate.isNotEmpty) {
        throw ArgumentError(
          'A category with this name already exists in this list.',
        );
      }
      if (id == null) {
        await txn.insert('categories', {
          'kind': kind.name,
          'name': trimmed,
          'icon': (icon ?? CategoryIcon.general).name,
          'color': color,
        });
      } else {
        final old = await txn.query(
          'categories',
          where: 'id = ? AND kind = ?',
          whereArgs: [id, kind.name],
        );
        if (old.isEmpty) {
          throw ArgumentError('Category no longer exists.');
        }
        await txn.update(
          'categories',
          {
            'name': trimmed,
            if (icon != null) 'icon': icon.name,
            'color': ?color,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        // Icon/color edits do not rename entries. Avoid rewriting every matching
        // transaction and decoding every legacy receipt for appearance changes.
        if (old.single['name'] == trimmed) return;
        await txn.update(
          'transactions',
          {
            'category': trimmed,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: kind == CategoryKind.income
              ? "category = ? AND type = 'income'"
              : "category = ? AND type IN ('expense','refund')",
          whereArgs: [old.single['name']],
        );
        for (final table in ['recurring_rules', 'recurring_occurrences']) {
          await txn.update(
            table,
            {'category': trimmed},
            where: 'category = ? AND type = ?',
            whereArgs: [old.single['name'], kind.name],
          );
        }
        if (kind == CategoryKind.expense) {
          await txn.update(
            'receipt_items',
            {'category': trimmed},
            where: 'category = ?',
            whereArgs: [old.single['name']],
          );
          for (final receipt in await txn.query('receipts')) {
            final draft =
                jsonDecode(receipt['draft'] as String) as Map<String, dynamic>;
            if (draft['category'] == old.single['name']) {
              draft['category'] = trimmed;
            }
            for (final item in draft['items'] as List) {
              if (item['category'] == old.single['name']) {
                item['category'] = trimmed;
              }
            }
            await txn.update(
              'receipts',
              {'draft': jsonEncode(draft)},
              where: 'id = ?',
              whereArgs: [receipt['id']],
            );
          }
        }
      }
    });
    await _refreshAfterWrite();
  }

  Future<void> saveRecurring(RecurringRule rule, {DateTime? today}) async {
    if (rule.type != EntryType.expense && rule.type != EntryType.income) {
      throw ArgumentError('Recurring entries must be expenses or income.');
    }
    if ((rule.isAsset && rule.type != EntryType.income) ||
        (rule.isLiability && rule.type != EntryType.expense)) {
      throw ArgumentError(
        'Only income can be marked as an asset and expenses as a liability.',
      );
    }
    final current = dateOnly(today ?? DateTime.now());
    if (rule.description.trim().isEmpty ||
        rule.amount <= 0 ||
        rule.amount > 9000000000000000 ||
        rule.day < 1 ||
        rule.day > 31 ||
        rule.interval < 1 ||
        rule.interval > 120 ||
        rule.nextDate !=
            monthlyDate(rule.nextDate.year, rule.nextDate.month, rule.day) ||
        rule.nextDate.isBefore(current) ||
        (rule.endDate != null && rule.endDate!.isBefore(rule.nextDate))) {
      throw ArgumentError(
        'Check the amount, schedule and first payment date. New schedules cannot start in the past.',
      );
    }
    await db.transaction((txn) async {
      final accounts = await txn.query(
        'accounts',
        where: rule.type == EntryType.income
            ? "id = ? AND currency = ?"
            : "id = ? AND available = 1 AND currency = ?",
        whereArgs: [rule.accountId, currency.name],
      );
      if (accounts.isEmpty) {
        throw ArgumentError(
          'Choose an unblocked payment account in the app currency.',
        );
      }
      final account = Account.fromMap(accounts.single);
      if (account.includeOnAsOf
          ? rule.nextDate.isBefore(account.asOf)
          : !rule.nextDate.isAfter(account.asOf)) {
        throw ArgumentError(
          'First payment must be after the account opening snapshot.',
        );
      }
      final categories = await txn.query(
        'categories',
        where: 'kind = ? AND name = ?',
        whereArgs: [categoryKind(rule.type).name, rule.category],
      );
      if (categories.isEmpty) {
        throw ArgumentError(
          'Select a category matching the recurring entry type.',
        );
      }
      if (rule.id == null) {
        await txn.insert('recurring_rules', rule.toMap());
      } else {
        final count = await txn.update(
          'recurring_rules',
          rule.toMap(),
          where: 'id = ? AND archived = 0',
          whereArgs: [rule.id],
        );
        if (count != 1) {
          throw ArgumentError('Recurring rule no longer exists.');
        }
      }
    });
    await processRecurring(today: current);
  }

  Future<void> setRecurringActive(
    int id,
    bool active, {
    DateTime? today,
  }) async {
    await db.transaction((txn) async {
      final rows = await txn.query(
        'recurring_rules',
        where: 'id = ? AND archived = 0',
        whereArgs: [id],
      );
      if (rows.isEmpty) {
        throw ArgumentError('Recurring rule no longer exists.');
      }
      final rule = RecurringRule.fromMap(rows.single);
      final now = dateOnly(today ?? DateTime.now());
      await txn.update(
        'recurring_rules',
        {
          'active': active ? 1 : 0,
          if (active && rule.nextDate.isBefore(now))
            'next_date': dayKey(firstMonthlyDate(now, rule.day)),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await processRecurring(today: today);
  }

  Future<void> archiveRecurring(int id) async {
    await db.update(
      'recurring_rules',
      {'active': 0, 'archived': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _refreshAfterWrite();
  }

  Future<void> _postOccurrence(
    DatabaseExecutor txn,
    int id, {
    DateTime? paymentDate,
  }) async {
    final row = (await txn.query(
      'recurring_occurrences',
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    final occurrence = RecurringOccurrence.fromMap(row);
    if (occurrence.status != 'failed') {
      return;
    }
    final chargedOn = paymentDate ?? occurrence.date;
    if (chargedOn.isBefore(occurrence.date)) {
      throw ArgumentError(
        'An unpaid bill cannot be paid before its scheduled date.',
      );
    }
    await txn.execute('SAVEPOINT recurring_post');
    try {
      final account = Account.fromMap(
        (await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [occurrence.accountId],
        )).single,
      );
      if (account.includeOnAsOf
          ? chargedOn.isBefore(account.asOf)
          : !chargedOn.isAfter(account.asOf)) {
        throw ArgumentError(
          'Payment date is covered by the account opening snapshot.',
        );
      }
      final transactionId = await _writeEntry(
        txn,
        LedgerEntry(
          type: occurrence.type,
          amount: occurrence.amount,
          currency: currency,
          date: chargedOn,
          description: occurrence.description,
          category: occurrence.category,
          accountId: occurrence.accountId,
        ),
      );
      await txn.execute('RELEASE recurring_post');
      await txn.update(
        'recurring_occurrences',
        {'status': 'posted', 'transaction_id': transactionId, 'error': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    } on ArgumentError catch (e) {
      await txn.execute('ROLLBACK TO recurring_post');
      await txn.execute('RELEASE recurring_post');
      await txn.update(
        'recurring_occurrences',
        {'error': '${e.message}'},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> processRecurring({DateTime? today}) async {
    final current = dayKey(dateOnly(today ?? DateTime.now()));
    await db.transaction((txn) async {
      // Process all schedules in date order; same-day income funds same-day expenses.
      for (var count = 0; count < 6000; count++) {
        final rows = await txn.query(
          'recurring_rules',
          where: 'active = 1 AND archived = 0 AND next_date <= ?',
          whereArgs: [current],
          orderBy: "next_date, CASE WHEN type = 'income' THEN 0 ELSE 1 END, id",
          limit: 1,
        );
        if (rows.isEmpty) {
          break;
        }
        final rule = RecurringRule.fromMap(rows.single);
        final due = rule.nextDate;
        if (rule.endDate != null && due.isAfter(rule.endDate!)) {
          await txn.update(
            'recurring_rules',
            {'active': 0},
            where: 'id = ?',
            whereArgs: [rule.id],
          );
          continue;
        }
        final existing = await txn.query(
          'recurring_occurrences',
          where: 'rule_id = ? AND scheduled_date = ?',
          whereArgs: [rule.id, dayKey(due)],
        );
        if (existing.isEmpty) {
          final id = await txn.insert('recurring_occurrences', {
            'rule_id': rule.id,
            'scheduled_date': dayKey(due),
            'type': rule.type.name,
            'description': rule.description,
            'amount': rule.amount,
            'category': rule.category,
            'account_id': rule.accountId,
            'status': 'failed',
          });
          await _postOccurrence(txn, id);
        }
        final next = monthlyDate(due.year, due.month + rule.interval, rule.day);
        await txn.update(
          'recurring_rules',
          {
            'next_date': dayKey(next),
            if (rule.endDate != null && next.isAfter(rule.endDate!))
              'active': 0,
          },
          where: 'id = ?',
          whereArgs: [rule.id],
        );
      }
    });
    await _refreshAfterWrite();
  }

  Future<void> retryRecurring(int id, {DateTime? paidOn}) async {
    await db.transaction(
      (txn) => _postOccurrence(
        txn,
        id,
        paymentDate: dateOnly(paidOn ?? DateTime.now()),
      ),
    );
    await _refreshAfterWrite();
  }

  Future<void> skipRecurring(int id) async {
    await db.update(
      'recurring_occurrences',
      {'status': 'skipped', 'error': null},
      where: "id = ? AND status = 'failed'",
      whereArgs: [id],
    );
    await _refreshAfterWrite();
  }

  Future<Map<String, Object?>?> scannedInvoiceFor(int transactionId) async =>
      (await db.rawQuery(
        'SELECT s.* FROM scanned_invoices s JOIN scanned_invoice_entries e ON e.batch_id = s.id WHERE e.transaction_id = ?',
        [transactionId],
      )).firstOrNull;

  Future<void> saveInvoiceBatch({
    required InvoiceDraft draft,
    required int accountId,
    required List<String> imagePaths,
  }) async {
    validateInvoice(
      draft,
      categoriesFor(draft.type).map((c) => c.name).toSet(),
      currency: currency,
    );
    await db.transaction((txn) async {
      final batchId = await txn.insert('scanned_invoices', {
        'draft': jsonEncode(draft.toMap()),
        'image_paths': jsonEncode(imagePaths),
        'raw_response': draft.raw,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      final lines = [
        ...(draft.type == EntryType.income
            ? draft.items
            : expandInvoiceItems(draft.items)),
        if ((draft.adjustment ?? 0) != 0)
          InvoiceItem(
            description: draft.adjustmentNote,
            quantity: '1',
            total: draft.adjustment,
            category: draft.category,
            edited: true,
            date: draft.date,
          ),
      ];
      // Credits first so an invoice discount can fund the gross item charges;
      // the transaction still commits all lines together or none.
      lines.sort(
        (a, b) => (a.total! < 0 ? 0 : 1).compareTo(b.total! < 0 ? 0 : 1),
      );
      for (var i = 0; i < lines.length; i++) {
        final item = lines[i];
        if (item.total == 0) {
          continue;
        }
        final id = await _writeEntry(
          txn,
          LedgerEntry(
            type: draft.type == EntryType.income
                ? EntryType.income
                : item.total! < 0
                ? EntryType.refund
                : EntryType.expense,
            amount: item.total!.abs(),
            currency: currency,
            date: item.date ?? draft.date!,
            description: item.description.trim(),
            category: item.category!,
            accountId: accountId,
            notes:
                '${draft.type == EntryType.income ? 'Payer' : 'Merchant'}: ${draft.merchant}',
          ),
          checkFunds: false,
        );
        await txn.insert('scanned_invoice_entries', {
          'transaction_id': id,
          'batch_id': batchId,
        });
        await txn.insert('receipt_items', {
          ...(item.toMap()..remove('date')),
          'item_date': dayKey(item.date ?? draft.date!),
          'transaction_id': id,
          'position': 0,
        });
      }
      await _checkFunds(txn, [accountId]);
    });
    await _refreshAfterWrite();
  }

  Future<Map<String, Object?>?> receiptFor(int id) async => (await db.query(
    'receipts',
    where: 'transaction_id = ?',
    whereArgs: [id],
  )).firstOrNull;
  Future<void> saveInvoice({
    required InvoiceDraft draft,
    required int accountId,
    required List<String> imagePaths,
    int? transactionId,
  }) async {
    if (draft.date == null || draft.multipleInvoices) {
      throw ArgumentError('Legacy invoice expenses require one invoice date.');
    }
    if (draft.type != EntryType.expense) {
      throw ArgumentError('Legacy invoice editing supports expenses only.');
    }
    validateInvoice(
      draft,
      categoriesFor(EntryType.expense).map((c) => c.name).toSet(),
      currency: currency,
    );
    await db.transaction((txn) async {
      final existing = transactionId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'receipts',
              where: 'transaction_id = ?',
              whereArgs: [transactionId],
            );
      if (transactionId != null && existing.isEmpty) {
        throw ArgumentError('Invoice no longer exists.');
      }
      if (existing.isNotEmpty) {
        await txn.update(
          'receipts',
          {'total': draft.total},
          where: 'transaction_id = ?',
          whereArgs: [transactionId],
        );
      }
      final id = await _writeEntry(
        txn,
        LedgerEntry(
          id: transactionId,
          type: EntryType.expense,
          amount: draft.total!,
          currency: currency,
          date: draft.date!,
          description: draft.merchant.trim(),
          category: draft.category!,
          accountId: accountId,
          notes: draft.adjustmentNote,
        ),
      );
      final values = {
        'transaction_id': id,
        'total': draft.total,
        'draft': jsonEncode(draft.toMap()),
        'image_paths': jsonEncode(imagePaths),
        'raw_response': existing.isEmpty
            ? draft.raw
            : existing.single['raw_response'],
        'scanned_at': existing.isEmpty
            ? DateTime.now().toUtc().toIso8601String()
            : existing.single['scanned_at'],
      };
      if (existing.isEmpty) {
        await txn.insert('receipts', values);
      } else {
        await txn.update(
          'receipts',
          values,
          where: 'transaction_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete(
        'receipt_items',
        where: 'transaction_id = ?',
        whereArgs: [id],
      );
      for (var i = 0; i < draft.items.length; i++) {
        await txn.insert('receipt_items', {
          ...(draft.items[i].toMap()..remove('date')),
          'item_date': draft.items[i].date == null
              ? null
              : dayKey(draft.items[i].date!),
          'transaction_id': id,
          'position': i,
        });
      }
    });
    await _refreshAfterWrite();
  }
}
