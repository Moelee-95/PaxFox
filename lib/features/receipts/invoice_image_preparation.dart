import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _targetBytes = 1024 * 1024;
const maxInvoiceSourceBytes = 25 * 1024 * 1024;
const maxInvoiceImagePixels = 4000000;

double _imageScale(int width, int height) => math.min(
  1.0,
  math.min(
    2000 / math.min(width, height),
    math.min(
      6000 / math.max(width, height),
      math.sqrt(maxInvoiceImagePixels / (width * height)),
    ),
  ),
);

Uint8List prepareInvoiceImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported invoice image.');
  }
  final orientation = decoded.exif.imageIfd.orientation;
  final oriented = img.bakeOrientation(decoded);
  final scale = _imageScale(oriented.width, oriented.height);
  final unchanged = scale == 1 && (orientation == null || orientation == 1);
  final isJpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
  if (isJpeg && unchanged && bytes.length <= _targetBytes) return bytes;
  final image = scale == 1
      ? oriented
      : img.copyResize(
          oriented,
          width: math.max(1, (oriented.width * scale).floor()),
          height: math.max(1, (oriented.height * scale).floor()),
          interpolation: img.Interpolation.average,
        );
  final compressed = img.encodeJpg(image, quality: 86);
  // Keep a smaller, already compatible JPEG rather than adding loss or bytes.
  return isJpeg && unchanged && bytes.length < compressed.length
      ? bytes
      : compressed;
}

bool isInvoicePdf(File file) => p.extension(file.path).toLowerCase() == '.pdf';

class InvoiceImagePreparation {
  InvoiceImagePreparation({this.temporaryDirectory, this.imageProcessor});

  final Future<Directory> Function()? temporaryDirectory;
  // Injectable worker lets regression tests hold a decode across cancellation.
  final Future<Uint8List> Function(File)? imageProcessor;
  static const nativeChannel = MethodChannel('paxfox/invoice_images');
  static final _prepared = Expando<Uint8List>('Prepared invoice image bytes');
  // Timeouts cannot interrupt an OS decoder. Keep at most one decode active,
  // including retries and extraction, rather than piling up abandoned workers.
  static Future<void> _worker = Future.value();
  static Future<T> _serial<T>(Future<T> Function() work) {
    final result = _worker.then((_) => work());
    _worker = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  final _files = <File>[];
  Future<Directory>? _directory;
  final _pending = <Future<File>>{};
  bool _disposed = false;
  int _generation = 0;
  int _nextPage = 0;

  static Future<Uint8List> bytesFor(File file) {
    final prepared = _prepared[file];
    if (prepared != null) return Future.value(prepared);
    return _serial(() => _bytesFor(file));
  }

  static Future<Uint8List> _bytesFor(File file) async {
    if (await file.length() > maxInvoiceSourceBytes) {
      throw const FormatException('An image is too large (25 MB limit).');
    }
    if (isInvoicePdf(file)) {
      final bytes = await file.readAsBytes();
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException('The file is not a readable PDF.');
      }
      return bytes;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      // Native sampled decode -> one native JPEG encode. No PNG round trip,
      // Dart pixel decode, repeated compression, or full-size camera bitmap.
      final bytes = await nativeChannel.invokeMethod<Uint8List>('prepare', {
        'path': file.path,
      });
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Cannot read image.');
      }
      return bytes;
    }
    // Desktop/test fallback; mobile must never silently regress to this path.
    var bytes = await file.readAsBytes();
    // Downsample oversized camera photos in the native codec before the Dart
    // JPEG encoder. Decoding full-resolution scans in Dart can take minutes.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = _imageScale(descriptor.width, descriptor.height);
      if (scale < 1 ||
          ['.heic', '.heif'].contains(p.extension(file.path).toLowerCase())) {
        codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).floor()),
          targetHeight: math.max(1, (descriptor.height * scale).floor()),
        );
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('Cannot read image.');
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }
    } catch (_) {
      throw const FormatException('Unsupported invoice image.');
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    return compute(prepareInvoiceImage, bytes);
  }

  Future<File> prepare(File source) {
    if (_disposed) throw StateError('Image preparation has been closed.');
    final generation = _generation;
    late final Future<File> task;
    task = _serial(() => _prepare(source, generation))
        .whenComplete(() => _pending.remove(task));
    _pending.add(task);
    return task;
  }

  void cancelPending() => _generation++;

  void _checkActive(int generation) {
    if (_disposed || generation != _generation) {
      throw StateError('Image preparation cancelled.');
    }
  }

  Future<File> _prepare(File source, int generation) async {
    _checkActive(generation);
    final bytes = await (imageProcessor ?? _bytesFor)(source);
    _checkActive(generation);
    final directory = await (_directory ??= _createDirectory().catchError((
      Object error,
    ) {
      _directory = null;
      throw error;
    }));
    _checkActive(generation);
    final file = File(
      p.join(
        directory.path,
        'page-${_nextPage++}.${isInvoicePdf(source) ? 'pdf' : 'jpg'}',
      ),
    );
    _files.add(file);
    try {
      await file.writeAsBytes(bytes, flush: true);
      _checkActive(generation);
      _prepared[file] = bytes;
      return file;
    } catch (_) {
      await release(file);
      rethrow;
    }
  }

  Future<Directory> _createDirectory() async =>
      (await (temporaryDirectory?.call() ?? getTemporaryDirectory()))
          .createTemp('moneva-invoice-');

  Future<void> release(File file) async {
    if (!_files.remove(file)) return;
    _prepared[file] = null;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      /* OS cache cleanup can retry. */
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    cancelPending();
    try {
      await Future.wait(_pending.toList(), eagerError: false);
    } catch (_) {
      /* Cleanup also follows failed preparation. */
    }
    for (final file in _files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        /* OS cache cleanup can retry. */
      }
      _prepared[file] = null;
    }
    if (_directory != null) {
      try {
        await (await _directory!).delete();
      } catch (_) {
        /* Do not delete unrelated cache files. */
      }
    }
  }
}
