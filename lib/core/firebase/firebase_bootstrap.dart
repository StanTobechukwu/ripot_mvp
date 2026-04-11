import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseBootstrap {
  static Future<void> initializeIfConfigured() async {
    if (Firebase.apps.isNotEmpty) return;

    final options = _fromEnvironment();
    if (options == null) {
      debugPrint(
        'Firebase not initialized: web config was not provided. '
        'Local access gating will still work, while cloud sync stays disabled.',
      );
      return;
    }

    try {
      await Firebase.initializeApp(options: options);
      debugPrint('Firebase initialized for Ripot web sync.');
    } catch (error) {
      debugPrint('Firebase initialization skipped: $error');
    }
  }

  static FirebaseOptions? _fromEnvironment() {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    const measurementId = String.fromEnvironment('FIREBASE_MEASUREMENT_ID');

    if (apiKey.isEmpty || appId.isEmpty || messagingSenderId.isEmpty || projectId.isEmpty) {
      return null;
    }

    return  FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      authDomain: authDomain.isEmpty ? null : authDomain,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      measurementId: measurementId.isEmpty ? null : measurementId,
    );
  }
}
