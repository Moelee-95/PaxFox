import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

CsvPreview _decodeCsv(
  ({Uint8List bytes, EntryType? type, int? accountId, Currency currency}) input,
) => TransactionCsv.decode(
  input.bytes,
  input.type,
  input.accountId,
  currency: input.currency,
);

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

  EntryType? type;
  int? accountId;
  bool busy = false;
  bool skipExisting = true;
  CsvFile? file;
  CsvPreview? preview;
  String? error;
  String? result;

  Future<void> run(Future<void> Function() action) async {
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
      type: type,
      accountId: accountId,
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
    final entries =
        widget.store.entries
            .where(
              (e) =>
                  e.currency == widget.store.currency &&
                  e.type == (type ?? EntryType.expense) &&
                  e.accountId == accountId,
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    if (entries.isEmpty) {
      throw const FormatException(
        'No transactions for this account and type to export.',
      );
    }
    final saved = await widget.saveFile(
      'moneva_${(type ?? EntryType.expense).name}_${accountId ?? 'unassigned'}_${dayKey(DateTime.now())}.csv',
      Uint8List.fromList(utf8.encode(TransactionCsv.encode(entries))),
    );
    if (mounted && saved) {
      setState(
        () =>
            result = 'Exported ${formatInteger(entries.length)} transactions.',
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
            message: 'Date · Details · Category · Cost · Notes more info Example: 1.10.26, Bank Fee, Service, 4.95.  Account and type are optional. Unassigned expenses count in transactions and reports without changing account balances.  Leaving the type unset treats rows as expenses. All dates are included in exports.  Transfers require two accounts and are not supported by this five-column format. Skip existing matches compares date, details, category, cost, notes, type and account; repeated purchases within a file are preserved. Missing categories receive a general icon. Import updates balances using normal account rules; dates before the opening balance count as history.',
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
              DropdownButtonFormField<int>(
                initialValue: accountId,
                hint: const Text('Unassigned (payment unknown)'),
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Unassigned (payment unknown)'),
                  ),
                  for (final a in widget.store.accounts)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        accountId = value;
                        run(parse);
                      },
              ),
              const SizedBox(height: 12),
              EntryTypePicker(
                value: type ?? EntryType.expense,
                types: const [
                  EntryType.expense,
                  EntryType.income,
                  EntryType.refund,
                ],
                onChanged: busy
                    ? null
                    : (value) {
                        type = value;
                        run(parse);
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
                if (data.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Correct these rows in the CSV and choose the file again:',
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
