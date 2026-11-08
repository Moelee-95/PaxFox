import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../core/data/ledger_store.dart';
import '../core/data/recurring_notifications.dart';
import '../core/domain/ledger.dart';
import '../core/domain/number_format.dart';
import '../core/presentation/ledger_refresh.dart';
import '../core/presentation/app_sheet.dart';
import '../core/presentation/busy_label.dart';
import '../core/presentation/retained_page.dart';
import '../core/presentation/transaction_tile.dart';
import '../core/presentation/transaction_menu.dart';
import '../features/receipts/invoice.dart';
import '../features/receipts/invoice_review_screen.dart';
import '../features/receipts/invoice_scan_screen.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';
import 'csv_screen.dart';
import 'cashflow_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'overview_screen.dart';
import 'recurring_screen.dart';
import '../core/presentation/floating_navigation_bar.dart';
import 'payment_notifications_screen.dart';
import '../core/presentation/category_icons.dart';
import '../core/domain/category.dart';
import 'settings_screen.dart';
import 'transaction_bulk_editor.dart';
import 'transaction_form.dart';
import 'debt_settlement_form.dart';
import 'transactions_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, required this.store});
  final LedgerStore store;
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  Drag? _homeEdgeDrag;
  final _addButtonKey = GlobalKey();
  Timer? _exitTimer;
  Timer? _deadlineTimer;
  bool _checkingRecurring = false;
  String? _recurringError;
  final Set<int> _selectedIds = {};
  bool _bulkBusy = false;
  bool _openingTransaction = false;
  bool _notificationsOpen = false;
  final _notificationFocus = ValueNotifier<int?>(null);
  int _homeTab = 0;
  String? _homeCategory;
  int _navigationIndex = 0;
  double _swipeStartPage = 0;
  bool _showTransactions = false;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String _searchQuery = '';
  EntryType? _entryType;

  // Shell navigation never rebuilds page contents. Each page listens only to
  // data and local view changes, and is retained after its first visit.
  final _homeChanges = ValueNotifier(0);
  final _filterChanges = ValueNotifier(0);
  final _selectionChanges = ValueNotifier(0);
  final _recurringChanges = ValueNotifier(0);
  late final _mainPages = <Widget>[
    RetainedPage(
      child: ListenableBuilder(
        listenable: Listenable.merge([
          widget.store,
          _homeChanges,
          _selectionChanges,
        ]),
        builder: _buildHome,
      ),
    ),
    RetainedPage(
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.store, _recurringChanges]),
        builder: (_, _) => OverviewScreen(
          store: widget.store,
          recurringError: _recurringError,
          onOpenRecurring: _openRecurring,
        ),
      ),
    ),
    const CashflowScreen(),
    RetainedPage(
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (_, _) =>
            MoreScreen(store: widget.store, onSelected: _openMenu),
      ),
    ),
  ];
  late final _transactions = ListenableBuilder(
    listenable: Listenable.merge([
      widget.store,
      _filterChanges,
      _selectionChanges,
    ]),
    builder: (_, _) => TransactionsScreen(
      entries: widget.store.searchEntries(
        query: _searchQuery,
        type: _entryType,
      ),
      search: _searchQuery,
      type: _entryType,
      onSearchChanged: (value) => _changeFilter(() => _searchQuery = value),
      onTypeChanged: (value) => _changeFilter(() => _entryType = value),
      tileBuilder: (entry) => _transactionTile(entry, compact: true),
      invoiceGroups: widget.store.invoiceGroups,
    ),
  );

  void _clearSelection() {
    if (_selectedIds.isEmpty) return;
    _selectedIds.clear();
    _selectionChanges.value++;
  }

  void _changeSelection(VoidCallback update) {
    setState(update);
    _selectionChanges.value++;
  }

  void _changeHome(VoidCallback update) {
    setState(() {
      update();
      _clearSelection();
    });
    _homeChanges.value++;
  }

  void _changeFilter(VoidCallback update) {
    update();
    if (_selectedIds.isNotEmpty) setState(_clearSelection);
    _filterChanges.value++;
  }

  void _setBulkBusy(bool value) {
    if (_bulkBusy != value) _changeSelection(() => _bulkBusy = value);
  }

  void _onPageChanged(int index) {
    if (_navigationIndex == index) return;
    _exitTimer?.cancel();
    setState(() {
      _navigationIndex = index;
      _clearSelection();
    });
  }

  void _selectPage(int index) {
    _homeEdgeDrag?.cancel();
    _homeEdgeDrag = null;
    _exitTimer?.cancel();
    if (_showTransactions ||
        _navigationIndex != index ||
        _selectedIds.isNotEmpty) {
      setState(() {
        _showTransactions = false;
        _navigationIndex = index;
        _clearSelection();
      });
    }
    if (_pageController.hasClients) _pageController.jumpToPage(index);
  }

  Widget _buildHome(BuildContext context, Widget? _) => HomeScreen(
    categoryColor: (name) {
      final value = widget.store.categoryFor(name, EntryType.expense)?.color;
      return value == null ? null : Color(value);
    },
    categoryIcon: (name) => categoryIconData(
      widget.store.categoryFor(name, EntryType.expense)?.icon ??
          CategoryIcon.general,
    ),
    currency: widget.store.currency,
    month: _month,
    summary: widget.store.monthSummary(_month),
    tab: _homeTab,
    selectedCategory: _homeCategory,
    onCategoryChanged: (value) => _changeHome(() => _homeCategory = value),
    onTabChanged: (value) => _changeHome(() {
      _homeTab = value;
      _homeCategory = null;
    }),
    onMonthChanged: _changeMonth,
    tileBuilder: (entry) => _transactionTile(entry, compact: true),
    invoiceGroups: widget.store.invoiceGroups,
    onOverviewDragStart: (details) {
      _homeEdgeDrag?.cancel();
      _exitTimer?.cancel();
      _swipeStartPage = 0;
      _homeEdgeDrag = _pageController.position.drag(
        details,
        () => _homeEdgeDrag = null,
      );
    },
    onOverviewDragUpdate: (details) => _homeEdgeDrag?.update(details),
    onOverviewDragEnd: (details) {
      final drag = _homeEdgeDrag;
      _homeEdgeDrag = null;
      drag?.end(details);
    },
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRecurring();
    _deadlineTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    RecurringNotifications.instance?.message.addListener(_reminderMessage);
    RecurringNotifications.instance?.occurrenceToOpen.addListener(
      _openReminder,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reminderMessage();
      _openReminder();
    });
  }

  void _openReminder() {
    final reminders = RecurringNotifications.instance;
    final id = reminders?.occurrenceToOpen.value;
    if (!mounted || id == null) return;
    reminders!.occurrenceToOpen.value = null;
    if (_notificationFocus.value == id) _notificationFocus.value = null;
    _notificationFocus.value = id;
    _openNotifications();
  }

  Future<void> _openNotifications() async {
    if (_notificationsOpen || !mounted) return;
    _notificationsOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaymentNotificationsScreen(
            store: widget.store,
            focusedOccurrence: _notificationFocus,
            takeDebtAction: () {
              final n = RecurringNotifications.instance;
              final action = n?.debtAction;
              if (n != null) n.debtAction = null;
              return action;
            },
          ),
        ),
      );
    } finally {
      _notificationsOpen = false;
      if (mounted) _notificationFocus.value = null;
    }
  }

  void _reminderMessage() {
    final value = RecurringNotifications.instance?.message.value;
    if (value != null && mounted) {
      RecurringNotifications.instance?.message.value = null;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  void dispose() {
    RecurringNotifications.instance?.message.removeListener(_reminderMessage);
    RecurringNotifications.instance?.occurrenceToOpen.removeListener(
      _openReminder,
    );
    _exitTimer?.cancel();
    _homeEdgeDrag?.cancel();
    _deadlineTimer?.cancel();
    _pageController.dispose();
    _homeChanges.dispose();
    _filterChanges.dispose();
    _selectionChanges.dispose();
    _recurringChanges.dispose();
    _notificationFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _exitTimer?.cancel();
      _checkRecurring();
      RecurringNotifications.instance?.sync();
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
    setState(() => _checkingRecurring = true);
    try {
      await widget.store.processRecurring();
      if (mounted) {
        if (_recurringError != null) {
          _recurringError = null;
          _recurringChanges.value++;
        }
      }
    } catch (_) {
      if (mounted) {
        _recurringError =
            'Scheduled payments could not be checked. Open Recurring to retry.';
        _recurringChanges.value++;
      }
    } finally {
      if (mounted) setState(() => _checkingRecurring = false);
    }
  }

  void _openRecurring() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => RecurringScreen(store: widget.store),
    ),
  );
  void _toggleSelection(LedgerEntry entry) => _changeSelection(() {
    if (!_selectedIds.add(entry.id!)) _selectedIds.remove(entry.id);
  });

  Future<void> _createTransaction() async {
    _exitTimer?.cancel();
    final button =
        _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) return;
    final action = await showTransactionMenu(
      context,
      anchor: button.localToGlobal(Offset.zero) & button.size,
    );
    if (!mounted || action == null) return;
    if (action.action == TransactionCreation.manual) {
      await _editTransaction(initialType: action.type);
      return;
    }
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => InvoiceScanScreen(
          store: widget.store,
          type: action.type,
          initialUpload: action.action == TransactionCreation.upload,
          initialGallery: action.action == TransactionCreation.gallery,
          onSavedDate: (date) => _month = DateTime(date.year, date.month),
        ),
      ),
    );
    if (saved == true && mounted) _goHome(type: action.type);
  }

  Future<void> _editTransaction({
    LedgerEntry? entry,
    EntryType initialType = EntryType.expense,
  }) async {
    if (_openingTransaction) return;
    _exitTimer?.cancel();
    try {
      if (entry?.id != null &&
          widget.store.receiptTransactionIds.contains(entry!.id)) {
        setState(() => _openingTransaction = true);
      }
      final feePrincipal = widget.store.debtFeeLinks[entry?.id];
      if (feePrincipal != null) {
        entry = widget.store.entries.firstWhere((e) => e.id == feePrincipal);
      }
      final debtId = widget.store.debtPaymentLinks[entry?.id];
      final debt = widget.store.debts.where((d) => d.id == debtId).firstOrNull;
      if (entry != null && debt != null) {
        await showAppSheet<bool>(
          context,
          editor: true,
          builder: (_) => DebtSettlementForm(
            store: widget.store,
            debt: debt,
            entry: entry,
            onSavedDate: (date) => _goHome(date: date),
          ),
        );
        return;
      }
      final receipt =
          entry?.id == null ||
              !widget.store.receiptTransactionIds.contains(entry!.id)
          ? null
          : await widget.store.receiptFor(entry.id!);
      if (!mounted) {
        return;
      }
      if (_openingTransaction) setState(() => _openingTransaction = false);
      var savedType = initialType;
      var savedDate = entry?.date ?? _month;
      final saved = receipt == null
          ? await showAppSheet<bool>(
              context,
              editor: true,
              builder: (_) => TransactionForm(
                store: widget.store,
                entry: entry,
                initialType: initialType,
                onSavedType: (type) => savedType = type,
                onSavedDate: (date) => savedDate = date,
                initialDate:
                    _month.year == DateTime.now().year &&
                        _month.month == DateTime.now().month
                    ? dateOnly(DateTime.now())
                    : DateTime(_month.year, _month.month),
              ),
            )
          : await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => InvoiceReviewScreen(
                  store: widget.store,
                  entry: entry,
                  onSavedDate: (date) => savedDate = date,
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
        _goHome(type: entry == null ? savedType : null, date: savedDate);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open transaction. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted && _openingTransaction) {
        setState(() => _openingTransaction = false);
      }
    }
  }

  void _goHome({EntryType? type, DateTime? date}) {
    _changeHome(() {
      if (date != null) _month = DateTime(date.year, date.month);
      if (type != null) {
        _homeTab = type == EntryType.income ? 1 : 0;
        _homeCategory = null;
      }
    });
    _selectPage(0);
  }

  void _openMenu(MoreDestination destination) {
    _exitTimer?.cancel();
    if (destination == MoreDestination.transactions) {
      setState(() {
        _showTransactions = true;
        _clearSelection();
      });
      return;
    }
    final screen = switch (destination) {
      MoreDestination.categories => CategoriesScreen(store: widget.store),
      MoreDestination.accounts => AccountsScreen(store: widget.store),
      MoreDestination.settings => SettingsScreen(store: widget.store),
      MoreDestination.csv => CsvScreen(store: widget.store),
      MoreDestination.recurring => RecurringScreen(store: widget.store),
      _ => throw StateError('Unsupported menu destination: $destination'),
    };
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  List<LedgerEntry> _visibleEntries() {
    if (!_showTransactions && _navigationIndex == 0) {
      final summary = widget.store.monthSummary(_month);
      if (_homeTab == 2) {
        return _homeCategory == null
            ? const []
            : summary.spendingForCategory(
                widget.store.currency,
                _homeCategory!,
              );
      }
      return _homeTab == 1 ? summary.incomeEntries : summary.spendingEntries;
    }
    return widget.store.searchEntries(query: _searchQuery, type: _entryType);
  }

  void _changeMonth(DateTime value) => _changeHome(() {
    _month = value;
    _homeCategory = null;
  });

  Widget _transactionTile(LedgerEntry entry, {bool compact = false}) =>
      TransactionTile(
        key: ValueKey(entry.id),
        entry: entry,
        categoryIcon: widget.store.iconFor(entry),
        categoryColor: switch (widget.store.colorFor(entry)) {
          final value? => Color(value),
          null => null,
        },
        compact: compact,
        selected: _selectedIds.contains(entry.id),
        selectionMode: _selectedIds.isNotEmpty,
        onLongPress: _bulkBusy ? null : () => _toggleSelection(entry),
        onTap: _bulkBusy
            ? null
            : () => _selectedIds.isEmpty
                  ? _editTransaction(entry: entry)
                  : _toggleSelection(entry),
      );

  List<Widget> _selectionActions() => [
    IconButton(
      tooltip: 'Select all visible',
      onPressed: _bulkBusy
          ? null
          : () => _changeSelection(() {
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
      final updated = await TransactionBulkEditor(widget.store)
          .apply(context, action, ids, onSaving: () => _setBulkBusy(true));
      if (updated && mounted) {
        _changeSelection(_selectedIds.clear);
        _showMessage('${formatInteger(ids.length)} transactions updated.');
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
      if (mounted) _setBulkBusy(false);
    }
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _selectedIds.isNotEmpty && !_bulkBusy) {
        _changeSelection(_selectedIds.clear);
        _exitTimer?.cancel();
      } else if (!didPop && _showTransactions) {
        setState(() {
          _showTransactions = false;
        });
        _exitTimer?.cancel();
      } else if (!didPop &&
          !_bulkBusy &&
          _navigationIndex == 0 &&
          _homeTab == 2 &&
          _homeCategory != null) {
        _changeHome(() => _homeCategory = null);
        _exitTimer?.cancel();
      } else if (!didPop && !_bulkBusy) {
        if (_exitTimer?.isActive == true) {
          _exitTimer?.cancel();
          SystemNavigator.pop();
        } else {
          _exitTimer = Timer(const Duration(seconds: 2), () {});
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tap back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    },
    child: Scaffold(
      appBar: AppBar(
        centerTitle:
            _selectedIds.isEmpty && !_showTransactions && _navigationIndex == 0,
        automaticallyImplyLeading: false,
        bottom: _bulkBusy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
        actions: _selectedIds.isNotEmpty
            ? _selectionActions()
            : [
                if (_openingTransaction || _checkingRecurring)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: BusyLabel(busy: true, label: ''),
                  ),
              ],
        title: Text(
          _selectedIds.isNotEmpty
              ? '${formatInteger(_selectedIds.length)} selected'
              : _showTransactions
              ? 'All transactions'
              : _navigationIndex == 1
              ? 'Overview'
              : _navigationIndex == 2
              ? 'Cashflow'
              : _navigationIndex == 3
              ? 'More'
              : 'PaxFox',
        ),
        leading: _selectedIds.isNotEmpty
            ? IconButton(
                tooltip: 'Cancel selection',
                onPressed: _bulkBusy
                    ? null
                    : () => _changeSelection(_selectedIds.clear),
                icon: const Icon(Icons.close),
              )
            : _showTransactions
            ? BackButton(
                onPressed: () => setState(() {
                  _showTransactions = false;
                  _exitTimer?.cancel();
                }),
              )
            : ListenableBuilder(
                listenable: widget.store,
                builder: (context, _) {
                  final count =
                      (pendingPaymentNotifications(widget.store).length +
                      widget.store.dueDebts().length);
                  return IconButton(
                    tooltip: 'Notifications',
                    onPressed: _openNotifications,
                    icon: Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  );
                },
              ),
      ),
      body: LedgerRefresh(
        store: widget.store,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: IndexedStack(
              index: _showTransactions ? 1 : 0,
              children: [
                TickerMode(
                  enabled: !_showTransactions,
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
                      onPageChanged: _onPageChanged,
                      itemCount: 4,
                      pageSnapping: false,
                      physics: _ShortSwipePagePhysics(
                        startPage: () => _swipeStartPage,
                      ),
                      itemBuilder: (_, index) => TickerMode(
                        enabled:
                            !_showTransactions && _navigationIndex == index,
                        child: _mainPages[index],
                      ),
                    ),
                  ),
                ),
                if (_showTransactions)
                  _transactions
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton:
          _selectedIds.isNotEmpty ||
              (!_showTransactions && _navigationIndex == 3)
          ? null
          : FloatingActionButton(
              key: _addButtonKey,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: .78),
              elevation: 1,
              onPressed: _createTransaction,
              tooltip: 'Add transaction',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _showTransactions
          ? null
          : FloatingNavigationBar(
              selectedIndex: _navigationIndex,
              onSelected: _selectPage,
            ),
    ),
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
