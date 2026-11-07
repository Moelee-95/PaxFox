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
        expect(request.url.host, 'api.moelee.de');
        expect(request.url.path, '/api/v1/gemini-config');
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
  test('custom source preserves existing query parameters', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'example.com');
      expect(request.url.path, '/custom.json');
      expect(request.url.queryParameters['app'], 'paxfox');
      expect(request.url.queryParameters, contains('requestedAt'));
      return http.Response('{}', 200);
    });
    await expectLater(
      GeminiKeyProvider.fetchKey(
        client: client,
        sourceUrl: 'https://example.com/custom.json?app=paxfox',
      ),
      throwsA(isA<GeminiKeyException>()),
    );
  });
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
