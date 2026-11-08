import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/receipts/invoice.dart';
import '../../features/receipts/gemini_key_provider.dart';
import '../../features/receipts/invoice_images.dart';
import '../domain/category.dart';
import '../domain/currency_exchange.dart';
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
  Map<int, ({int id, String label})> _invoiceGroups = const {};
  Map<int, ({int id, String label})> get invoiceGroups => _invoiceGroups;
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
  int get totalDebt => debts
      .where((d) => !d.isReceivable)
      .fold(0, (sum, debt) => sum + (debtMainAmount(debt) ?? 0));
  int get totalReceivable => debts
      .where((d) => d.isReceivable)
      .fold(0, (sum, debt) => sum + (debtMainAmount(debt) ?? 0));
  CurrencyExchangeTable exchangeTable = CurrencyExchangeTable({});
  int? debtMainAmount(Debt debt) => debt.amount == 0
      ? 0
      : exchangeTable.convert(debt.amount, debt.currency, currency);
  bool get hasUnvaluedDebts =>
      debts.any((d) => d.amount > 0 && debtMainAmount(d) == null);
  Future<void> saveExchangeRates(Map<String, String> values) async {
    final normalized = <String, String>{};
    for (final item in values.entries) {
      final pair = item.key.split('_');
      if (pair.length != 2 || pair[0] == pair[1]) {
        throw ArgumentError('Choose two different currencies.');
      }
      Currency.values.byName(pair[0]);
      Currency.values.byName(pair[1]);
      normalized[item.key] = ConversionRate.parse(item.value).text;
    }
    await db.transaction((txn) async {
      await txn.insert('settings', {
        'key': 'currency_exchange_rates',
        'value': jsonEncode(normalized),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await _refreshAfterWrite();
  }

  Map<int, int> _debtFeeLinks = const {};
  Map<int, int> get debtFeeLinks => _debtFeeLinks;
  Map<int, int> _debtPaymentLinks = const {};
  Map<int, int> get debtPaymentLinks => _debtPaymentLinks;
  int get netWealth => currentBalances.wealth - totalDebt + totalReceivable;
  int invoiceTimeoutSeconds = 180;
  String geminiConfigUrl = GeminiKeyProvider.configUrl;
  bool geminiUseManualKey = false;
  bool notificationsEnabled = true;
  String geminiManualKey = '';

  Future<void> saveNotificationsEnabled(bool enabled) async {
    await db.insert('settings', {
      'key': 'notifications_enabled',
      'value': enabled.toString(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _refreshAfterWrite();
  }

  static bool validGeminiConfigUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        !RegExp(r'\s').hasMatch(value.trim());
  }

  static bool validGeminiKey(String value) =>
      value.trim().length >= 20 && !RegExp(r'\s').hasMatch(value.trim());

  Future<void> saveInvoiceSettings({
    required int seconds,
    required String configUrl,
    required bool useManualKey,
    required String manualKey,
  }) async {
    if (seconds < 30 ||
        seconds > 900 ||
        !validGeminiConfigUrl(configUrl) ||
        (useManualKey && !validGeminiKey(manualKey))) {
      throw ArgumentError('Enter valid invoice scanning settings.');
    }
    await db.transaction((txn) async {
      for (final setting in {
        'invoice_timeout_seconds': '$seconds',
        'gemini_config_url': configUrl.trim(),
        'gemini_use_manual_key': '$useManualKey',
        'gemini_manual_key': manualKey.trim(),
      }.entries) {
        await txn.insert('settings', {
          'key': setting.key,
          'value': setting.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await _refreshAfterWrite();
  }

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
      final batchLinks = await txn.rawQuery(
        'SELECT e.transaction_id, e.batch_id, s.draft FROM scanned_invoice_entries e JOIN scanned_invoices s ON s.id = e.batch_id',
      );
      final scannedIds = batchLinks
          .map((r) => r['transaction_id'] as int)
          .toSet();
      final invoiceGroups = <int, ({int id, String label})>{};
      final batchLabels = <int, String>{};
      for (final row in batchLinks) {
        final batch = row['batch_id'] as int;
        final label = batchLabels.putIfAbsent(batch, () {
          var merchant = '';
          try {
            final draft = jsonDecode(row['draft'] as String);
            if (draft is Map && draft['merchant'] is String) {
              merchant = (draft['merchant'] as String).trim();
            }
          } on FormatException {
            // Damaged source metadata must not prevent reading the ledger.
          }
          return 'Invoice #$batch${merchant.isEmpty ? '' : ' - $merchant'}';
        });
        invoiceGroups[row['transaction_id'] as int] = (id: batch, label: label);
      }
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
            where: 'COALESCE(base_currency, currency) != ?',
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
        where: 'COALESCE(base_currency, currency) = ?',
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
        geminiConfigUrl:
            settingsByKey['gemini_config_url'] ?? GeminiKeyProvider.configUrl,
        geminiUseManualKey: settingsByKey['gemini_use_manual_key'] == 'true',
        notificationsEnabled: settingsByKey['notifications_enabled'] != 'false',
        geminiManualKey: settingsByKey['gemini_manual_key'] ?? '',
        profileName: settingsByKey['profile_name'] ?? '',
        profileEmail: settingsByKey['profile_email'] ?? '',
        deletableBankIds: deletableBankIds,
        currency: activeCurrency,
        debts: debtList,
        exchangeRates: Map<String, String>.from(
          jsonDecode(settingsByKey['currency_exchange_rates'] ?? '{}') as Map,
        ),
        debtFeeLinks: {
          for (final row in await txn.query(
            'debt_payments',
            where: 'debt_id IS NOT NULL AND fee_transaction_id IS NOT NULL',
          ))
            row['fee_transaction_id'] as int: row['transaction_id'] as int,
        },
        debtPaymentLinks: {
          for (final row in await txn.query(
            'debt_payments',
            where: 'debt_id IS NOT NULL',
          ))
            row['transaction_id'] as int: row['debt_id'] as int,
        },
        timeout: timeout,
        receiptIds: receiptIds,
        scannedIds: scannedIds,
        invoiceGroups: invoiceGroups,
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
    exchangeTable = CurrencyExchangeTable(snapshot.exchangeRates);
    _debtPaymentLinks = Map.unmodifiable(snapshot.debtPaymentLinks);
    _debtFeeLinks = Map.unmodifiable(snapshot.debtFeeLinks);
    invoiceTimeoutSeconds = snapshot.timeout;
    geminiConfigUrl = snapshot.geminiConfigUrl;
    geminiUseManualKey = snapshot.geminiUseManualKey;
    notificationsEnabled = snapshot.notificationsEnabled;
    geminiManualKey = snapshot.geminiManualKey;
    _receiptTransactionIds = Set.unmodifiable(snapshot.receiptIds);
    _scannedInvoiceTransactionIds = Set.unmodifiable(snapshot.scannedIds);
    _invoiceGroups = Map.unmodifiable(snapshot.invoiceGroups);
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

  /// Builds reporting and native amounts together. Reporting values are frozen
  /// on save; account rates subsequently revalue only current account totals.
  LedgerEntry entryFromInput({
    int? id,
    required EntryType type,
    required int inputAmount,
    required Currency inputCurrency,
    required DateTime date,
    required String description,
    required String category,
    int? accountId,
    int? destinationId,
    int? receivedAmount,
    String notes = '',
  }) {
    final source = accounts.where((a) => a.id == accountId).firstOrNull;
    final target = accounts.where((a) => a.id == destinationId).firstOrNull;
    return _fromInput(
      id: id,
      type: type,
      inputAmount: inputAmount,
      inputCurrency: inputCurrency,
      date: date,
      description: description,
      category: category,
      source: source,
      target: target,
      accountId: accountId,
      destinationId: destinationId,
      receivedAmount: receivedAmount,
      notes: notes,
    );
  }

  LedgerEntry _fromInput({
    int? id,
    required EntryType type,
    required int inputAmount,
    required Currency inputCurrency,
    required DateTime date,
    required String description,
    required String category,
    Account? source,
    Account? target,
    int? accountId,
    int? destinationId,
    int? receivedAmount,
    String notes = '',
  }) {
    if (inputAmount <= 0) {
      throw ArgumentError('Enter an amount greater than zero.');
    }
    if (inputCurrency != currency && inputCurrency != source?.currency) {
      throw ArgumentError(
        'Use the app currency or the selected account currency.',
      );
    }
    final native = source == null
        ? inputAmount
        : inputCurrency == source.currency
        ? inputAmount
        : source.fromBase(inputAmount);
    final base = inputCurrency == currency
        ? inputAmount
        : source!.toBase(inputAmount);
    if (base <= 0 || native <= 0) {
      throw ArgumentError(
        'Amount is below the smallest supported currency unit.',
      );
    }
    int? received;
    if (type == EntryType.transfer) {
      if (source == null || target == null || source.id == target.id) {
        throw ArgumentError('Choose two different accounts for a transfer.');
      }
      if (source.currency != target.currency && receivedAmount == null) {
        throw ArgumentError(
          'Enter the amount received in the destination currency.',
        );
      }
      received = receivedAmount ?? native;
      if (received <= 0 ||
          received > 9000000000000000 ||
          (source.currency == target.currency && received != native)) {
        throw ArgumentError(
          'Check the amount received by the destination account.',
        );
      }
    }
    final snapshot =
        source != null &&
            (source.currency != currency ||
                (target != null && target.currency != currency))
        ? FxSnapshot(
            inputCurrency: inputCurrency,
            inputAmount: inputAmount,
            sourceCurrency: source.currency,
            sourceAmount: native,
            sourceRate: source.exchangeRate,
            targetCurrency: target?.currency,
            targetAmount: received,
            targetRate: target?.exchangeRate,
          )
        : null;
    return LedgerEntry(
      id: id,
      type: type,
      amount: base,
      currency: currency,
      date: date,
      description: description,
      category: category,
      notes: notes,
      accountId: accountId,
      destinationId: destinationId,
      accountAmount: source == null ? null : native,
      destinationAmount: received,
      fx: snapshot,
    );
  }

  Future<void> saveEntry(LedgerEntry entry, {DateTime? createdAt}) async {
    await db.transaction((txn) async {
      await _writeEntry(txn, entry);
      if (createdAt != null && entry.id != null) {
        await txn.update(
          'transactions',
          {'created_at': createdAt.toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      }
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
      String signature(LedgerEntry e) {
        final source = accounts.where((a) => a.id == e.accountId).firstOrNull;
        final target = accounts
            .where((a) => a.id == e.destinationId)
            .firstOrNull;
        return jsonEncode({
          ...e.toMap(),
          'account_amount': e.accountAmount ?? source?.fromBase(e.amount),
          'destination_amount': e.type != EntryType.transfer
              ? null
              : e.destinationAmount ?? target?.fromBase(e.amount),
        });
      }

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
            accountAmount: source.accountAmount,
            destinationAmount: source.destinationAmount,
            fx: source.fx,
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
    LedgerEntry input, {
    bool allowUnassigned = false,
    bool checkFunds = true,
    bool allowSettlementWrite = false,
  }) async {
    var entry = input;
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
      if (rows.isEmpty ||
          Account.fromMap(rows.single).reportingCurrency != currency) {
        throw ArgumentError(
          'Account must exist and use the app reporting currency.',
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
    final oldEntry = previous.isEmpty
        ? null
        : LedgerEntry.fromMap(previous.single);
    final sameMoney =
        oldEntry != null &&
        oldEntry.amount == entry.amount &&
        oldEntry.currency == entry.currency &&
        oldEntry.type == entry.type &&
        oldEntry.accountId == entry.accountId &&
        oldEntry.destinationId == entry.destinationId;
    if (entry.fx == null && entry.accountAmount == null && sameMoney) {
      entry = entry.withAmounts(
        accountAmount: oldEntry.accountAmount,
        destinationAmount: oldEntry.destinationAmount,
        fx: oldEntry.fx,
      );
    }
    final staleAmounts =
        oldEntry != null &&
        oldEntry.amount != entry.amount &&
        oldEntry.accountAmount == entry.accountAmount &&
        jsonEncode(oldEntry.fx?.toMap()) == jsonEncode(entry.fx?.toMap());
    if (!allowSettlementWrite &&
        (staleAmounts ||
            entry.accountAmount == null ||
            (oldEntry != null &&
                (oldEntry.accountId != entry.accountId ||
                    oldEntry.destinationId != entry.destinationId)))) {
      final sourceRows = entry.accountId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'accounts',
              where: 'id = ?',
              whereArgs: [entry.accountId],
            );
      final targetRows = entry.destinationId == null
          ? <Map<String, Object?>>[]
          : await txn.query(
              'accounts',
              where: 'id = ?',
              whereArgs: [entry.destinationId],
            );
      entry = _fromInput(
        id: entry.id,
        type: entry.type,
        inputAmount: entry.amount,
        inputCurrency: currency,
        date: entry.date,
        description: entry.description,
        category: entry.category,
        notes: entry.notes,
        accountId: entry.accountId,
        destinationId: entry.destinationId,
        source: sourceRows.isEmpty ? null : Account.fromMap(sourceRows.single),
        target: targetRows.isEmpty ? null : Account.fromMap(targetRows.single),
        receivedAmount: entry.destinationAmount,
      );
    }
    for (final native in [
      entry.accountAmount,
      entry.destinationAmount,
    ].whereType<int>()) {
      if (native <= 0 || native > 9000000000000000) {
        throw ArgumentError('Invalid account amount.');
      }
    }
    final fx = entry.fx;
    if (fx != null) {
      for (final value in [
        fx.inputAmount,
        fx.sourceAmount,
        fx.targetAmount,
      ].whereType<int>()) {
        if (value <= 0 || value > 9000000000000000) {
          throw ArgumentError('Invalid original currency amount.');
        }
      }
      final rate = ExchangeRate.parse(fx.sourceRate);
      if (fx.targetRate != null) ExchangeRate.parse(fx.targetRate!);
      if (fx.inputCurrency != entry.currency &&
          fx.inputCurrency != fx.sourceCurrency) {
        throw ArgumentError('Invalid original input currency.');
      }
      final expected = fx.inputCurrency == entry.currency
          ? fx.inputAmount
          : rate.toBase(
              fx.inputAmount,
              fx.inputCurrency.scale,
              entry.currency.scale,
            );
      if (expected != entry.amount ||
          (entry.type == EntryType.transfer &&
              (fx.targetCurrency == null || fx.targetAmount == null)) ||
          (entry.type != EntryType.transfer &&
              (fx.targetCurrency != null || fx.targetAmount != null))) {
        throw ArgumentError('Currency details do not match this transaction.');
      }
    }
    if (entry.id != null &&
        !allowSettlementWrite &&
        (await txn.query(
          'debt_payments',
          where: 'fee_transaction_id = ? AND debt_id IS NOT NULL',
          whereArgs: [entry.id],
        )).isNotEmpty) {
      throw ArgumentError('Edit this fee through the linked debt payment.');
    }
    if (entry.id != null) {
      final links = await txn.rawQuery(
        'SELECT p.amount AS paid, p.details, d.amount AS remaining, d.is_receivable FROM debt_payments p JOIN debts d ON d.id = p.debt_id WHERE p.transaction_id = ?',
        [entry.id],
      );
      if (links.isNotEmpty) {
        final link = links.single;
        final expected = link['is_receivable'] == 1
            ? EntryType.income
            : EntryType.expense;
        if (entry.type != expected ||
            entry.category != debtCategory(expected)) {
          throw ArgumentError(
            'Keep the Debt category and payment type for this settlement.',
          );
        }
        if (link['details'] != null && !allowSettlementWrite) {
          throw ArgumentError(
            'Edit this payment from its debt settlement editor.',
          );
        }
        if (link['details'] == null &&
            entry.amount > (link['paid'] as int) + (link['remaining'] as int)) {
          throw ArgumentError('Payment exceeds the remaining balance.');
        }
      }
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
          if (changeAccount) ...{
            'account_id': accountId,
            'account_amount': null,
            'destination_amount': null,
            'fx_snapshot': null,
          },
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
      final deleting = {...ids};
      for (final id in ids) {
        for (final link in await txn.query(
          'debt_payments',
          where: 'transaction_id = ?',
          whereArgs: [id],
        )) {
          if (link['fee_transaction_id'] != null) {
            deleting.add(link['fee_transaction_id'] as int);
          }
        }
      }
      for (final id in deleting) {
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
    account.toBase(account.opening);
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

  void _validateAccount(
    Account account, {
    Currency? selectedCurrency,
    bool checkOpening = true,
  }) {
    final base = selectedCurrency ?? currency;
    if (account.reportingCurrency != base ||
        (account.kind == AccountKind.cash && account.currency != base)) {
      throw ArgumentError(
        'Cash must use the app currency; foreign banks need a reporting currency.',
      );
    }
    account.rate;
    if (account.name.trim().isEmpty ||
        account.opening.abs() > 9000000000000000) {
      throw ArgumentError('Invalid account.');
    }
    if (checkOpening && !account.canOverdraw && account.opening < 0) {
      throw ArgumentError(
        'Cash and banks without overdraft cannot have a negative balance.',
      );
    }
  }

  Future<void> updateAccount(Account account, {int? currentBalance}) async {
    _validateAccount(account, checkOpening: false);
    if (account.id == null) {
      throw ArgumentError('Account no longer exists.');
    }
    await db.transaction((txn) async {
      final oldRows = await txn.query(
        'accounts',
        where: 'id = ?',
        whereArgs: [account.id],
      );
      if (oldRows.isEmpty) throw ArgumentError('Account no longer exists.');
      final old = Account.fromMap(oldRows.single);
      final linked = (await txn.query(
        'transactions',
        where: 'account_id = ? OR destination_id = ?',
        whereArgs: [account.id, account.id],
      )).map(LedgerEntry.fromMap).toList();
      var opening = account.opening;
      if (old.currency != account.currency) {
        opening = old.convertTo(account, old.opening);
        for (final entry in linked) {
          final values = <String, Object?>{};
          if (entry.accountId == account.id &&
              (entry.accountAmount != null || entry.currency == old.currency)) {
            values['account_amount'] = old.convertTo(
              account,
              entry.accountAmount ?? entry.amount,
            );
          }
          if (entry.destinationId == account.id &&
              (entry.destinationAmount != null ||
                  entry.currency == old.currency)) {
            values['destination_amount'] = old.convertTo(
              account,
              entry.destinationAmount ?? entry.amount,
            );
          }
          if (values.values.any((value) => value == 0)) {
            throw ArgumentError(
              'Currency change would round an existing payment to zero.',
            );
          }
          await txn.update(
            'transactions',
            values,
            where: 'id = ?',
            whereArgs: [entry.id],
          );
        }
        for (final table in ['recurring_rules', 'recurring_occurrences']) {
          for (final row in await txn.query(
            table,
            where: table == 'recurring_rules' && old.currency == currency
                ? 'account_id = ? AND (currency = ? OR currency IS NULL)'
                : 'account_id = ? AND currency = ?',
            whereArgs: [account.id, old.currency.name],
          )) {
            // Posted history describes its original input and must not change.
            if (table == 'recurring_occurrences' && row['status'] != 'failed') {
              continue;
            }
            final converted = old.convertTo(account, row['amount'] as int);
            if (converted <= 0) {
              throw ArgumentError(
                'Currency change would round a recurring payment to zero.',
              );
            }
            await txn.update(
              table,
              {'amount': converted, 'currency': account.currency.name},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          }
        }
      }
      final desiredBalance =
          currentBalance ??
          (old.currency == account.currency
              ? null
              : old.convertTo(
                  account,
                  accountBalance(old, linked, DateTime.now()),
                ));
      if (desiredBalance != null) {
        final revised = (await txn.query(
          'transactions',
          where: 'account_id = ? OR destination_id = ?',
          whereArgs: [account.id, account.id],
        )).map(LedgerEntry.fromMap);
        final baseline = Account(
          id: account.id,
          name: account.name,
          currency: account.currency,
          baseCurrency: account.reportingCurrency,
          exchangeRate: account.exchangeRate,
          opening: opening,
          asOf: old.asOf,
          includeOnAsOf: old.includeOnAsOf,
          kind: account.kind,
          available: account.available,
          allowOverdraft: account.allowOverdraft,
        );
        opening +=
            desiredBalance - accountBalance(baseline, revised, DateTime.now());
      }
      if (opening.abs() > 9000000000000000) {
        throw ArgumentError('Account balance exceeds the supported limit.');
      }

      final count = await txn.update(
        'accounts',
        {
          ...account.toMap(),
          'opening': opening,
          'as_of': dayKey(old.asOf),
          'include_on_as_of': old.includeOnAsOf ? 1 : 0,
        },
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
      if (account.canOverdraw &&
          account.currency == account.reportingCurrency) {
        continue;
      }
      final entries = (await db.query(
        'transactions',
        where: 'account_id = ? OR destination_id = ?',
        whereArgs: [id, id],
        orderBy: 'date, id',
      )).map(LedgerEntry.fromMap).toList();
      account.toBase(accountBalance(account, entries, DateTime.now()));
      if (account.canOverdraw) continue;
      var balance = account.opening;
      final daily = <String, int>{};
      for (final entry in entries) {
        if ((account.includeOnAsOf
            ? entry.date.isBefore(account.asOf)
            : !entry.date.isAfter(account.asOf))) {
          continue;
        }
        final delta = entry.changeFor(account);
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
    final setupRates = {...exchangeTable.rates};
    for (final account in newAccounts.where(
      (a) => a.currency != setupCurrency,
    )) {
      setupRates.putIfAbsent(
        CurrencyExchangeTable.key(setupCurrency, account.currency),
        () => account.exchangeRate,
      );
    }
    for (final debt in initialDebts) {
      _validateDebt(debt);
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
        'key': 'currency_exchange_rates',
        'value': jsonEncode(setupRates),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  static void _validateDebt(Debt debt) {
    if (debt.name.trim().isEmpty ||
        debt.amount < 0 ||
        debt.amount > 9000000000000000) {
      throw ArgumentError(
        'Enter a lender and a valid outstanding amount in the selected currency.',
      );
    }
  }

  static Future<int> _writeDebt(DatabaseExecutor txn, Debt debt) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'name': debt.name.trim(),
      'is_receivable': debt.isReceivable ? 1 : 0,
      'amount': debt.amount,
      'currency': debt.currency.name,
      'updated_at': now,
      'deadline': debt.deadline?.toIso8601String(),
      'deadline_acknowledged': debt.deadlineAcknowledged?.toIso8601String(),
    };
    if (debt.id == null) {
      return txn.insert('debts', {...values, 'created_at': now});
    } else {
      final count = await txn.update(
        'debts',
        values,
        where: 'id = ?',
        whereArgs: [debt.id],
      );
      if (count != 1) throw ArgumentError('Debt no longer exists.');
      return debt.id!;
    }
  }

  static Future<CurrencyExchangeTable> _readExchangeTable(
    DatabaseExecutor txn,
  ) async {
    final row = (await txn.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['currency_exchange_rates'],
    )).firstOrNull;
    return CurrencyExchangeTable(
      Map<String, String>.from(
        jsonDecode(row?['value'] as String? ?? '{}') as Map,
      ),
    );
  }

  Future<void> saveDebt(Debt debt) async {
    _validateDebt(debt);
    await db.transaction((txn) async {
      if (debt.id != null) {
        final old = (await txn.query(
          'debts',
          where: 'id = ?',
          whereArgs: [debt.id],
        )).firstOrNull;
        if (old != null &&
            ((old['is_receivable'] == 1) != debt.isReceivable ||
                old['currency'] != debt.currency.name) &&
            (await txn.query(
              'debt_payments',
              where: 'debt_id = ?',
              whereArgs: [debt.id],
            )).isNotEmpty) {
          throw ArgumentError(
            'A debt with payments cannot change currency or direction.',
          );
        }
      }
      await _writeDebt(txn, debt);
    });
    await _refreshAfterWrite();
  }

  String debtCategory(EntryType type) =>
      categoriesFor(type).firstWhere((c) => c.isSystemDebt).name;

  Future<void> payDebt(int debtId, LedgerEntry entry) async {
    if (entry.id != null) {
      throw ArgumentError('Use a new transaction to settle a debt.');
    }
    await db.transaction((txn) async {
      final row = (await txn.query(
        'debts',
        where: 'id = ?',
        whereArgs: [debtId],
      )).firstOrNull;
      if (row == null) throw ArgumentError('Debt no longer exists.');
      final debt = Debt.fromMap(row);
      final expected = debt.isReceivable ? EntryType.income : EntryType.expense;
      if (entry.type != expected ||
          entry.category != debtCategory(expected) ||
          entry.currency != debt.currency ||
          entry.amount > debt.amount) {
        throw ArgumentError(
          'Choose the Debt category and an amount up to the remaining balance.',
        );
      }
      final id = await _writeEntry(txn, entry);
      await txn.insert('debt_payments', {
        'transaction_id': id,
        'debt_id': debtId,
        'amount': entry.amount,
      });
    });
    await _refreshAfterWrite();
  }

  Future<Map<String, Object?>?> debtSettlement(int transactionId) async =>
      (await db.query(
        'debt_payments',
        where: 'transaction_id = ?',
        whereArgs: [transactionId],
      )).firstOrNull;

  /// Principal is in debt minor units; fee is in the selected account's units.
  /// Both ledger effects and the outstanding native balance commit together.
  Future<void> settleDebt({
    required int debtId,
    required int principal,
    required int accountId,
    required ConversionRate rate,
    required int fee,
    required DateTime date,
    int? transactionId,
    String? description,
    DateTime? createdAt,
  }) async {
    await db.transaction((txn) async {
      final row = (await txn.query(
        'debts',
        where: 'id = ?',
        whereArgs: [debtId],
      )).firstOrNull;
      if (row == null) throw ArgumentError('Debt no longer exists.');
      final debt = Debt.fromMap(row);
      final account = Account.fromMap(
        (await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [accountId],
        )).single,
      );
      final old = transactionId == null
          ? null
          : (await txn.query(
              'debt_payments',
              where: 'transaction_id = ? AND debt_id = ?',
              whereArgs: [transactionId, debtId],
            )).firstOrNull;
      if (transactionId != null && old == null) {
        throw ArgumentError('Settlement no longer exists.');
      }
      if (principal <= 0 ||
          principal > debt.amount + (old?['amount'] as int? ?? 0) ||
          fee < 0) {
        throw ArgumentError(
          'Enter a payment up to the remaining balance and a nonnegative fee.',
        );
      }
      if (account.currency == debt.currency && fee != 0) {
        throw ArgumentError('Fees apply only to currency conversion.');
      }
      final actualRate = account.currency == debt.currency
          ? ConversionRate.parse('1')
          : rate;
      final native = actualRate.convert(
        principal,
        debt.currency,
        account.currency,
      );
      if (native <= 0 || (debt.isReceivable && fee >= native)) {
        throw ArgumentError(
          'The converted amount must exceed zero and any receiving fee.',
        );
      }
      final affected = <int>{accountId};
      final oldEntry = transactionId == null
          ? null
          : LedgerEntry.fromMap(
              (await txn.query(
                'transactions',
                where: 'id = ?',
                whereArgs: [transactionId],
              )).single,
            );
      if (oldEntry?.accountId != null) affected.add(oldEntry!.accountId!);
      LedgerEntry? previousFee;
      if (old?['fee_transaction_id'] != null) {
        final feeId = old!['fee_transaction_id'] as int;
        final oldFee = (await txn.query(
          'transactions',
          where: 'id = ?',
          whereArgs: [feeId],
        )).firstOrNull;
        if (oldFee?['account_id'] != null) {
          affected.add(oldFee!['account_id'] as int);
        }
        if (oldFee != null) previousFee = LedgerEntry.fromMap(oldFee);
        if (fee == 0) {
          await txn.delete('transactions', where: 'id = ?', whereArgs: [feeId]);
        }
      }
      final details = jsonEncode({
        'rate': actualRate.toMap(),
        'account_currency': account.currency.name,
        'debt_currency': debt.currency.name,
      });
      if (old != null) {
        await txn.update(
          'debt_payments',
          {'details': details, 'amount': principal},
          where: 'transaction_id = ?',
          whereArgs: [transactionId],
        );
      }
      LedgerEntry entry(
        EntryType type,
        int value,
        String category,
        String label, {
        int? id,
      }) {
        final previous = id == transactionId ? oldEntry : previousFee;
        final unchanged =
            previous != null &&
            previous.accountId == accountId &&
            previous.accountAmount == value;
        final reporting = unchanged ? previous.amount : account.toBase(value);
        if (reporting <= 0) {
          throw ArgumentError('Amount is too small in ${currency.code}.');
        }
        return LedgerEntry(
          id: id,
          type: type,
          amount: reporting,
          currency: currency,
          accountId: accountId,
          accountAmount: value,
          date: date,
          description: label,
          category: category,
          notes: [
            if (previous != null)
              ...previous.notes
                  .split('\n')
                  .where((line) => !line.startsWith('Settlement: ')),
            'Settlement: ${debt.currency.display(principal)}; 1 ${debt.currency.code} = ${actualRate.text} ${account.currency.code}',
          ].where((line) => line.isNotEmpty).join('\n'),
          fx: unchanged
              ? previous.fx
              : FxSnapshot(
                  inputCurrency: currency,
                  inputAmount: reporting,
                  sourceCurrency: account.currency,
                  sourceAmount: value,
                  sourceRate: account.exchangeRate,
                ),
        );
      }

      final type = debt.isReceivable ? EntryType.income : EntryType.expense;
      final id = await _writeEntry(
        txn,
        entry(
          type,
          native,
          debtCategory(type),
          description ?? debt.name,
          id: transactionId,
        ),
        checkFunds: false,
        allowSettlementWrite: true,
      );
      if (createdAt != null && transactionId != null) {
        await txn.update(
          'transactions',
          {'created_at': createdAt.toUtc().toIso8601String()},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      int? feeId;
      if (fee > 0) {
        await txn.execute(
          "INSERT OR IGNORE INTO categories(kind,name,icon) VALUES ('expense','Exchange fees','general')",
        );
        feeId = await _writeEntry(
          txn,
          entry(
            EntryType.expense,
            fee,
            'Exchange fees',
            'Exchange fee: ${debt.name}',
            id: previousFee?.id,
          ),
          checkFunds: false,
          allowSettlementWrite: true,
        );
      }
      if (old == null) {
        await txn.insert('debt_payments', {
          'transaction_id': id,
          'debt_id': debtId,
          'amount': principal,
          'details': details,
          'fee_transaction_id': feeId,
        });
      } else {
        await txn.update(
          'debt_payments',
          {'fee_transaction_id': feeId},
          where: 'transaction_id = ?',
          whereArgs: [id],
        );
      }
      await _checkFunds(txn, affected);
    });
    await _refreshAfterWrite();
  }

  Future<void> moveRecurringToDebt(int occurrenceId) async {
    await db.transaction((txn) async {
      if ((await txn.query(
        'recurring_debts',
        where: 'occurrence_id = ?',
        whereArgs: [occurrenceId],
      )).isNotEmpty) {
        return;
      }
      final row = (await txn.query(
        'recurring_occurrences',
        where: 'id = ?',
        whereArgs: [occurrenceId],
      )).firstOrNull;
      if (row == null) throw ArgumentError('Payment no longer exists.');
      final occurrence = RecurringOccurrence.fromMap(row);
      if (!occurrence.manual || occurrence.status != 'failed') {
        throw ArgumentError(
          'Only an unconfirmed manual payment can become a debt.',
        );
      }
      final account = Account.fromMap(
        (await txn.query(
          'accounts',
          where: 'id = ?',
          whereArgs: [occurrence.accountId],
        )).single,
      );
      final inputCurrency = occurrence.currency ?? currency;
      final debt = Debt(
        name: occurrence.description,
        amount: occurrence.amount,
        currency: inputCurrency,
        isReceivable: occurrence.type == EntryType.income,
      );
      _validateDebt(debt);
      if (occurrence.amount <= 0) {
        throw ArgumentError('Debt amount must be positive.');
      }
      final table = await _readExchangeTable(txn);
      if (table.rate(inputCurrency, currency) == null &&
          inputCurrency == account.currency) {
        final rates = {
          ...table.rates,
          CurrencyExchangeTable.key(currency, inputCurrency):
              account.exchangeRate,
        };
        await txn.insert('settings', {
          'key': 'currency_exchange_rates',
          'value': jsonEncode(rates),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final debtId = await _writeDebt(txn, debt);
      await txn.insert('recurring_debts', {
        'occurrence_id': occurrenceId,
        'debt_id': debtId,
      });
      await txn.update(
        'recurring_occurrences',
        {
          'status': 'skipped',
          'error': debt.isReceivable
              ? 'Moved to receivables'
              : 'Moved to debts',
        },
        where: 'id = ?',
        whereArgs: [occurrenceId],
      );
    });
    await _refreshAfterWrite();
  }

  List<Debt> dueDebts([DateTime? now]) =>
      debts.where((d) => d.deadlineDue(now ?? DateTime.now())).toList()
        ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
  Future<void> acknowledgeDebtDeadline(int id, DateTime deadline) async {
    await db.update(
      'debts',
      {'deadline_acknowledged': deadline.toIso8601String()},
      where: 'id = ? AND deadline = ?',
      whereArgs: [id, deadline.toIso8601String()],
    );
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
        if ((old.single['name'] as String).toLowerCase() == 'debt' &&
            trimmed != old.single['name']) {
          throw ArgumentError(
            'The built-in Debt category name is fixed. You can change its icon and color.',
          );
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
        rule.month < 1 ||
        rule.month > 12 ||
        rule.reminderMinutes < 0 ||
        rule.reminderMinutes > 1439 ||
        (rule.frequency == RecurrenceFrequency.week && rule.day > 7) ||
        rule.nextDate !=
            firstRecurringDate(
              rule.nextDate,
              rule.frequency,
              rule.day,
              rule.month,
            ) ||
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
            ? "id = ? AND COALESCE(base_currency, currency) = ?"
            : "id = ? AND available = 1 AND COALESCE(base_currency, currency) = ?",
        whereArgs: [rule.accountId, currency.name],
      );
      if (accounts.isEmpty) {
        throw ArgumentError(
          'Choose an unblocked payment account in the selected currency.',
        );
      }
      final account = Account.fromMap(accounts.single);
      if (rule.currency != null &&
          rule.currency != currency &&
          rule.currency != account.currency) {
        throw ArgumentError(
          'Choose the app or account currency for this recurring payment.',
        );
      }
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
            'next_date': dayKey(
              firstRecurringDate(now, rule.frequency, rule.day, rule.month),
            ),
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
        _fromInput(
          type: occurrence.type,
          inputAmount: occurrence.amount,
          inputCurrency: occurrence.currency ?? currency,
          source: account,
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
    } catch (e) {
      if (e is! ArgumentError && e is! FormatException) rethrow;
      await txn.execute('ROLLBACK TO recurring_post');
      await txn.execute('RELEASE recurring_post');
      await txn.update(
        'recurring_occurrences',
        {
          'error': e is ArgumentError
              ? '${e.message}'
              : (e as FormatException).message,
        },
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
            'currency': rule.currency?.name,
            'category': rule.category,
            'account_id': rule.accountId,
            'status': 'failed',
            'manual': rule.automatic ? 0 : 1,
          });
          if (rule.automatic) await _postOccurrence(txn, id);
        }
        final next = nextRecurringDate(
          due,
          rule.frequency,
          rule.interval,
          rule.day,
          rule.month,
        );
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
      where: "id = ? AND status = 'failed' AND manual = 0",
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
