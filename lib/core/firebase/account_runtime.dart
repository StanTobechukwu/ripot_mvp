import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options.dart';
import 'account_session.dart';
import 'cloud_documents.dart';
import 'windows_account_session.dart';
import 'windows_cloud_documents.dart';
import 'windows_session_store.dart';

/// Windows deliberately does not initialize the development-only native
/// Firebase Auth/Firestore SDKs. All other platforms keep their SDK path.
class AccountRuntime {
  static WindowsAccountSession? _windowsSession;
  static bool get usesWindowsRest =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Future<void> initializeWindows({
    WindowsAccountSession? session,
  }) async {
    final options = DefaultFirebaseOptions.windows;
    final account = _windowsSession ??=
        session ??
        WindowsAccountSession(
          projectId: options.projectId,
          apiKey: options.apiKey,
          store: WindowsSessionStore(options.projectId),
        );
    await account.initialize();
  }

  static AccountSession? get session {
    if (usesWindowsRest) return _windowsSession;
    return Firebase.apps.isEmpty
        ? null
        : FirebaseAccountSession(FirebaseAuth.instance);
  }

  static CloudDocuments? get documents {
    if (usesWindowsRest) {
      final account = _windowsSession;
      return account == null
          ? null
          : WindowsCloudDocuments(
              projectId: account.projectId,
              session: account,
            );
    }
    return Firebase.apps.isEmpty
        ? null
        : FirebaseCloudDocuments(FirebaseFirestore.instance);
  }
}
