import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _targetBytes = 1024 * 1024;
const maxInvoiceSourceBytes = 25 * 1024 * 1024;

Uint8List prepareInvoiceImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Unsupported invoice image.');
  }
  final orientation = decoded.exif.imageIfd.orientation;
  final oriented = img.bakeOrientation(decoded);
  final shortEdge = math.min(oriented.width, oriented.height);
  final longEdge = math.max(oriented.width, oriented.height);
  final scale = math.min(1.0, math.min(2000 / shortEdge, 6000 / longEdge));
  final unchanged = scale == 1 && (orientation == null || orientation == 1);
  final isJpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
  if (isJpeg && unchanged && bytes.length <= _targetBytes) return bytes;
  final image = scale == 1
      ? oriented
      : img.copyResize(
          oriented,
          width: math.max(1, (oriented.width * scale).round()),
          height: math.max(1, (oriented.height * scale).round()),
          interpolation: img.Interpolation.average,
        );
  var compressed = img.encodeJpg(image, quality: 86);
  for (final quality in [82, 78]) {
    if (compressed.length <= _targetBytes) break;
    compressed = img.encodeJpg(image, quality: quality);
  }
  // Keep a smaller, already compatible JPEG rather than adding loss or bytes.
  return isJpeg && unchanged && bytes.length < compressed.length
      ? bytes
      : compressed;
}

bool isInvoicePdf(File file) => p.extension(file.path).toLowerCase() == '.pdf';

class InvoiceImagePreparation {
  InvoiceImagePreparation({this.temporaryDirectory});

  final Future<Directory> Function()? temporaryDirectory;
  static final _prepared = Expando<Uint8List>('Prepared invoice image bytes');
  final _files = <File>[];
  Future<Directory>? _directory;
  final _pending = <Future<File>>{};
  bool _disposed = false;
  int _nextPage = 0;

  static Future<Uint8List> bytesFor(File file) async {
    final prepared = _prepared[file];
    if (prepared != null) return prepared;
    if (await file.length() > maxInvoiceSourceBytes) {
      throw const FormatException('An image is too large (25 MB limit).');
    }
    var bytes = await file.readAsBytes();
    if (isInvoicePdf(file)) {
      if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        throw const FormatException('The file is not a readable PDF.');
      }
      return bytes;
    }
    // Downsample oversized camera photos in the native codec before the Dart
    // JPEG encoder. Decoding full-resolution scans in Dart can take minutes.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        math.min(
          2000 / math.min(descriptor.width, descriptor.height),
          6000 / math.max(descriptor.width, descriptor.height),
        ),
      );
      if (scale < 1 ||
          ['.heic', '.heif'].contains(p.extension(file.path).toLowerCase())) {
        codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * scale).round()),
          targetHeight: math.max(1, (descriptor.height * scale).round()),
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
    late final Future<File> task;
    task = _prepare(source).whenComplete(() => _pending.remove(task));
    _pending.add(task);
    return task;
  }

  Future<File> _prepare(File source) async {
    final bytes = await bytesFor(source);
    if (_disposed) throw StateError('Image preparation has been closed.');
    final directory = await (_directory ??= _createDirectory().catchError((
      Object error,
    ) {
      _directory = null;
      throw error;
    }));
    if (_disposed) throw StateError('Image preparation has been closed.');
    final file = File(
      p.join(
        directory.path,
        'page-${_nextPage++}.${isInvoicePdf(source) ? 'pdf' : 'jpg'}',
      ),
    );
    _files.add(file);
    try {
      await file.writeAsBytes(bytes, flush: true);
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
