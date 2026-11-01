import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../../core/domain/app_failure.dart';

class GeminiKeyProvider {
  static const String configUrl =
      'https://alhayali.de/card_lens/gemini-config.json';

  // This protects the key from plain-text discovery only. Because the app must
  // decrypt the remote value, this encryption key is intentionally bundled
  // with the app and should not be treated as a server-side secret.
  static const String _encryptionKeyBase64 =
      'VGYIC/pnuoIfhXssKgcNVEfHUqaeY8Ld0MSyGiNCbYo=';

  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<String> fetchKey({http.Client? client}) async {
    final ownsClient = client == null;
    final requestClient = client ?? http.Client();

    try {
      final baseUri = Uri.parse(configUrl);
      final requestUri = baseUri.replace(
        queryParameters: {
          ...baseUri.queryParameters,
          'requestedAt': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final response = await requestClient
          .get(
            requestUri,
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache, no-store',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw GeminiKeyException(
          AppFailure.serviceMessage(
            response.statusCode,
            'Invoice connection service',
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          decoded['algorithm'] != 'AES-256-GCM') {
        throw const GeminiKeyException('Unsupported key configuration.');
      }

      final secretBox = SecretBox(
        base64Decode(_requiredString(decoded, 'ciphertext')),
        nonce: base64Decode(_requiredString(decoded, 'nonce')),
        mac: Mac(base64Decode(_requiredString(decoded, 'mac'))),
      );
      final clearBytes = await _cipher.decrypt(
        secretBox,
        secretKey: SecretKey(base64Decode(_encryptionKeyBase64)),
      );
      final apiKey = utf8.decode(clearBytes).trim();

      if (apiKey.length < 20 || apiKey.contains(RegExp(r'\s'))) {
        throw const GeminiKeyException('The decrypted API key is invalid.');
      }

      return apiKey;
    } on GeminiKeyException {
      rethrow;
    } catch (error) {
      throw GeminiKeyException(
        AppFailure.messageFor(
          error,
          fallback: 'Unable to load the Gemini configuration. Please try again later.',
        ),
      );
    } finally {
      if (ownsClient) requestClient.close();
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw GeminiKeyException('Missing configuration field: $key.');
    }
    return value;
  }
}

class GeminiKeyException extends AppFailure {
  const GeminiKeyException(super.message);
}
