// Firebase settings for the neev-udaan project.
// Web is configured. For Android, iOS, macOS and Windows, run from the app/ folder:
//
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=neev-udaan
//
// which registers those apps and regenerates this file with all platforms.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError(
      'This platform is not configured yet. Run `flutterfire configure --project=neev-udaan` in the app/ folder.',
    );
  }

  // Firebase web config is public by design; access is controlled by security rules.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAl6mdi-AyPQbRR5zkOyVi0kRRG7h7dOEY',
    appId: '1:42776937513:web:e45d39d6e7450de7594838',
    messagingSenderId: '42776937513',
    projectId: 'neev-udaan',
    authDomain: 'neev-udaan.firebaseapp.com',
    storageBucket: 'neev-udaan.firebasestorage.app',
    measurementId: 'G-RPCVWBQXR1',
  );
}
