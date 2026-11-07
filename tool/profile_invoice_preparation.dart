import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:moneva/features/receipts/invoice_image_preparation.dart';
import 'package:path_provider/path_provider.dart';

/// Synthetic photos only; never opens the production ledger or calls Gemini.
/// Build with the isolated Android package and PAXFOX_BENCHMARK=true.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('PAXFOX_BENCHMARK')) {
    throw StateError('Use the isolated benchmark command in PERFORMANCE.md.');
  }
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Synthetic image benchmark'))),
    ),
  );
  final directory = await (await getTemporaryDirectory()).createTemp(
    'paxfox-synthetic-image-benchmark-',
  );
  final results = <Map<String, Object?>>[];
  try {
    for (final fixture in [
      ('photo-small', 500, 700, 1),
      ('photo-8mp', 3264, 2448, 1),
      ('photo-12mp', 4032, 3024, 1),
      ('rotated-12mp', 4032, 3024, 6),
      ('panorama-12mp', 6000, 2000, 1),
    ]) {
      final (name, width, height, orientation) = fixture;
      debugPrint('PAXFOX_IMAGE_STAGE creating $name');
      final path = '${directory.path}/$name.jpg';
      await compute(_createFixture, {
        'path': path,
        'width': width,
        'height': height,
        'orientation': orientation,
      });
      final source = File(path);
      final preparation = InvoiceImagePreparation(
        temporaryDirectory: () async => directory,
      );
      final result = <String, Object?>{
        'fixture': name,
        'sourceWidth': width,
        'sourceHeight': height,
        'sourceOrientation': orientation,
        'sourceBytes': await source.length(),
      };
      final stopwatch = Stopwatch()..start();
      debugPrint('PAXFOX_IMAGE_STAGE preparing $name');
      try {
        final prepared = await preparation
            .prepare(source)
            .timeout(const Duration(minutes: 4));
        result['preparationMs'] = stopwatch.elapsedMicroseconds / 1000;
        stopwatch.reset();
        final bytes = await InvoiceImagePreparation.bytesFor(prepared);
        result['cachedReadMs'] = stopwatch.elapsedMicroseconds / 1000;
        result['outputBytes'] = bytes.length;
        result['jpeg'] = bytes[0] == 0xff && bytes[1] == 0xd8;
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        result['outputWidth'] = descriptor.width;
        result['outputHeight'] = descriptor.height;
        descriptor.dispose();
        buffer.dispose();
        stopwatch.reset();
        final reused = await InvoiceImagePreparation.bytesFor(prepared);
        result['secondCachedReadMs'] = stopwatch.elapsedMicroseconds / 1000;
        result['reusedSameBytes'] = identical(bytes, reused);
        final outputWidth = result['outputWidth']! as int;
        final outputHeight = result['outputHeight']! as int;
        final expectedRatio = orientation == 6
            ? height / width
            : width / height;
        final checks = <String, bool>{
          'sourcePreserved':
              await source.exists() &&
              await source.length() == result['sourceBytes'],
          'jpeg': result['jpeg']! as bool,
          'cacheReusesBytes': identical(bytes, reused),
          'orientationAndAspectRatio':
              (outputWidth / outputHeight - expectedRatio).abs() < .005,
          'boundedPixels': outputWidth * outputHeight <= 4000000,
          if (name == 'photo-small')
            'smallJpegUnchanged': listEquals(await source.readAsBytes(), bytes),
        };
        result['checks'] = checks;
        if (checks.containsValue(false)) {
          throw StateError('Fixture validation failed: $checks');
        }
      } catch (error) {
        result['error'] = '$error';
        result['elapsedMs'] = stopwatch.elapsedMicroseconds / 1000;
      } finally {
        await preparation.dispose();
        if (kDebugMode && name == 'photo-12mp') {
          await source.copy('${directory.path}/legacy-12mp.jpg');
        }
        await source.delete();
      }
      results.add(result);
      debugPrint('PAXFOX_IMAGE_RESULT ${jsonEncode(result)}');
    }
    debugPrint('PAXFOX_IMAGE_BENCHMARK ${jsonEncode(results)}');
    if (kDebugMode) {
      await _measureLegacy(File('${directory.path}/legacy-12mp.jpg'));
    }
  } catch (error, stack) {
    debugPrint('PAXFOX_IMAGE_FATAL $error\n$stack');
  } finally {
    await directory.delete(recursive: true);
  }
}

