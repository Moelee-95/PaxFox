import 'dart:io';
import 'dart:math' as math;

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

class InvoiceImagePreparation {
  InvoiceImagePreparation({this.temporaryDirectory});

  final Future<Directory> Function()? temporaryDirectory;
  static final _prepared = Expando<Uint8List>('Prepared invoice image bytes');
  final _files = <File>[];
  Future<Directory>? _directory;
  Future<File>? _pending;
  bool _disposed = false;
  int _nextPage = 0;

  static Future<Uint8List> bytesFor(File file) async {
    final prepared = _prepared[file];
    if (prepared != null) return prepared;
    if (await file.length() > maxInvoiceSourceBytes) {
      throw const FormatException('An image is too large (25 MB limit).');
    }
    return compute(prepareInvoiceImage, await file.readAsBytes());
  }

  Future<File> prepare(File source) {
    if (_disposed) throw StateError('Image preparation has been closed.');
    return _pending = _prepare(source);
  }

  Future<File> _prepare(File source) async {
    final bytes = await bytesFor(source);
    if (_disposed) throw StateError('Image preparation has been closed.');
    final directory = await (_directory ??= _createDirectory());
    if (_disposed) throw StateError('Image preparation has been closed.');
    final file = File(p.join(directory.path, 'page-${_nextPage++}.jpg'));
    _files.add(file);
    await file.writeAsBytes(bytes, flush: true);
    _prepared[file] = bytes;
    return file;
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
      await _pending;
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
