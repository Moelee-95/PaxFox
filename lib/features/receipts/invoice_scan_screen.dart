import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/data/ledger_store.dart';
import '../../core/domain/ledger.dart';
import 'gemini_invoice_extractor.dart';
import 'invoice.dart';
import 'invoice_review_screen.dart';

class InvoiceScanScreen extends StatefulWidget {
  const InvoiceScanScreen({
    super.key,
    required this.store,
    this.extractor,
    this.autoCapture = true,
    this.initialImages = const [],
    this.extractionTimeout,
  });
  final LedgerStore store;
  final InvoiceExtractor? extractor;
  final bool autoCapture;
  final List<File> initialImages;
  final Duration? extractionTimeout;
  @override
  State<InvoiceScanScreen> createState() => _InvoiceScanScreenState();
}

class _InvoiceScanScreenState extends State<InvoiceScanScreen> {
  final images = <File>[];
  bool busy = false;
  int requestId = 0;
  InvoiceExtractor? activeExtractor;
  Timer? extractionTimer, elapsedTimer;
  int elapsedSeconds = 0;
  int limitSeconds = 0;
  String stage = 'Preparing images';
  void cancelExtraction({String? message}) {
    requestId++;
    extractionTimer?.cancel();
    elapsedTimer?.cancel();
    final extractor = activeExtractor;
    if (extractor is GeminiInvoiceExtractor) {
      extractor.cancel();
    }
    activeExtractor = null;
    if (mounted) {
      setState(() {
        busy = false;
        error = message;
      });
    }
  }

  @override
  void dispose() {
    requestId++;
    extractionTimer?.cancel();
    elapsedTimer?.cancel();
    final extractor = activeExtractor;
    if (extractor is GeminiInvoiceExtractor) {
      extractor.cancel();
    }
    super.dispose();
  }

  String? error;
  @override
  void initState() {
    super.initState();
    images.addAll(widget.initialImages);
    if (widget.autoCapture) {
      WidgetsBinding.instance.addPostFrameCallback((_) => capture());
    }
  }

  Future<void> capture({bool gallery = false}) async {
    if (busy || images.length >= 10) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final paths = gallery
          ? (await ImagePicker().pickMultiImage(imageQuality: 85))
                .map((i) => i.path)
                .toList()
          : await CunningDocumentScanner.getPictures(
              noOfPages: 10 - images.length,
            );
      if (mounted && paths != null) {
        setState(() {
          final room = 10 - images.length;
          if (paths.length > room) {
            error =
                'Only the first $room selected images were added. Maximum 10 pages.';
          }
          images.addAll(paths.take(room).map(File.new));
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Camera unavailable or permission denied. Try gallery images, or enable camera access in device settings.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> review(InvoiceDraft draft) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceReviewScreen(
          store: widget.store,
          draft: draft,
          images: List.of(images),
        ),
      ),
    );
    if (saved == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> extract() async {
    if (busy || images.isEmpty) {
      return;
    }
    final currentRequest = ++requestId;
    final timeout =
        widget.extractionTimeout ??
        Duration(seconds: widget.store.invoiceTimeoutSeconds);
    limitSeconds = timeout.inSeconds;
    elapsedSeconds = 0;
    stage = 'Preparing images';
    activeExtractor =
        widget.extractor ??
        GeminiInvoiceExtractor(
          timeout: timeout,
          onProgress: (value) {
            if (mounted && requestId == currentRequest) {
              setState(() => stage = value);
            }
          },
        );
    elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && requestId == currentRequest) {
        setState(() => elapsedSeconds++);
      }
    });
    extractionTimer = Timer(timeout, () {
      if (mounted && requestId == currentRequest) {
        cancelExtraction(
          message:
              'Extraction timed out after $limitSeconds seconds. Increase the limit in Settings or try fewer images.',
        );
      }
    });
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final draft = await activeExtractor!.extract(
        List.of(images),
        widget.store
            .categoriesFor(EntryType.expense)
            .map((c) => c.name)
            .toSet(),
      );
      if (mounted && requestId == currentRequest) {
        extractionTimer?.cancel();
        elapsedTimer?.cancel();
        setState(() => busy = false);
        await review(draft);
      }
    } catch (e) {
      if (mounted && requestId == currentRequest) {
        setState(
          () => error = e is InvoiceExtractionException ? e.message : 'Extraction failed. Check your connection and Gemini configuration, then retry.',
        );
      }
    } finally {
      if (mounted && requestId == currentRequest) {
        extractionTimer?.cancel();
        elapsedTimer?.cancel();
        activeExtractor = null;
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        cancelExtraction();
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Scan invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Capture all pages of ONE invoice, in order. You can add more images for a long receipt. Maximum 10. Review every extracted price and category before saving.',
          ),
          Wrap(
            spacing: 10,
            children: [
              FilledButton.icon(
                onPressed: busy || images.length >= 10 ? null : () => capture(),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Scan more pages'),
              ),
              OutlinedButton(
                onPressed: busy || images.length >= 10
                    ? null
                    : () => capture(gallery: true),
                child: const Text('Gallery'),
              ),
            ],
          ),
          for (var i = 0; i < images.length; i++)
            Card(
              child: Column(
                children: [
                  SizedBox(
                    height: 220,
                    child: Image.file(
                      images[i],
                      errorBuilder: (_, _, _) =>
                          const Center(child: Text('Image unavailable')),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Page ${i + 1}'),
                      IconButton(
                        tooltip: 'Move page earlier',
                        onPressed: busy || i == 0
                            ? null
                            : () => setState(() {
                                final file = images.removeAt(i);
                                images.insert(i - 1, file);
                              }),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: 'Remove page',
                        onPressed: busy
                            ? null
                            : () => setState(() => images.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (busy) ...[
            const LinearProgressIndicator(),
            if (activeExtractor != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '$stage\nElapsed: ${elapsedSeconds}s ? Timeout: ${limitSeconds}s',
                ),
              ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy || images.isEmpty ? null : extract,
            child: const Text('Extract'),
          ),
          if (busy && activeExtractor != null)
            TextButton.icon(
              onPressed: () =>
                  cancelExtraction(message: 'Extraction cancelled.'),
              icon: const Icon(Icons.close),
              label: const Text('Cancel extraction'),
            ),
        ],
      ),
    ),
  );
}
