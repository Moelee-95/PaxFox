import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

import 'gemini_invoice_extractor.dart';

class InvoiceImages {
  Future<File> resolve(String relative) async {
    if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
      throw ArgumentError('Invalid receipt path.');
    }
    return File(
      p.join((await getApplicationSupportDirectory()).path, relative),
    );
  }

  Future<List<String>> retain(List<File> files) async {
    final result = <String>[];
    try {
      final prefix = '${DateTime.now().microsecondsSinceEpoch}';
      for (var i = 0; i < files.length; i++) {
        final relative = p.join('receipts', '$prefix-$i.jpg');
        final target = await resolve(relative);
        await target.parent.create(recursive: true);
        final bytes = await compute(
          prepareInvoiceImage,
          await files[i].readAsBytes(),
        );
        await target.writeAsBytes(bytes, flush: true);
        result.add(relative);
      }
      return result;
    } catch (_) {
      await remove(result);
      rethrow;
    }
  }

  Future<void> remove(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = await resolve(path);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        /* Retry through later storage cleanup; do not expose file content. */
      }
    }
  }
}
