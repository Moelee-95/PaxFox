import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/data/ledger_store.dart';
import 'core/presentation/app_theme.dart';
import 'core/presentation/store_status.dart';
import 'screens/main_screen.dart';
import 'screens/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/LICENSE.txt'));
  });
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.store});
  final LedgerStore? store;
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late Future<LedgerStore> _store;
  @override
  void initState() {
    super.initState();
    _store = widget.store == null
        ? LedgerStore.open()
        : Future.value(widget.store);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<LedgerStore>(
    future: _store,
    builder: (context, snapshot) {
      final store = snapshot.data;
      return MaterialApp(
        title: 'Paxlee',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        builder: store == null
            ? null
            : (context, child) => StoreStatus(store: store, child: child!),
        home: snapshot.hasError
            ? Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Local storage could not be opened. Your data has not been reset.',
                      ),
                      FilledButton(
                        onPressed: () =>
                            setState(() => _store = LedgerStore.open()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            : store == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : ListenableBuilder(
                listenable: store,
                child: MainScreen(store: store),
                builder: (context, child) =>
                    store.setupCompleted ? child! : SetupScreen(store: store),
              ),
      );
    },
  );
}
