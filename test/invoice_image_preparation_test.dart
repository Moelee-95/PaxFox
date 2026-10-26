import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:moneva/features/receipts/gemini_invoice_extractor.dart';
import 'package:moneva/features/receipts/invoice_image_preparation.dart';

void main() {
  Uint8List receiptPng(int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    img.drawString(
      image,
      'INVOICE 12.34 EUR',
      font: img.arial24,
      x: 24,
      y: 24,
      color: img.ColorRgb8(0, 0, 0),
    );
    img.fillRect(
      image,
      x1: 20,
      y1: 100,
      x2: width - 20,
      y2: 104,
      color: img.ColorRgb8(0, 0, 0),
    );
    return img.encodePng(image);
  }

  test(
    'small JPEGs are preserved byte-for-byte without extra quality loss',
    () {
      final jpeg = img.encodeJpg(
        img.decodePng(receiptPng(500, 700))!,
        quality: 90,
      );
      expect(prepareInvoiceImage(jpeg), same(jpeg));
    },
  );

  test(
    'compression retains receipt contrast and never upscales small images',
    () {
      final jpeg = prepareInvoiceImage(receiptPng(500, 700));
      final decoded = img.decodeJpg(jpeg)!;
      expect(decoded.width, 500);
      expect(decoded.height, 700);
      expect(decoded.getPixel(200, 102).r, lessThan(40));
      expect(decoded.getPixel(200, 150).r, greaterThan(230));
      expect(jpeg.length, lessThan(1024 * 1024));
    },
  );

  test('long receipts retain proportional text resolution and respect the long edge limit', () {
    final jpeg = prepareInvoiceImage(receiptPng(400, 6400));
    final decoded = img.decodeJpg(jpeg)!;
    expect(decoded.width, 375);
    expect(decoded.height, 6000);
  });

  test('camera EXIF orientation is baked into the uploaded image', () {
    final image = img.decodePng(receiptPng(500, 700))!;
    image.exif.imageIfd.orientation = 6;
    final decoded = img.decodeJpg(prepareInvoiceImage(img.encodeJpg(image)))!;
    expect(decoded.width, 700);
    expect(decoded.height, 500);
    expect(decoded.exif.imageIfd.orientation, anyOf(isNull, equals(1)));
  });

  test(
    'capture cache is reused by Gemini and cleanup leaves the original intact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'moneva_image_preparation_test_',
      );
      final source = File('${directory.path}/original.png');
      await source.writeAsBytes(receiptPng(600, 900));
      final preparation = InvoiceImagePreparation(
        temporaryDirectory: () async => directory,
      );
      File? prepared;
      try {
        prepared = await preparation.prepare(source);
        expect(prepared.path, isNot(source.path));
        final bytes = await InvoiceImagePreparation.bytesFor(prepared);
        expect(await InvoiceImagePreparation.bytesFor(prepared), same(bytes));
        final client = MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final parts = (body['contents'] as List).single['parts'] as List;
          final inline = parts.last['inline_data'] as Map;
          expect(inline['mime_type'], 'image/jpeg');
          expect(base64Decode(inline['data'] as String), bytes);
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'STOP',
                  'content': {
                    'parts': [
                      {
                        'text': jsonEncode({
                          'merchant': 'Shop',
                          'currency': 'EUR',
                          'items': [],
                        }),
                      },
                    ],
                  },
                },
              ],
            }),
            200,
          );
        });
        final draft = await GeminiInvoiceExtractor(
          client: client,
          keyLoader: () async => 'synthetic-test-key',
        ).extract([prepared], {'Groceries'});
        expect(draft.merchant, 'Shop');
        client.close();
      } finally {
        await preparation.dispose();
        expect(await source.exists(), isTrue);
        if (prepared != null) expect(await prepared.exists(), isFalse);
        await source.delete();
        await directory.delete();
      }
    },
  );

  test('failed image preparation cleans only its own files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'moneva_invalid_image_test_',
    );
    final source = File('${directory.path}/invalid.jpg');
    await source.writeAsString('not an image');
    final preparation = InvoiceImagePreparation(
      temporaryDirectory: () async => directory,
    );
    await expectLater(preparation.prepare(source), throwsFormatException);
    await preparation.dispose();
    expect(await source.readAsString(), 'not an image');
    await source.delete();
    await directory.delete();
  });

  test(
    'removing a prepared page releases its cache without touching the source',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'moneva_remove_prepared_page_',
      );
      final source = File('${directory.path}/source.png');
      await source.writeAsBytes(receiptPng(100, 200));
      final preparation = InvoiceImagePreparation(
        temporaryDirectory: () async => directory,
      );
      try {
        final first = await preparation.prepare(source);
        await preparation.release(first);
        expect(await first.exists(), isFalse);
        final second = await preparation.prepare(source);
        expect(second.path, isNot(first.path));
        expect(await second.exists(), isTrue);
        await preparation.release(source);
        expect(await source.exists(), isTrue);
      } finally {
        await preparation.dispose();
        await source.delete();
        await directory.delete();
      }
    },
  );
  test(
    'native downsampling handles oversized rotated scans before JPEG encoding',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'moneva_native_resize_',
      );
      final source = File('${directory.path}/rotated.jpg');
      try {
        final image = img.decodePng(receiptPng(400, 6400))!;
        image.exif.imageIfd.orientation = 6;
        await source.writeAsBytes(img.encodeJpg(image, quality: 90));
        final prepared = img.decodeJpg(
          await InvoiceImagePreparation.bytesFor(source),
        )!;
        expect(prepared.width, 6000);
        expect(prepared.height, 375);
        expect(await source.exists(), isTrue);
      } finally {
        await source.delete();
        await directory.delete();
      }
    },
  );
}
