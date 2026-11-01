import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/presentation/busy_label.dart';

import 'invoice_image_preview.dart';

class InvoiceSourceDetails extends StatefulWidget {
  const InvoiceSourceDetails({
    super.key,
    required this.source,
    this.title = 'Scanned invoice',
  });
  final Future<Map<String, Object?>?> source;
  final String title;

  @override
  State<InvoiceSourceDetails> createState() => _InvoiceSourceDetailsState();
}

class _InvoiceSourceDetailsState extends State<InvoiceSourceDetails> {
  late Future<({List<String> paths, String raw})?> details = load();

  Future<({List<String> paths, String raw})?> load() async {
    final data = await widget.source;
    if (data == null) return null;
    final paths = jsonDecode(data['image_paths'] as String);
    if (paths is! List || paths.any((path) => path is! String)) {
      throw const FormatException('Invalid attachment list');
    }
    return (paths: paths.cast<String>(), raw: data['raw_response'] as String);
  }

  @override
  void didUpdateWidget(InvoiceSourceDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) details = load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: details,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: BusyLabel(busy: true, label: 'Loading source…'),
        );
      }
      if (snapshot.hasError) {
        return const Text(
          'Invoice attachments could not be loaded. You can still edit this transaction.',
        );
      }
      final data = snapshot.data;
      if (data == null) return const SizedBox.shrink();
      return ExpansionTile(
        title: Text(widget.title),
        children: [
          for (final path in data.paths)
            InvoiceImagePreview.stored(path: path, height: 220),
          ExpansionTile(
            title: const Text('Original extracted data'),
            children: [SelectableText(data.raw)],
          ),
        ],
      );
    },
  );
}
