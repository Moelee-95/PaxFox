import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moneva/features/receipts/gemini_key_provider.dart';

void main() {
  test(
    'Card Lens config protocol decrypts a synthetic key without exposing it',
    () async {
      const testKey = 'synthetic-test-key-never-a-real-api-key';
      final box = await AesGcm.with256bits().encrypt(
        utf8.encode(testKey),
        secretKey: SecretKey(
          base64Decode('VGYIC/pnuoIfhXssKgcNVEfHUqaeY8Ld0MSyGiNCbYo='),
        ),
        nonce: List<int>.generate(12, (i) => i),
      );
      final client = MockClient((request) async {
        expect(request.url.host, 'alhayali.de');
        expect(request.url.path, '/card_lens/gemini-config.json');
        expect(request.url.queryParameters, contains('requestedAt'));
        expect(request.headers['Cache-Control'], 'no-cache, no-store');
        return http.Response(
          jsonEncode({
            'version': 1,
            'algorithm': 'AES-256-GCM',
            'ciphertext': base64Encode(box.cipherText),
            'nonce': base64Encode(box.nonce),
            'mac': base64Encode(box.mac.bytes),
          }),
          200,
        );
      });
      expect(await GeminiKeyProvider.fetchKey(client: client), testKey);
    },
  );
  test(
    'config errors and malformed payloads are safe and fail closed',
    () async {
      for (final response in [
        http.Response('sensitive payload', 500),
        http.Response('{}', 200),
      ]) {
        await expectLater(
          GeminiKeyProvider.fetchKey(client: MockClient((_) async => response)),
          throwsA(
            isA<GeminiKeyException>().having(
              (e) => e.message,
              'safe error',
              isNot(contains('sensitive payload')),
            ),
          ),
        );
      }
    },
  );
}
