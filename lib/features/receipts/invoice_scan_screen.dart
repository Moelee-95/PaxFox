import 'dart:async';
import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/data/ledger_store.dart';
import '../../core/domain/app_failure.dart';
import '../../core/domain/ledger.dart';
import '../../core/presentation/info_button.dart';
import 'gemini_invoice_extractor.dart';
import 'invoice.dart';
import 'invoice_image_preparation.dart';
import 'invoice_image_preview.dart';
import 'invoice_review_screen.dart';

class InvoiceScanScreen extends StatefulWidget {
  const InvoiceScanScreen({
    super.key,
    required this.store,
    this.extractor,
    this.autoCapture = true,
    this.initialGallery = false,
    this.initialUpload = false,
    this.type = EntryType.expense,
    this.uploadPicker,
    this.preparationTimeout = const Duration(seconds: 45),
    this.initialImages = const [],
    this.extractionTimeout,
    this.imagePreparation,
  });
  final LedgerStore store;
  final InvoiceExtractor? extractor;
  final bool autoCapture;
  final bool initialGallery;
  final bool initialUpload;
  final EntryType type;
  final Future<List<File>> Function()? uploadPicker;
  final Duration preparationTimeout;
  final List<File> initialImages;
  final Duration? extractionTimeout;
  final InvoiceImagePreparation? imagePreparation;
  @override
  State<InvoiceScanScreen> createState() => _InvoiceScanScreenState();
}