// Kept only in this isolated tool to reproduce the pre-fix mobile pipeline in
// debug mode. Kill its worker after two minutes; a Future timeout alone leaves
// the expensive compression running and competing with retries.
Future<void> _measureLegacy(File source) async {
  final stopwatch = Stopwatch()..start();
  Isolate? worker;
  final response = ReceivePort();
  final result = <String, Object?>{'fixture': 'photo-12mp', 'mode': 'debug'};
  debugPrint('PAXFOX_IMAGE_STAGE legacy-debug preparing photo-12mp');
  try {
    var bytes = await source.readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    ui.Codec? codec;
    ui.Image? image;
    try {
      final scale = math.min(
        1.0,
        math.min(
          2000 / math.min(descriptor.width, descriptor.height),
          6000 / math.max(descriptor.width, descriptor.height),
        ),
      );
      if (scale < 1) {
        codec = await descriptor.instantiateCodec(
          targetWidth: (descriptor.width * scale).round(),
          targetHeight: (descriptor.height * scale).round(),
        );
        image = (await codec.getNextFrame()).image;
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = data!.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      }
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
    worker = await Isolate.spawn(_legacyWorker, (
      response.sendPort,
      TransferableTypedData.fromList([bytes]),
    ));
    final message = await response.first.timeout(const Duration(minutes: 2));
    if (message is String) throw StateError(message);
    result['outputBytes'] = (message as TransferableTypedData)
        .materialize()
        .lengthInBytes;
  } catch (error) {
    result['error'] = '$error';
  } finally {
    worker?.kill(priority: Isolate.immediate);
    response.close();
    result['elapsedMs'] = stopwatch.elapsedMicroseconds / 1000;
    result['exceeded45SecondLimit'] = stopwatch.elapsedMilliseconds > 45000;
    debugPrint('PAXFOX_IMAGE_LEGACY ${jsonEncode(result)}');
  }
}

void _legacyWorker((SendPort, TransferableTypedData) arguments) {
  try {
    final bytes = arguments.$2.materialize().asUint8List();
    final decoded = img.decodeImage(bytes)!;
    final orientation = decoded.exif.imageIfd.orientation;
    final oriented = img.bakeOrientation(decoded);
    final scale = math.min(
      1.0,
      math.min(
        2000 / math.min(oriented.width, oriented.height),
        6000 / math.max(oriented.width, oriented.height),
      ),
    );
    final unchanged = scale == 1 && (orientation == null || orientation == 1);
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    if (isJpeg && unchanged && bytes.length <= 1024 * 1024) {
      arguments.$1.send(TransferableTypedData.fromList([bytes]));
      return;
    }
    final image = scale == 1
        ? oriented
        : img.copyResize(
            oriented,
            width: (oriented.width * scale).round(),
            height: (oriented.height * scale).round(),
            interpolation: img.Interpolation.average,
          );
    var compressed = img.encodeJpg(image, quality: 86);
    for (final quality in [82, 78]) {
      if (compressed.length <= 1024 * 1024) break;
      compressed = img.encodeJpg(image, quality: quality);
    }
    arguments.$1.send(TransferableTypedData.fromList([compressed]));
  } catch (error) {
    arguments.$1.send('$error');
  }
}

void _createFixture(Map<String, Object> arguments) {
  final width = arguments['width']! as int;
  final height = arguments['height']! as int;
  final image = img.Image(width: width, height: height);
  var noise = 0x12345678;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      noise ^= noise << 13;
      noise ^= noise >> 17;
      noise ^= noise << 5;
      noise &= 0x7fffffff;
      // High detail, deterministic, and private-data free. A gray background
      // plus noise and fine lines keeps all JPEG quality passes exercised.
      final intensity = (noise & 127) + (((x ~/ 3 + y ~/ 3) & 1) * 96);
      image.setPixelRgb(x, y, intensity, intensity, intensity);
    }
  }
  image.exif.imageIfd.orientation = arguments['orientation']! as int;
  File(arguments['path']! as String)
      .writeAsBytesSync(img.encodeJpg(image, quality: 96));
}
