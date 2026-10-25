import 'package:flutter/material.dart';

import 'core/data/ledger_store.dart';
import 'screens/main_screen.dart';
import 'screens/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Moneva',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF00796B),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xFF00796B),
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: FutureBuilder<LedgerStore>(
      future: _store,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
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
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final store = snapshot.data!;
        return ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.setupCompleted
              ? MainScreen(store: store)
              : SetupScreen(store: store),
        );
      },
    ),
  );
}
