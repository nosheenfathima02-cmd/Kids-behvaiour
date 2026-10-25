import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/kid_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/welcome_screen.dart';
import 'store.dart';
import 'widgets.dart';

const brandColor = Color(0xFF0D6B5B);

/// `--dart-define=USE_EMULATOR=true` talks to the local Firebase emulator
/// instead of the real project. Use EMULATOR_HOST=10.0.2.2 for an Android emulator.
const useEmulator = bool.fromEnvironment('USE_EMULATOR');
const emulatorHost = String.fromEnvironment(
  'EMULATOR_HOST',
  defaultValue: 'localhost',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (useEmulator) {
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  }
  final store = await AppStore.load();
  runApp(SuperMomApp(store: store));
}

ThemeData buildTheme(Color seed, Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
  useMaterial3: true,
  cardTheme: const CardThemeData(elevation: 0),
);

class SuperMomApp extends StatelessWidget {
  const SuperMomApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: 'Super Mom',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brandColor, Brightness.light),
        darkTheme: buildTheme(brandColor, Brightness.dark),
        scaffoldMessengerKey: _messenger,
        home: _ErrorListener(store: store, child: const _Root()),
      ),
    );
  }
}

final _messenger = GlobalKey<ScaffoldMessengerState>();

/// Shows save errors (for example a tick the server refused) as a snackbar.
class _ErrorListener extends StatefulWidget {
  const _ErrorListener({required this.store, required this.child});
  final AppStore store;
  final Widget child;

  @override
  State<_ErrorListener> createState() => _ErrorListenerState();
}

class _ErrorListenerState extends State<_ErrorListener> {
  @override
  void initState() {
    super.initState();
    widget.store.errors.addListener(_show);
  }

  void _show() {
    final msg = widget.store.errors.value;
    if (msg == null) return;
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(msg)));
    widget.store.errors.value = null;
  }

  @override
  void dispose() {
    widget.store.errors.removeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return switch (store.phase) {
      Phase.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      Phase.welcome => const WelcomeScreen(),
      Phase.parentNeedsFamily => const SetupScreen(),
      Phase.parentNeedsPin => const SetPinScreen(),
      Phase.deviceUnlinked => const UnlinkedScreen(),
      Phase.ready => const KidEntryScreen(),
    };
  }
}
