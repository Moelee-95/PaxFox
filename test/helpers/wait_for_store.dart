import 'dart:async';

import 'package:moneva/core/data/ledger_store.dart';

Future<void> waitForStore(LedgerStore store, bool Function() ready) async {
  if (ready()) return;
  final completed = Completer<void>();
  void check() {
    if (ready() && !completed.isCompleted) completed.complete();
  }

  store.addListener(check);
  try {
    await completed.future.timeout(const Duration(seconds: 10));
  } finally {
    store.removeListener(check);
  }
}
