import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/category.dart';
import '../core/presentation/category_icons.dart';
import '../core/presentation/month_selector.dart';
import 'transaction_form.dart';
import 'accounts_screen.dart';
import 'freedom_screen.dart';
import 'categories_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import 'csv_screen.dart';
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
    homeTabs?.removeListener(homeTabChanged);
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
  final Set<int> selected = {};
  bool bulkBusy = false;
  int homeTab = 0;
  TabController? homeTabs;
  void homeTabChanged() {
    if (homeTabs != null && homeTab != homeTabs!.index) {
      setState(() {
        homeTab = homeTabs!.index;
        selected.clear();
      });
    }
  }

  void toggleSelection(LedgerEntry entry) => setState(() {
    if (!selected.add(entry.id!)) selected.remove(entry.id);
  });
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

  List<LedgerEntry> visibleEntries() => widget.store.entries.where((e) {
    if (_selectedIndex == 0) {
      return e.date.year == month.year &&
          e.date.month == month.month &&
          (homeTab == 1
              ? e.type == EntryType.income
              : e.type == EntryType.expense || e.type == EntryType.refund);
    }
    return (type == null || e.type == type) &&
        '${e.description} ${e.notes} ${e.category}'.toLowerCase().contains(
          search.toLowerCase(),
        );
  }).toList();

  List<Widget> selectionActions() => [
    IconButton(
      tooltip: 'Select all visible',
      onPressed: bulkBusy
          ? null
          : () => setState(() {
              selected.addAll(visibleEntries().map((e) => e.id!));
            }),
      icon: const Icon(Icons.select_all),
    ),
    PopupMenuButton<String>(
      tooltip: 'Transaction actions',
      enabled: !bulkBusy,
      onSelected: bulkAction,
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'category', child: Text('Change category')),
        PopupMenuItem(value: 'account', child: Text('Change account')),
        PopupMenuItem(value: 'delete', child: Text('Delete selected')),
      ],
    ),
  ];

  Future<void> bulkAction(String action) async {
    final ids = {...selected};
    final entries = widget.store.entries
        .where((e) => ids.contains(e.id))
        .toList();
    String? category;
    int? accountId;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${ids.length} transactions?'),
          content: const Text(
            'This updates spending reports and any linked account balances.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else {
      if (entries.any((e) => e.type == EntryType.transfer)) {
        showBulkError('Edit transfers individually to choose both accounts.');
        return;
      }
      if (action == 'category') {
        if (entries.map((e) => categoryKind(e.type)).toSet().length != 1) {
          showBulkError(
            'Select income separately from expenses and refunds to change categories.',
          );
          return;
        }
        category = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Change category'),
            children: [
              for (final c in widget.store.categoriesFor(entries.first.type))
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, c.name),
                  child: Text(c.name),
                ),
            ],
          ),
        );
        if (category == null) return;
      } else {
        final spending = entries.any((e) => e.type == EntryType.expense);
        final choice = await showDialog<({int? id})>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Change account'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, (id: null)),
                child: const Text('Unassigned (payment unknown)'),
              ),
              for (final a in widget.store.accounts.where(
                (a) => !spending || a.available,
              ))
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, (id: a.id)),
                  child: Text(a.name),
                ),
            ],
          ),
        );
        if (choice == null) return;
        accountId = choice.id;
      }
    }
    if (!mounted) return;
    setState(() => bulkBusy = true);
    try {
      if (action == 'delete') {
        await widget.store.deleteEntries(ids);
      } else {
        await widget.store.updateEntries(
          ids,
          category: category,
          accountId: accountId,
          changeAccount: action == 'account',
        );
      }
      if (mounted) {
        setState(selected.clear);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ids.length} transactions updated.')),
        );
      }
    } on ArgumentError catch (e) {
      if (mounted) showBulkError('${e.message}');
    } catch (_) {
      if (mounted) {
        showBulkError(
          'Could not update the selected transactions. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => bulkBusy = false);
    }
  }

  void showBulkError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

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
        canPop: !showReports && selected.isEmpty && !bulkBusy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && selected.isNotEmpty && !bulkBusy) {
            setState(selected.clear);
          } else if (!didPop && showReports) {
            setState(() => showReports = false);
          }
        },
        child: Scaffold(
          appBar: AppBar(
            bottom: bulkBusy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(2),
                    child: LinearProgressIndicator(),
                  )
                : null,
            actions: selected.isNotEmpty
                ? selectionActions()
                : [
                    IconButton(
                      tooltip: 'Scan invoice',
                      icon: const Icon(Icons.document_scanner_outlined),
                      onPressed: () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute<bool>(
                            builder: (_) =>
                                InvoiceScanScreen(store: widget.store),
                          ),
                        );
                        if (saved == true && mounted) {
                          goHome();
                        }
                      },
                    ),
                  ],
            title: Text(
              selected.isNotEmpty
                  ? '${selected.length} selected'
                  : showReports
                  ? 'Reports'
                  : _selectedIndex == 1
                  ? 'Overview'
                  : 'Moneva',
            ),
            leading: selected.isNotEmpty
                ? IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: bulkBusy ? null : () => setState(selected.clear),
                    icon: const Icon(Icons.close),
                  )
                : Builder(
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
                    leading: const Icon(Icons.import_export),
                    title: const Text('Import & export CSV'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CsvScreen(store: widget.store),
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
                      key: const ValueKey('main-pages'),
                      controller: _pages,
                      onPageChanged: (index) => setState(() {
                        _selectedIndex = index;
                        selected.clear();
                      }),
                      children: [
                        dashboard(rows),
                        overview(totals),
                        FreedomScreen(store: widget.store),
                        ledger(),
                      ],
                    ),
            ),
          ),
          floatingActionButton: selected.isNotEmpty
              ? null
              : FloatingActionButton(
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
                      selected.clear();
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
                      icon: Icon(Icons.dashboard_outlined),
                      label: 'Overview',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.timeline),
                      label: 'Cashflow',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      label: 'Transactions',
                    ),
                  ],
                ),
        ),
      );
    },
  );

  Widget monthPicker() => MonthSelector(
    month: month,
    onChanged: (value) => setState(() {
      month = value;
      selected.clear();
    }),
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
                  entry.key.symbol,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Income: ${entry.key.display(entry.value.income)}'),
                Text(
                  'Spending after refunds: ${entry.key.display(entry.value.spending)}',
                ),
                Text('Net cashflow: ${entry.key.display(entry.value.net)}'),
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
                'Net cashflow: ${Currency.eur.display(monthly.net)}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Income minus spending after refunds',
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
            'Income: ${Currency.eur.display(monthly.income)}',
            Icons.payments_outlined,
            Colors.green,
          ),
          metric(
            'Spending after refunds: ${Currency.eur.display(monthly.spending)}',
            Icons.shopping_bag_outlined,
            Colors.red,
          ),
        ),
        const SizedBox(height: 10),
        pair(
          metric(
            'Account wealth: €${Currency.eur.format(wealth)}',
            Icons.account_balance_outlined,
            colors.primary,
          ),
          metric(
            'Available to spend: €${Currency.eur.format(available)}',
            Icons.account_balance_wallet_outlined,
            colors.primary,
            detail:
                'Excludes blocked accounts: €${Currency.eur.format(blocked)}',
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
                            account.currency.display(balance),
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

  Widget dashboard(List<LedgerEntry> rows) {
    final spending = rows
        .where((e) => e.type == EntryType.expense || e.type == EntryType.refund)
        .toList();
    final income = rows.where((e) => e.type == EntryType.income).toList();
    final totals = Totals();
    for (final e in rows) {
      totals.add(e);
    }
    Widget list(String view, List<LedgerEntry> entries, String empty) =>
        ListView.builder(
          key: PageStorageKey('home-$view-${month.year}-${month.month}'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          itemCount: entries.isEmpty ? 1 : entries.length,
          itemBuilder: (_, index) => entries.isEmpty
              ? Padding(padding: const EdgeInsets.all(20), child: Text(empty))
              : tile(entries[index], compact: true),
        );
    return DefaultTabController(
      length: 2,
      initialIndex: homeTab,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          if (homeTabs != controller) {
            homeTabs?.removeListener(homeTabChanged);
            homeTabs = controller;
            controller.addListener(homeTabChanged);
          }
          return Column(
            children: [
              monthPicker(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TabBar(
                    padding: const EdgeInsets.all(4),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    labelColor: Theme.of(context).colorScheme.onSurface,
                    unselectedLabelColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                    splashBorderRadius: BorderRadius.circular(20),
                    tabs: [
                      for (final tab in [
                        (
                          label: 'Expenses',
                          amount: totals.spending,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.red.shade300
                              : Colors.red.shade700,
                        ),
                        (
                          label: 'Income',
                          amount: totals.income,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.green.shade400
                              : Colors.green.shade700,
                        ),
                      ])
                        Tab(
                          height:
                              48 * MediaQuery.textScalerOf(context).scale(1),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              Text(
                                tab.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                Currency.eur.display(tab.amount),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: tab.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    list(
                      'expenses',
                      spending,
                      'No expenses or refunds in this month. Tap + to add one.',
                    ),
                    list(
                      'income',
                      income,
                      'No income in this month. Tap + to add one.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget tile(LedgerEntry e, {bool compact = false}) => ListTile(
    dense: compact,
    visualDensity: compact ? VisualDensity.compact : null,
    contentPadding: compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
    selected: selected.contains(e.id),
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    onLongPress: bulkBusy ? null : () => toggleSelection(e),
    onTap: bulkBusy
        ? null
        : () => selected.isEmpty ? edit(e) : toggleSelection(e),
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
    subtitle: Text(
      compact
          ? dayKey(e.date)
          : '${dayKey(e.date)} · ${e.type.name} · ${e.category}',
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(e.currency.display(e.amount)),
        if (selected.isNotEmpty) ...[
          const SizedBox(width: 8),
          Icon(
            selected.contains(e.id)
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: selected.contains(e.id)
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ],
      ],
    ),
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
                onChanged: (s) => setState(() {
                  search = s;
                  selected.clear();
                }),
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
                      onChanged: (t) => setState(() {
                        type = t;
                        selected.clear();
                      }),
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
        final key = '${e.currency.symbol} · ${e.category}';
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
                  .firstWhere((c) => item.key.startsWith(c.symbol))
                  .display(item.value),
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
