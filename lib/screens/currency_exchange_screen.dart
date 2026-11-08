import 'package:flutter/material.dart';

import '../core/data/ledger_store.dart';
import '../core/domain/ledger.dart';
import '../core/domain/currency_exchange.dart';
import '../core/presentation/grouped_amount_formatter.dart';

class CurrencyExchangeScreen extends StatefulWidget {
  const CurrencyExchangeScreen({
    super.key,
    required this.store,
    this.initialFrom,
    this.initialTo,
  });
  final Currency? initialFrom, initialTo;
  @override
  State<CurrencyExchangeScreen> createState() => _CurrencyExchangeScreenState();
  final LedgerStore store;
}

class _CurrencyExchangeScreenState extends State<CurrencyExchangeScreen> {
  LedgerStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    if (widget.initialFrom != null && widget.initialTo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog<void>(
            context: context,
            builder: (_) => _RateEditor(
              store: store,
              initialFrom: widget.initialFrom,
              initialTo: widget.initialTo,
            ),
          );
        }
      });
    }
  }

  Future<void> edit(BuildContext context, [String? key]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _RateEditor(store: store, pair: key),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Currency exchange')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => edit(context),
      tooltip: 'Add exchange rate',
      child: const Icon(Icons.add),
    ),
    body: ListenableBuilder(
      listenable: store,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          const Text(
            'Your default rates prefill debt payments and value outstanding balances. You can override a rate when paying. Saved transactions keep their original values. Reverse and cross conversions are calculated automatically.',
          ),
          const SizedBox(height: 16),
          if (store.exchangeTable.rates.isEmpty)
            const Text('No defaults yet. Add a currency pair.'),
          for (final item in store.exchangeTable.rates.entries)
            Card(
              child: ListTile(
                leading: const Icon(Icons.currency_exchange),
                title: Text(
                  '1 ${item.key.split('_').first.toUpperCase()} = ${item.value} ${item.key.split('_').last.toUpperCase()}',
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => edit(context, item.key),
              ),
            ),
        ],
      ),
    ),
  );
}

class _RateEditor extends StatefulWidget {
  const _RateEditor({
    required this.store,
    this.pair,
    this.initialFrom,
    this.initialTo,
  });
  final Currency? initialFrom, initialTo;
  final LedgerStore store;
  final String? pair;
  @override
  State<_RateEditor> createState() => _RateEditorState();
}

class _RateEditorState extends State<_RateEditor> {
  final form = GlobalKey<FormState>();
  late Currency from = widget.pair == null
      ? widget.initialFrom ?? widget.store.currency
      : Currency.values.byName(widget.pair!.split('_').first);
  late Currency to = widget.pair == null
      ? widget.initialTo ?? Currency.values.firstWhere((c) => c != from)
      : Currency.values.byName(widget.pair!.split('_').last);
  late final rate = TextEditingController(
    text: widget.store.exchangeTable.rates[widget.pair] ?? '',
  );
  String? error;
  bool busy = false;
  @override
  void dispose() {
    rate.dispose();
    super.dispose();
  }

  Future<void> save({bool remove = false}) async {
    if (!remove && !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rates = {...widget.store.exchangeTable.rates};
      if (widget.pair != null) rates.remove(widget.pair);
      if (!remove) {
        rates.remove(CurrencyExchangeTable.key(to, from));
        rates[CurrencyExchangeTable.key(from, to)] = ConversionRate.parse(
          rate.text,
        ).text;
      }
      await widget.store.saveExchangeRates(rates);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is ArgumentError
              ? e.message.toString()
              : 'Could not save the rate. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.pair == null ? 'Add exchange rate' : 'Edit exchange rate',
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<Currency>(
                  initialValue: from,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: [
                    for (final c in Currency.values)
                      DropdownMenuItem(value: c, child: Text(c.code)),
                  ],
                  onChanged: busy ? null : (v) => setState(() => from = v!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<Currency>(
                  initialValue: to,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: [
                    for (final c in Currency.values)
                      DropdownMenuItem(value: c, child: Text(c.code)),
                  ],
                  onChanged: busy ? null : (v) => setState(() => to = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: rate,
                  autofocus: widget.initialFrom != null,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [GroupedAmountFormatter()],
                  decoration: InputDecoration(
                    labelText: '1 ${from.code} = X ${to.code}',
                  ),
                  validator: (v) {
                    if (from == to) return 'Choose different currencies.';
                    try {
                      ConversionRate.parse(v ?? '');
                      return null;
                    } on FormatException catch (e) {
                      return e.message;
                    }
                  },
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.pair != null)
          TextButton(
            onPressed: busy ? null : () => save(remove: true),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Saving...' : 'Save'),
        ),
      ],
    ),
  );
}