class _InvoiceScanScreenState extends State<InvoiceScanScreen> {
  final images = <File>[];
  late final _imagePreparation =
      widget.imagePreparation ?? InvoiceImagePreparation();
  String? _preparationStage;
  bool busy = false;
  bool _showSources = false;
  int requestId = 0;
  int captureId = 0;
  InvoiceExtractor? activeExtractor;
  Timer? extractionTimer, elapsedTimer;
  int elapsedSeconds = 0;
  int limitSeconds = 0;
  String stage = 'Preparing images';
  final progress = ValueNotifier<String>('');
  void updateProgress() => progress.value =
      '$stage\nElapsed: ${elapsedSeconds}s - Timeout: ${limitSeconds}s';
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
    captureId++;
    extractionTimer?.cancel();
    elapsedTimer?.cancel();
    final extractor = activeExtractor;
    if (extractor is GeminiInvoiceExtractor) {
      extractor.cancel();
    }
    unawaited(_imagePreparation.dispose());
    progress.dispose();
    super.dispose();
  }

  String? error;
  @override
  void initState() {
    super.initState();
    images.addAll(widget.initialImages);
    if (widget.autoCapture) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => capture(
          gallery: widget.initialGallery,
          upload: widget.initialUpload,
        ),
      );
    }
  }

  Future<void> capture({bool gallery = false, bool upload = false}) async {
    if (busy || images.length >= 10) {
      return;
    }
    final currentCapture = ++captureId;
    setState(() {
      busy = true;
      error = null;
    });
    Directory? uploadSources;
    try {
      List<String>? paths;
      if (upload && widget.uploadPicker != null) {
        paths = (await widget.uploadPicker!())
            .map((file) => file.path)
            .toList();
      } else if (upload) {
        final selected = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'webp',
            'heic',
            'heif',
          ],
          dialogTitle: 'Upload images or PDF',
        );
        paths = [];
        if (selected.isNotEmpty) {
          uploadSources = await (await getTemporaryDirectory()).createTemp(
            'paxfox-upload-',
          );
          for (final picked in selected.take(10 - images.length)) {
            if (mounted) {
              setState(
                () =>
                    _preparationStage = 'Loading document ${paths!.length + 1}',
              );
            }
            if (!mounted || currentCapture != captureId) break;
            final extension = p.extension(picked.name).toLowerCase();
            final target = File(
              p.join(uploadSources.path, '${paths.length}$extension'),
            );
            final sink = target.openWrite();
            var count = 0;
            try {
              await for (final bytes in picked.readAsByteStream().timeout(
                widget.preparationTimeout,
              )) {
                count += bytes.length;
                if (count > maxInvoiceSourceBytes) {
                  throw const FormatException('A document exceeds 25 MB.');
                }
                if (!mounted || currentCapture != captureId) {
                  throw const FormatException('Upload cancelled.');
                }
                sink.add(bytes);
              }
              await sink.flush();
            } finally {
              await sink.close();
            }
            paths.add(target.path);
          }
        }
      } else {
        paths = gallery
            ? (await ImagePicker().pickMultiImage()).map((i) => i.path).toList()
            : await CunningDocumentScanner.getPictures(
                noOfPages: 10 - images.length,
              );
      }
      final selectedPaths = paths;
      if (mounted && currentCapture == captureId && selectedPaths != null) {
        final room = 10 - images.length;
        final pages = selectedPaths.take(room).toList();
        var failed = 0;
        var timedOut = false;
        for (var i = 0; i < pages.length; i++) {
          if (!mounted || currentCapture != captureId) break;
          setState(
            () => _preparationStage =
                'Optimizing image ${i + 1} of ${pages.length}',
          );
          try {
            var expired = false;
            final pending = _imagePreparation.prepare(File(pages[i]));
            // A stuck native/file/decoder operation must never trap the screen.
            unawaited(
              pending.then((file) {
                if (expired || !mounted || currentCapture != captureId) {
                  unawaited(_imagePreparation.release(file));
                }
              }, onError: (Object _) {}),
            );
            final image = await pending.timeout(
              widget.preparationTimeout,
              onTimeout: () {
                expired = true;
                throw TimeoutException('Image preparation timed out.');
              },
            );
            if (mounted && currentCapture == captureId) {
              setState(() => images.add(image));
            }
          } on TimeoutException {
            timedOut = true;
            break;
          } catch (_) {
            failed++;
          }
        }
        if (mounted && currentCapture == captureId) {
          setState(() {
            error = timedOut
                ? 'Image optimization timed out. Try again with a smaller image or scan fewer pages.'
                : failed > 0
                ? '$failed image(s) could not be prepared. Try a JPEG/PNG under 25 MB or scan again.'
                : selectedPaths.length > room
                ? 'Only the first $room selected images were added. Maximum 10 pages.'
                : null;
          });
        }
      }
    } catch (e) {
      if (mounted && currentCapture == captureId) {
        setState(
          () => error = upload
              ? e is FormatException
                    ? e.message
                    : 'File unavailable. Choose a readable image or PDF and try again.'
              : 'Camera unavailable or permission denied. Try gallery images, or enable camera access in device settings.',
        );
      }
    } finally {
      if (uploadSources != null) {
        try {
          await uploadSources.delete(recursive: true);
        } catch (_) {
          /* Owned temporary copies only. */
        }
      }
      if (mounted && currentCapture == captureId) {
        setState(() {
          busy = false;
          _preparationStage = null;
        });
      }
    }
  }

  Future<void> review(InvoiceDraft draft) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceReviewScreen(
          store: widget.store,
          draft: widget.type == draft.type
              ? draft
              : InvoiceDraft(
                  type: widget.type,
                  merchant: draft.merchant,
                  date: draft.date,
                  multipleInvoices: draft.multipleInvoices,
                  currency: draft.currency,
                  total: draft.total,
                  category: draft.category,
                  adjustment: draft.adjustment,
                  adjustmentNote: draft.adjustmentNote,
                  items: draft.items,
                  raw: draft.raw,
                ),
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
    updateProgress();
    activeExtractor =
        widget.extractor ??
        GeminiInvoiceExtractor(
          timeout: timeout,
          currency: widget.store.currency,
          type: widget.type,
          onProgress: (value) {
            if (mounted && requestId == currentRequest) {
              stage = value;
              updateProgress();
            }
          },
        );
    elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && requestId == currentRequest) {
        elapsedSeconds++;
        updateProgress();
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
        widget.store.categoriesFor(widget.type).map((c) => c.name).toSet(),
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
          () => error = AppFailure.messageFor(
            e,
            fallback: 'Extraction failed. Your images are still available. Please retry.',
          ),
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
      appBar: AppBar(
        title: Text(
          widget.type == EntryType.income ? 'Scan income' : 'Scan invoice',
        ),
        actions: [
          InfoButton(
            title: 'Invoice scanning information',
            message: widget.type == EntryType.income
                ? 'Upload or scan payslips, statements or paid customer invoices. Payslips use net pay as one income entry. Only received income is extracted; outgoing payments, internal transfers and balances are excluded. Images and PDFs are supported. Review every amount, date and category before saving.'
                : 'Add pages from one or more invoices, in order. Each extracted item has its own invoice date. Maximum 10 files or scanned pages. Images and PDFs are supported. Review every extracted price and category before saving.',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(),
            if (_preparationStage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_preparationStage!),
              ),
            if (busy && activeExtractor != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, value, _) => Text(value),
                ),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            FilledButton(
              onPressed: busy || images.isEmpty ? null : extract,
              child: const Text('Extract'),
            ),
            if (_preparationStage != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  captureId++;
                  busy = false;
                  _preparationStage = null;
                  error = 'Image preparation cancelled.';
                }),
                icon: const Icon(Icons.close),
                label: const Text('Cancel preparation'),
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < images.length; i++)
            Card(
              child: Column(
                children: [
                  InvoiceImagePreview(file: images[i], height: 220),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '${isInvoicePdf(images[i]) ? 'PDF' : 'Page'} ${i + 1}',
                      ),
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
                            : () {
                                final file = images[i];
                                setState(() => images.removeAt(i));
                                unawaited(_imagePreparation.release(file));
                              },
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: _showSources
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: busy || images.length >= 10
                              ? null
                              : () => capture(),
                          icon: const Icon(Icons.document_scanner_outlined),
                          label: const Text('Scan'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy || images.length >= 10
                              ? null
                              : () => capture(upload: true),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Upload file'),
                        ),
                        OutlinedButton.icon(
                          onPressed: busy || images.length >= 10
                              ? null
                              : () => capture(gallery: true),
                          label: const Text('Gallery'),
                          icon: const Icon(Icons.photo_library_outlined),
                        ),
                      ],
                    )
                  : TextButton.icon(
                      onPressed: busy || images.length >= 10
                          ? null
                          : () => setState(() => _showSources = true),
                      icon: const Icon(Icons.add),
                      label: const Text('Add pages'),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
