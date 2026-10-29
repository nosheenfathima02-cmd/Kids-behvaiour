// Firebase project "super-mom-43520". Values from android/app/google-services.json;
// they identify the project and are not secret (security comes from the
// Firestore rules). The web and iPhone apps are not registered yet: the web
// build only works with the local emulator (`--dart-define=USE_EMULATOR=true`).
// Running `flutterfire configure` later regenerates this file for all platforms.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

  static FirebaseOptions get currentPlatform {
    if (useEmulator || kIsWeb) return emulator;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Super Mom is not registered for $defaultTargetPlatform in Firebase yet. '
          'Add the app in the Firebase console and run `flutterfire configure`.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB3RscePe_22zRF6SLzNV37Z_i8jxdl9Iw',
    appId: '1:407838898643:android:c73abf2f33add179309726',
    messagingSenderId: '407838898643',
    projectId: 'super-mom-43520',
    storageBucket: 'super-mom-43520.firebasestorage.app',
  );

  /// Only for the local Firebase emulator (tests and screenshots).
  static const FirebaseOptions emulator = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'demo-supermom',
  );
}
