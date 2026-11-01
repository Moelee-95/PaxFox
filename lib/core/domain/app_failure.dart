import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A message safe to display, without provider responses or private data.
class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;

  @override
  String toString() => message;

  static String messageFor(
    Object error, {
    required String fallback,
  }) => switch (error) {
    AppFailure(:final message) => message,
    TimeoutException() =>
      'The request timed out. Please try again when the connection improves.',
    SocketException() || http.ClientException() =>
      'Could not connect. Check your internet connection and try again.',
    FileSystemException() => 'Could not access the file. Check storage space and permissions, then retry.',
    _ => fallback,
  };

  static String serviceMessage(int status, String service) => switch (status) {
    401 || 403 => '$service access is unavailable. Please try again later.',
    408 || 504 => '$service took too long to respond. Please retry.',
    429 => '$service is busy or its usage limit was reached. Please try later.',
    >= 500 => '$service is temporarily unavailable. Please try again later.',
    _ =>
      '$service could not complete the request (HTTP $status). Please retry.',
  };
}
