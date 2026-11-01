import 'dart:io';

import 'package:flutter/material.dart';

import 'invoice_images.dart';
import 'invoice_image_preparation.dart';

class InvoiceImagePreview extends StatefulWidget {
  const InvoiceImagePreview({
    super.key,
    required File this.file,
    this.height = 180,
  }) : path = null;
  const InvoiceImagePreview.stored({
    super.key,
    required String this.path,
    this.height = 180,
  }) : file = null;

  final File? file;
  final String? path;
  final double height;

  @override
  State<InvoiceImagePreview> createState() => _InvoiceImagePreviewState();
}

class _InvoiceImagePreviewState extends State<InvoiceImagePreview> {
  Future<File>? resolved;

  @override
  void initState() {
    super.initState();
    resolve();
  }

  @override
  void didUpdateWidget(InvoiceImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) resolve();
  }

  void resolve() {
    resolved = widget.path == null
        ? null
        : InvoiceImages().resolve(widget.path!);
  }

  Widget image(File file) => isInvoicePdf(file)
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 8),
              const Text('PDF document'),
              const Text(
                'Attached for extraction and saved with the transaction',
              ),
            ],
          ),
        )
      : Image.file(
          file,
          cacheHeight: (widget.height * MediaQuery.devicePixelRatioOf(context))
              .round(),
          errorBuilder: (_, _, _) =>
              const Center(child: Text('Image unavailable')),
        );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    child: widget.file != null
        ? image(widget.file!)
        : FutureBuilder<File>(
            future: resolved,
            builder: (_, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Text('Stored image unavailable'));
              }
              return snapshot.hasData
                  ? image(snapshot.data!)
                  : const Center(child: CircularProgressIndicator());
            },
          ),
  );
}
