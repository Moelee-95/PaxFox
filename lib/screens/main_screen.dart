import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/category.dart';
import '../core/presentation/category_icons.dart';
import 'transaction_form.dart';
import 'accounts_screen.dart';
import 'freedom_screen.dart';
import 'categories_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import '../features/receipts/invoice.dart';
import '../features/receipts/invoice_scan_screen.dart';
import '../features/receipts/invoice_review_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final PageController _pages = PageController();
  bool checkingRecurring = false;
  String? recurringError;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkRecurring();
  }

  @override
  void dispose() {
    _pages.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkRecurring();
    }
  }

  Future<void> checkRecurring() async {
    if (checkingRecurring ||
        !widget.store.recurringRules.any(
          (r) => r.active && !r.nextDate.isAfter(dateOnly(DateTime.now())),
        )) {
      return;
    }
    checkingRecurring = true;
    try {
      await widget.store.processRecurring();
      if (mounted) {
        setState(() => recurringError = null);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => recurringError = 'Scheduled payments could not be checked. Open Recurring to retry.',
        );
      }
    } finally {
      checkingRecurring = false;
    }
  }

  void recurring() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RecurringScreen(store: widget.store),
    ),
  );
  int _selectedIndex = 0;
  bool showReports = false;
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  String search = '';
  EntryType? type;
  Future<void> edit([LedgerEntry? entry]) async {
    try {
      final receipt =
          entry?.id == null ||
              !widget.store.receiptTransactionIds.contains(entry!.id)
          ? null
          : await widget.store.receiptFor(entry.id!);
      if (!mounted) {
        return;
      }
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => receipt == null
              ? TransactionForm(store: widget.store, entry: entry)
              : InvoiceReviewScreen(
                  store: widget.store,
                  entry: entry,
                  draft: InvoiceDraft.fromMap(
                    jsonDecode(receipt['draft'] as String)
                        as Map<String, dynamic>,
                  ),
                  storedPaths: (jsonDecode(
                    receipt['image_paths'] as String,
                  ) as List).cast<String>(),
                ),
        ),
      );
      if (saved == true && mounted) {
        goHome();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open transaction. Please retry.'),
          ),
        );
      }
    }
  }

  void goHome() {
    setState(() {
      showReports = false;
      _selectedIndex = 0;
      month = DateTime(DateTime.now().year, DateTime.now().month);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pages.hasClients) {
        _pages.jumpToPage(0);
      }
    });
  }

  void accounts() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AccountsScreen(store: widget.store),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final rows = widget.store.entries
          .where(
            (e) => e.date.year == month.year && e.date.month == month.month,
          )
          .toList();
      final totals = <Currency, Totals>{};
      for (final row in rows) {
        (totals[row.currency] ??= Totals()).add(row);
      }
      return PopScope(
        canPop: !showReports,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && showReports) {
            setState(() => showReports = false);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                tooltip: 'Scan invoice',
                icon: const Icon(Icons.document_scanner_outlined),
                onPressed: () async {
                  final saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute<bool>(
                      builder: (_) => InvoiceScanScreen(store: widget.store),
                    ),
                  );
                  if (saved == true && mounted) {
                    goHome();
                  }
                },
              ),
            ],
            title: Text(
              showReports
                  ? 'Reports'
                  : _selectedIndex == 3
                  ? 'Overview'
                  : 'Moneva',
            ),
            leading: Builder(
              builder: (context) => IconButton(
                tooltip: 'Open menu',
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Moneva', style: TextStyle(fontSize: 24)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.home_outlined),
                    title: const Text('Home'),
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        showReports = false;
                        _selectedIndex = 0;
                      });
                      if (_pages.hasClients) {
                        _pages.jumpToPage(0);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.bar_chart),
                    title: const Text('Reports'),
                    selected: showReports,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() => showReports = true);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Categories'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CategoriesScreen(store: widget.store),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Accounts'),
                    onTap: () {
                      Navigator.pop(context);
                      accounts();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => SettingsScreen(store: widget.store),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.event_repeat),
                    title: const Text('Recurring payments'),
                    onTap: () {
                      Navigator.pop(context);
                      recurring();
                    },
                  ),
                ],
              ),
            ),
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: showReports
                  ? reports(rows, totals)
                  : PageView(
                      controller: _pages,
                      onPageChanged: (index) =>
                          setState(() => _selectedIndex = index),
                      children: [
                        dashboard(rows),
                        ledger(),
                        FreedomScreen(store: widget.store),
                        overview(totals),
                      ],
                    ),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => edit(),
            tooltip: 'Add transaction',
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: showReports
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    _pages.jumpToPage(index);
                    setState(() {
                      _selectedIndex = index;
                      showReports = false;
                    });
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: 'Transactions',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.timeline),
                      label: 'Cashflow',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Overview',
                    ),
                  ],
                ),
        ),
      );
    },
  );

  Widget monthPicker() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: 'Previous month',
        onPressed: () =>
            setState(() => month = DateTime(month.year, month.month - 1)),
        icon: const Icon(Icons.chevron_left),
      ),
      Text(
        '${month.year}-${month.month.toString().padLeft(2, '0')}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      IconButton(
        tooltip: 'Next month',
        onPressed: () =>
            setState(() => month = DateTime(month.year, month.month + 1)),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget summary(Map<Currency, Totals> totals) => Column(
    children: [
      if (widget.store.hasLegacyCurrencyData)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Existing non-EUR data is retained locally and excluded from this EUR-only version. No conversion has been applied.',
          ),
        ),
      if (totals.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No transactions in this month. Add your first expense or income.',
          ),
        ),
      for (final entry in totals.entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key.code,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Income: ${entry.key.format(entry.value.income)}'),
                Text(
                  'Spending after refunds: ${entry.key.format(entry.value.spending)}',
                ),
                Text('Net cashflow: ${entry.key.format(entry.value.net)}'),
              ],
            ),
          ),
        ),
    ],
  );

  Widget homeOverview(Map<Currency, Totals> totals) {
    final monthly = totals[Currency.eur] ?? Totals();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final wealth = widget.store.accounts.fold<int>(
      0,
      (total, a) => total + accountBalance(a, widget.store.entries, now),
    );
    final available = widget.store.accounts
        .where((a) => a.available)
        .fold<int>(
          0,
          (total, a) => total + accountBalance(a, widget.store.entries, now),
        );
    final blocked = wealth - available;
    Widget metric(String text, IconData icon, Color color, {String? detail}) =>
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 8),
              Text(
                text,
                style: theme.textTheme.titleSmall?.copyWith(height: 1.5),
              ),
              if (detail != null) ...[
                const SizedBox(height: 4),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
    Widget pair(Widget left, Widget right) => LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 10), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Monthly overview',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Text(
                    '${month.year}-${month.month.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Net cashflow: ${Currency.eur.format(monthly.net)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'EUR ? Income minus spending after refunds',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        pair(
          metric(
            'Income: ${Currency.eur.format(monthly.income)}',
            Icons.payments_outlined,
            Colors.green,
          ),
          metric(
            'Spending after refunds: ${Currency.eur.format(monthly.spending)}',
            Icons.shopping_bag_outlined,
            Colors.red,
          ),
        ),
        const SizedBox(height: 10),
        pair(
          metric(
            'Account wealth: EUR ${Currency.eur.format(wealth)}',
            Icons.account_balance_outlined,
            colors.primary,
          ),
          metric(
            'Available to spend: EUR ${Currency.eur.format(available)}',
            Icons.account_balance_wallet_outlined,
            colors.primary,
            detail:
                'Excludes blocked accounts: EUR ${Currency.eur.format(blocked)}',
          ),
        ),
        if (widget.store.hasLegacyCurrencyData)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Existing non-EUR data is preserved and excluded from these totals.',
            ),
          ),
      ],
    );
  }

  Widget overview(Map<Currency, Totals> totals) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
    children: [
      homeOverview(totals),
      if (recurringError != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(recurringError!),
        ),
      const SizedBox(height: 20),
      if (widget.store.recurringOccurrences.any((o) => o.status == 'failed'))
        TextButton(
          onPressed: recurring,
          child: const Text('Review unpaid recurring payments'),
        ),
      Text(
        'Account balances today',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (widget.store.accounts.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'No accounts configured. Add an opening balance to track available cash.',
          ),
        ),
      if (widget.store.accounts.isNotEmpty)
        SizedBox(
          height: 128 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.store.accounts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final account = widget.store.accounts[index];
              final balance = accountBalance(
                account,
                widget.store.entries,
                DateTime.now(),
              );
              return SizedBox(
                width: 184,
                child: Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              !account.available
                                  ? Icons.lock_outline
                                  : account.kind == AccountKind.cash
                                  ? Icons.payments_outlined
                                  : Icons.account_balance_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Tooltip(
                                message: account.name,
                                child: Text(
                                  account.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${account.currency.code} ${account.currency.format(balance)}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: balance < 0
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                          ),
                        ),
                        Text(
                          !account.available
                              ? 'Blocked'
                              : account.kind == AccountKind.cash
                              ? 'Cash'
                              : 'Bank',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );

  Widget dashboard(List<LedgerEntry> rows) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
    children: [
      monthPicker(),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No transactions in this month. Tap + to add one.'),
        ),
      for (final entry in rows) tile(entry),
    ],
  );

  Widget tile(LedgerEntry e) => ListTile(
    onTap: () => edit(e),
    leading: Icon(
      e.type == EntryType.transfer
          ? Icons.account_balance_outlined
          : categoryIconData(
              widget.store.categories
                      .where(
                        (c) =>
                            c.kind == categoryKind(e.type) &&
                            c.name == e.category,
                      )
                      .firstOrNull
                      ?.icon ??
                  CategoryIcon.general,
            ),
      color: transactionColor(e.type),
      semanticLabel:
          '${e.type.name} - ${e.type == EntryType.transfer ? 'Transfer' : e.category}',
    ),
    title: Text(e.description),
    subtitle: Text('${dayKey(e.date)} · ${e.type.name} · ${e.category}'),
    trailing: Text('${e.currency.code} ${e.currency.format(e.amount)}'),
  );

  Widget ledger() {
    final filtered = widget.store.entries
        .where(
          (e) =>
              (type == null || e.type == type) &&
              '${e.description} ${e.notes} ${e.category}'
                  .toLowerCase()
                  .contains(search.toLowerCase()),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search description, category or notes',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (s) => setState(() => search = s),
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<EntryType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('All types'),
                        ),
                        ...EntryType.values.map(
                          (t) =>
                              DropdownMenuItem(value: t, child: Text(t.name)),
                        ),
                      ],
                      onChanged: (t) => setState(() => type = t),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching transactions.'),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (_, index) => tile(filtered[index]),
          ),
        ),
      ],
    );
  }

  Widget reports(List<LedgerEntry> rows, Map<Currency, Totals> totals) {
    final categories = <String, int>{};
    for (final e in rows) {
      if (e.type == EntryType.expense || e.type == EntryType.refund) {
        final key = '${e.currency.code} · ${e.category}';
        categories[key] =
            (categories[key] ?? 0) +
            (e.type == EntryType.refund ? -e.amount : e.amount);
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        monthPicker(),
        summary(totals),
        const Text('Spending by category', style: TextStyle(fontSize: 22)),
        for (final item in categories.entries)
          ListTile(
            title: Text(item.key),
            trailing: Text(
              Currency.values
                  .firstWhere((c) => item.key.startsWith(c.code))
                  .format(item.value),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Transfers are excluded. Refunds reduce spending. Future-dated entries appear in their selected month.',
          ),
        ),
      ],
    );
  }
}
