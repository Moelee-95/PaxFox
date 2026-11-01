import 'package:flutter/foundation.dart';

import '../domain/app_failure.dart';

/// Keeps a form retryable after failure and ignores completion after disposal.
class AsyncAction extends ChangeNotifier {
  bool _disposed = false;
  bool busy = false;
  String? error;

  Future<bool> run(
    Future<void> Function() action, {
    required String failureMessage,
  }) async {
    if (busy || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return !_disposed;
    } catch (failure) {
      error = failure is ArgumentError
          ? '${failure.message}'
          : AppFailure.messageFor(failure, fallback: failureMessage);
      return false;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
