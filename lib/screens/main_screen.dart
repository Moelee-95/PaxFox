import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/presentation/ledger_refresh.dart';
import '../core/presentation/main_drawer.dart';
import '../core/presentation/transaction_tile.dart';
import '../core/presentation/transaction_menu.dart';
import '../features/receipts/invoice.dart';
import '../features/receipts/invoice_review_screen.dart';
import '../features/receipts/invoice_scan_screen.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';
import 'csv_screen.dart';
import 'freedom_screen.dart';
import 'home_screen.dart';
import 'overview_screen.dart';
import 'recurring_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transaction_bulk_editor.dart';
import 'transaction_form.dart';
import 'transactions_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  final _addButtonKey = GlobalKey();
  bool _checkingRecurring = false;
  String? _recurringError;
  final Set<int> _selectedIds = {};
  bool _bulkBusy = false;
  int _homeTab = 0;
  int _navigationIndex = 0;
  double _swipeStartPage = 0;
  bool _showReports = false;
  bool _showTransactions = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _searchQuery = '';
  EntryType? _entryType;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRecurring();
  }

  @override
  void dispose() {
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkRecurring();
    }
  }

  Future<void> _checkRecurring() async {
    final today = dateOnly(DateTime.now());
    if (_checkingRecurring ||
        !widget.store.recurringRules.any(
          (rule) => rule.active && !rule.nextDate.isAfter(today),
        )) {
      return;
    }
    _checkingRecurring = true;
    try {
      await widget.store.processRecurring();
      if (mounted) {
        setState(() => _recurringError = null);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _recurringError = 'Scheduled payments could not be checked. Open Recurring to retry.',
        );
      }
    } finally {
      _checkingRecurring = false;
    }
  }

  void _openRecurring() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RecurringScreen(store: widget.store),
    ),
  );
  void _toggleSelection(LedgerEntry entry) => setState(() {
    if (!_selectedIds.add(entry.id!)) _selectedIds.remove(entry.id);
  });

  Future<void> _createTransaction() async {
    final button =
        _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final action = await showTransactionMenu(
      context,
      anchor: button.localToGlobal(Offset.zero) & button.size,
    );
    if (!mounted || action == null) return;
    if (action == TransactionCreation.manual) {
      await _editTransaction();
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => InvoiceScanScreen(
          store: widget.store,
          initialGallery: action == TransactionCreation.gallery,
        ),
      ),
    );
    if (saved == true && mounted) _goHome();
  }

  Future<void> _editTransaction([LedgerEntry? entry]) async {
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
        _goHome();
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

  void _goHome() {
    setState(() {
      _showReports = false;
      _showTransactions = false;
      _navigationIndex = 0;
      _month = DateTime(DateTime.now().year, DateTime.now().month);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
  }

  void _openMenu(MainMenuDestination destination) {
    Navigator.pop(context);
    if (destination == MainMenuDestination.home) {
      setState(() {
        _showReports = false;
        _showTransactions = false;
        _navigationIndex = 0;
        _selectedIds.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
      return;
    }
    if (destination == MainMenuDestination.transactions) {
      setState(() {
        _showTransactions = true;
        _showReports = false;
        _selectedIds.clear();
      });
      return;
    }
    if (destination == MainMenuDestination.reports) {
      setState(() {
        _showReports = true;
        _showTransactions = false;
        _selectedIds.clear();
      });
      return;
    }
    final screen = switch (destination) {
      MainMenuDestination.categories => CategoriesScreen(store: widget.store),
      MainMenuDestination.accounts => AccountsScreen(store: widget.store),
      MainMenuDestination.settings => SettingsScreen(store: widget.store),
      MainMenuDestination.csv => CsvScreen(store: widget.store),
      MainMenuDestination.recurring => RecurringScreen(store: widget.store),
      _ => throw StateError('Unsupported menu destination: $destination'),
    };
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  List<LedgerEntry> _visibleEntries() {
    if (!_showTransactions && _navigationIndex == 0) {
      final summary = widget.store.monthSummary(_month);
      return _homeTab == 1 ? summary.incomeEntries : summary.spendingEntries;
    }
    return widget.store.searchEntries(query: _searchQuery, type: _entryType);
  }

  void _changeMonth(DateTime value) => setState(() {
    _month = value;
    _selectedIds.clear();
  });

  Widget _transactionTile(LedgerEntry entry, {bool compact = false}) =>
      TransactionTile(
        key: ValueKey(entry.id),
        entry: entry,
        categoryIcon: widget.store.iconFor(entry),
        compact: compact,
        selected: _selectedIds.contains(entry.id),
        selectionMode: _selectedIds.isNotEmpty,
        onLongPress: _bulkBusy ? null : () => _toggleSelection(entry),
        onTap: _bulkBusy
            ? null
            : () => _selectedIds.isEmpty
                  ? _editTransaction(entry)
                  : _toggleSelection(entry),
      );

  List<Widget> _selectionActions() => [
    IconButton(
      tooltip: 'Select all visible',
      onPressed: _bulkBusy
          ? null
          : () => setState(() {
              _selectedIds.addAll(_visibleEntries().map((e) => e.id!));
            }),
      icon: const Icon(Icons.select_all),
    ),
    PopupMenuButton<TransactionBulkAction>(
      tooltip: 'Transaction actions',
      enabled: !_bulkBusy,
      onSelected: _applyBulkAction,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: TransactionBulkAction.category,
          child: Text('Change category'),
        ),
        PopupMenuItem(
          value: TransactionBulkAction.account,
          child: Text('Change account'),
        ),
        PopupMenuItem(
          value: TransactionBulkAction.delete,
          child: Text('Delete selected'),
        ),
      ],
    ),
  ];

  Future<void> _applyBulkAction(TransactionBulkAction action) async {
    final ids = {..._selectedIds};
    try {
      final updated = await TransactionBulkEditor(widget.store).apply(
        context,
        action,
        ids,
        onSaving: () => setState(() => _bulkBusy = true),
      );
      if (updated && mounted) {
        setState(_selectedIds.clear);
        _showMessage('${ids.length} transactions updated.');
      }
    } on ArgumentError catch (error) {
      if (mounted) _showMessage('${error.message}');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'Could not update the selected transactions. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final summary = widget.store.monthSummary(_month);
      return PopScope(
        canPop:
            !_showReports &&
            !_showTransactions &&
            _selectedIds.isEmpty &&
            !_bulkBusy,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _selectedIds.isNotEmpty && !_bulkBusy) {
            setState(_selectedIds.clear);
          } else if (!didPop && (_showReports || _showTransactions)) {
            setState(() {
              _showReports = false;
              _showTransactions = false;
            });
          }
        },
        child: Scaffold(
          appBar: AppBar(
            bottom: _bulkBusy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(2),
                    child: LinearProgressIndicator(),
                  )
                : null,
            actions: _selectedIds.isNotEmpty ? _selectionActions() : null,
            title: Text(
              _selectedIds.isNotEmpty
                  ? '${_selectedIds.length} selected'
                  : _showTransactions
                  ? 'All transactions'
                  : _showReports
                  ? 'Reports'
                  : _navigationIndex == 1
                  ? 'Overview'
                  : 'Moneva',
            ),
            leading: _selectedIds.isNotEmpty
                ? IconButton(
                    tooltip: 'Cancel selection',
                    onPressed: _bulkBusy
                        ? null
                        : () => setState(_selectedIds.clear),
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
          drawer: MainDrawer(
            onSelected: _openMenu,
            showReports: _showReports,
            showTransactions: _showTransactions,
          ),
          body: LedgerRefresh(
            store: widget.store,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: IndexedStack(
                  index: _showTransactions
                      ? 2
                      : _showReports
                      ? 1
                      : 0,
                  children: [
                    TickerMode(
                      enabled: !_showReports && !_showTransactions,
                      child: NotificationListener<ScrollStartNotification>(
                        onNotification: (notification) {
                          if (notification.depth == 0 &&
                              notification.dragDetails != null) {
                            _swipeStartPage =
                                _pageController.page?.roundToDouble() ??
                                _navigationIndex.toDouble();
                          }
                          return false;
                        },
                        child: PageView.builder(
                          key: const ValueKey('main-pages'),
                          controller: _pageController,
                          onPageChanged: (index) => setState(() {
                            _navigationIndex = index;
                            _selectedIds.clear();
                          }),
                          itemCount: 3,
                          pageSnapping: false,
                          physics: _ShortSwipePagePhysics(
                            startPage: () => _swipeStartPage,
                          ),
                          itemBuilder: (context, index) => switch (index) {
                            0 => HomeScreen(
                              currency: widget.store.currency,
                              month: _month,
                              summary: summary,
                              tab: _homeTab,
                              onTabChanged: (tab) => setState(() {
                                _homeTab = tab;
                                _selectedIds.clear();
                              }),
                              onMonthChanged: _changeMonth,
                              tileBuilder: (entry) =>
                                  _transactionTile(entry, compact: true),
                            ),
                            1 => OverviewScreen(
                              store: widget.store,
                              month: _month,
                              summary: summary,
                              recurringError: _recurringError,
                              onOpenRecurring: _openRecurring,
                            ),
                            2 => FreedomScreen(store: widget.store),
                            _ => throw StateError('Unknown page'),
                          },
                        ),
                      ),
                    ),
                    // Preserve pager state beneath drawer destinations.
                    if (!_showReports) const SizedBox.shrink(),
                    if (_showReports)
                      ReportsScreen(
                        month: _month,
                        summary: summary,
                        onMonthChanged: _changeMonth,
                        hasLegacyCurrencyData:
                            widget.store.hasLegacyCurrencyData,
                      ),
                    if (_showTransactions)
                      TransactionsScreen(
                        entries: widget.store.searchEntries(
                          query: _searchQuery,
                          type: _entryType,
                        ),
                        search: _searchQuery,
                        type: _entryType,
                        onSearchChanged: (value) => setState(() {
                          _searchQuery = value;
                          _selectedIds.clear();
                        }),
                        onTypeChanged: (value) => setState(() {
                          _entryType = value;
                          _selectedIds.clear();
                        }),
                        tileBuilder: _transactionTile,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: _selectedIds.isNotEmpty
              ? null
              : FloatingActionButton(
                  key: _addButtonKey,
                  onPressed: _createTransaction,
                  tooltip: 'Add transaction',
                  child: const Icon(Icons.add),
                ),
          bottomNavigationBar: _showReports || _showTransactions
              ? null
              : NavigationBar(
                  selectedIndex: _navigationIndex,
                  onDestinationSelected: (index) {
                    _pageController.jumpToPage(index);
                    setState(() {
                      _selectedIds.clear();
                      _navigationIndex = index;
                      _showReports = false;
                      _showTransactions = false;
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
                  ],
                ),
        ),
      );
    },
  );
}

// The start page is captured before onPageChanged changes the selected tab.
// Disabling PageView's default snap physics lets this shorter threshold apply.
class _ShortSwipePagePhysics extends PageScrollPhysics {
  const _ShortSwipePagePhysics({required this.startPage, super.parent});
  final double Function() startPage;
  @override
  _ShortSwipePagePhysics applyTo(ScrollPhysics? ancestor) =>
      _ShortSwipePagePhysics(
        startPage: startPage,
        parent: buildParent(ancestor),
      );
  @override
  double get minFlingDistance => 12;
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (position is! PageMetrics ||
        position.page == null ||
        (position.page! - position.page!.round()).abs() < 0.000001 ||
        position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final start = startPage();
    final delta = position.page! - start;
    if (delta.abs() >= 0.08 && velocity.abs() < 300) {
      final target = ((start + delta.sign) * position.viewportDimension).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((target - position.pixels).abs() < toleranceFor(position).distance) {
        return null;
      }
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: toleranceFor(position),
      );
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
