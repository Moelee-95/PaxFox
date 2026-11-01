import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/presentation/selection_cards.dart';
import '../core/presentation/entry_type_picker.dart';

import '../core/data/ledger_store.dart';
import '../core/data/transaction_csv.dart';
import '../core/domain/ledger.dart';
import '../core/domain/number_format.dart';
import '../core/presentation/bottom_action_bar.dart';
import '../core/presentation/info_button.dart';

typedef CsvFile = ({String name, Uint8List bytes});

Future<CsvFile?> pickCsvFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csv'],
    dialogTitle: 'Import CSV',
  );
  if (file == null) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    if (bytes.length + chunk.length > TransactionCsv.maxBytes) {
      throw const FormatException('Choose a CSV smaller than 5 MB.');
    }
    bytes.add(chunk);
  }
  return (name: file.name, bytes: bytes.takeBytes());
}

Future<bool> saveCsvFile(String name, Uint8List bytes) async =>
    await FilePicker.saveFile(
      fileName: name,
      bytes: bytes,
      dialogTitle: 'Export CSV',
    ) !=
    null;

({Uint8List bytes, int count}) _encodeCsv(
  ({
    List<LedgerEntry> entries,
    List<Account> accounts,
    Set<EntryType> types,
    Set<int?> accountIds,
    Currency currency,
  })
  input,
) {
  final entries =
      input.entries
          .where(
            (e) =>
                e.currency == input.currency &&
                input.types.contains(e.type) &&
                (input.accountIds.contains(e.accountId) ||
                    e.type == EntryType.transfer &&
                        input.accountIds.contains(e.destinationId)),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  if (entries.isEmpty) {
    throw const FormatException(
      'No transactions match the selected accounts and types.',
    );
  }
  return (
    bytes: Uint8List.fromList(
      utf8.encode(TransactionCsv.encode(entries, accounts: input.accounts)),
    ),
    count: entries.length,
  );
}

CsvPreview _decodeCsv(
  ({
    Uint8List bytes,
    Set<EntryType> types,
    Set<int?> accountIds,
    List<Account> accounts,
    Currency currency,
  })
  input,
) {
  final parsed = TransactionCsv.decode(
    input.bytes,
    input.types.length == 1 ? input.types.single : null,
    input.accountIds.length == 1 ? input.accountIds.single : null,
    currency: input.currency,
    accounts: input.accounts,
  );
  if (input.types.isEmpty || input.accountIds.isEmpty) {
    return CsvPreview([], [
      'Select at least one account and transaction type.',
    ], hasAssignments: parsed.hasAssignments);
  }
  if (!parsed.hasAssignments &&
      (input.types.length != 1 || input.accountIds.length != 1)) {
    return const CsvPreview([], [
      'This older CSV has no account or type columns. Select one account and one transaction type to assign its rows.',
    ]);
  }
  return CsvPreview(
    [
      for (final row in parsed.rows)
        if (input.types.contains(row.entry.type) &&
            (input.accountIds.contains(row.entry.accountId) ||
                row.entry.type == EntryType.transfer &&
                    input.accountIds.contains(row.entry.destinationId)))
          row,
    ],
    parsed.errors,
    hasAssignments: parsed.hasAssignments,
  );
}

class CsvScreen extends StatefulWidget {
  const CsvScreen({
    super.key,
    required this.store,
    this.pickFile = pickCsvFile,
    this.saveFile = saveCsvFile,
  });
  final LedgerStore store;
  final Future<CsvFile?> Function() pickFile;
  final Future<bool> Function(String, Uint8List) saveFile;
  @override
  State<CsvScreen> createState() => _CsvScreenState();
}

class _CsvScreenState extends State<CsvScreen> {
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  final types = EntryType.values.toSet();
  late final accountIds = <int?>{
    null,
    ...widget.store.accounts.map((a) => a.id),
  };
  bool busy = false;
  bool skipExisting = true;
  CsvFile? file;
  CsvPreview? preview;
  String? error;
  String? result;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not complete the CSV operation. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> parse() async {
    preview = null;
    if (file == null) return;
    final parsed = await compute(_decodeCsv, (
      bytes: file!.bytes,
      currency: widget.store.currency,
      types: {...types},
      accountIds: {...accountIds},
      accounts: widget.store.accounts,
    ));
    if (mounted) setState(() => preview = parsed);
  }

  Future<void> chooseFile() => run(() async {
    final selected = await widget.pickFile();
    if (!mounted || selected == null) return;
    setState(() {
      file = selected;
      preview = null;
    });
    await parse();
  });

  Future<void> export() => run(() async {
    final encoded = await compute(_encodeCsv, (
      entries: widget.store.entries,
      accounts: widget.store.accounts,
      types: {...types},
      accountIds: {...accountIds},
      currency: widget.store.currency,
    ));
    if (!mounted) return;
    final saved = await widget.saveFile(
      'paxfox_transactions_${dayKey(DateTime.now())}.csv',
      encoded.bytes,
    );
    if (mounted && saved) {
      setState(
        () => result = 'Exported ${formatInteger(encoded.count)} transactions.',
      );
    }
  });

  Future<void> import() => run(() async {
    final data = preview;
    if (data == null || data.errors.isNotEmpty) return;
    final saved = await widget.store.importCsv(
      data.rows,
      skipExisting: skipExisting,
    );
    if (mounted) {
      setState(() {
        result =
            'Imported ${formatInteger(saved.imported)} transactions. Skipped ${formatInteger(saved.skipped)} existing matches.';
        preview = null;
        file = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV import complete: ${formatInteger(saved.imported)} added, ${formatInteger(saved.skipped)} skipped.',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) scroll.jumpTo(0);
      });
    }
  });

  String _accountName(int? id) => id == null
      ? 'Unassigned'
      : widget.store.accounts.where((a) => a.id == id).firstOrNull?.name ??
            'Unknown account';

  String _typeName(EntryType type) =>
      '${type.name[0].toUpperCase()}${type.name.substring(1)}';

  Widget _selectionGroup<T>({
    required String label,
    required String allLabel,
    required String keyPrefix,
    required List<T> options,
    required Set<T> selected,
    required String Function(T) title,
    required IconData Function(T) icon,
  }) {
    final allSelected = options.every(selected.contains);
    void change(VoidCallback update) {
      setState(() {
        update();
        error = null;
        result = null;
      });
      if (file != null) run(parse);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SelectionRow(
          key: ValueKey('$keyPrefix-options'),
          count: options.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return SelectionCard(
                key: ValueKey('$keyPrefix-all'),
                selected: allSelected,
                icon: Icons.select_all,
                title: allLabel,
                onTap: busy
                    ? null
                    : () => change(() {
                        selected.clear();
                        if (!allSelected) selected.addAll(options);
                      }),
              );
            }
            final value = options[index - 1];
            final key = value is EntryType
                ? value.name
                : value?.toString() ?? 'unassigned';
            return SelectionCard(
              key: ValueKey('$keyPrefix-$key'),
              selected: selected.contains(value),
              icon: icon(value),
              title: title(value),
              onTap: busy
                  ? null
                  : () => change(() {
                      if (!selected.add(value)) selected.remove(value);
                    }),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final data = preview;
    final rows = data?.rows ?? <CsvTransactionRow>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import & export CSV'),
        actions: const [
          InfoButton(
            title: 'CSV import and export',
            message: 'Select multiple accounts and transaction types to export them together or filter an import. Each exported row includes Account, Type, Destination account and Currency alongside Date, Details, Category, Cost and Notes more info. Account names must match accounts already in the app; blank Account means Unassigned. Transfers include both accounts, match either selected account and are exported once. Older five-column files require selecting exactly one account and type to assign their rows. All dates are included. Imports are atomic and use normal balance, blocked-account and currency rules. Skip existing matches preserves repeated purchases. CSV does not include opening balances, receipts or settings.',
          ),
        ],
      ),
      body: ListView.builder(
        controller: scroll,
        padding: const EdgeInsets.all(16),
        itemCount: rows.length + 1,
        itemBuilder: (context, index) {
          if (index > 0) {
            final row = rows[index - 1];
            final e = row.entry;
            final rowError = error?.startsWith('Row ${row.number}:') == true;
            return Card(
              color: rowError ? colors.errorContainer : null,
              child: ListTile(
                title: Text('${formatInteger(row.number)}. ${e.description}'),
                subtitle: Text(
                  '${dayKey(e.date)} · ${e.category}'
                  '\n${_typeName(e.type)} \u00b7 ${_accountName(e.accountId)}'
                  '${e.destinationId == null ? '' : ' -> ${_accountName(e.destinationId)}'}'
                  '${e.notes.isEmpty ? '' : '\n${e.notes}'}${rowError ? '\n$error' : ''}',
                ),
                trailing: Text(
                  '${widget.store.currency.symbol}${widget.store.currency.formatGrouped(e.amount)}',
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _selectionGroup<int?>(
                label: 'Accounts',
                allLabel: 'All accounts',
                keyPrefix: 'csv-account',
                options: [...widget.store.accounts.map((a) => a.id), null],
                selected: accountIds,
                title: (id) => _accountName(id),
                icon: (id) => id == null
                    ? Icons.help_outline
                    : widget.store.accounts
                              .firstWhere((a) => a.id == id)
                              .kind ==
                          AccountKind.cash
                    ? Icons.payments_outlined
                    : Icons.account_balance_outlined,
              ),
              const SizedBox(height: 12),
              ListTile(
                key: const ValueKey('csv-type-picker'),
                title: const Text('Transaction types'),
                subtitle: Text(
                  types.length == EntryType.values.length
                      ? 'All types'
                      : types.map(entryTypeLabel).join(', '),
                ),
                trailing: const Icon(Icons.expand_more),
                onTap: busy
                    ? null
                    : () async {
                        final selected = await showEntryTypes(
                          context,
                          selected: types,
                          multiple: true,
                        );
                        if (selected == null || !mounted) return;
                        await run(() async {
                          setState(() {
                            types
                              ..clear()
                              ..addAll(selected);
                          });
                          await parse();
                        });
                      },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : chooseFile,
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Choose CSV'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                ),
              if (result != null)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  child: ListTile(
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    title: Text(result!),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(error!, style: TextStyle(color: colors.error)),
                ),
              if (file != null) ...[
                const SizedBox(height: 16),
                Text(
                  file!.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Skip existing matches'),
                  value: skipExisting,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => skipExisting = value),
                ),
              ],
              if (data != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${formatInteger(rows.length)} valid rows · ${widget.store.currency.symbol}${widget.store.currency.formatGrouped(rows.fold<int>(0, (total, row) => total + row.entry.amount))}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (rows.isEmpty && data.errors.isEmpty)
                  const Text('No rows match the selected accounts and types.'),
                if (data.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Review the following before importing:',
                    style: TextStyle(color: colors.error),
                  ),
                  for (final message in data.errors)
                    Text(message, style: TextStyle(color: colors.error)),
                ],
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: BottomActionBar(
        label: 'Import transactions',
        busy: busy,
        busyLabel: 'Working…',
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        icon: Icons.file_upload_outlined,
        onPressed: rows.isEmpty || data!.errors.isNotEmpty ? null : import,
      ),
    );
  }
}
