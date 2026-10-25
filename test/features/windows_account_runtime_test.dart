import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ripot/core/firebase/account_runtime.dart';
import 'package:ripot/core/firebase/account_session.dart';
import 'package:ripot/core/firebase/firebase_bootstrap.dart';
import 'package:ripot/core/firebase/windows_account_session.dart';
import 'package:ripot/core/firebase/windows_cloud_documents.dart';
import 'package:ripot/core/firebase/windows_session_store.dart';
import 'package:ripot/features/access/data/access_repository.dart';
import 'package:ripot/features/access/domain/access_state.dart';
import 'package:ripot/features/access/providers/access_provider.dart';
import 'package:ripot/features/auth/providers/auth_provider.dart';
import 'package:ripot/features/reports/data/templates_repository.dart';

class _MemoryStore implements SessionStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Session implements AccountSession {
  final controller = StreamController<AccountUser?>.broadcast(sync: true);
  AccountUser? user;
  void switchTo(String? uid) {
    user = uid == null ? null : AccountUser(uid: uid);
    controller.add(user);
  }

  @override
  AccountUser? get currentUser => user;
  @override
  Stream<AccountUser?> authStateChanges() => controller.stream;
  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      'fictional-token';
  @override
  Future<void> signOut() async => switchTo(null);
  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {}
  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}
}

class _AccessRepo extends AccessRepository {
  final reply = Completer<AccessState>();
  @override
  Future<AccessState?> loadCached() async => null;
  @override
  Future<AccessState> load({bool refreshPlay = true}) => reply.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows startup uses REST services without initializing native Firebase',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(Firebase.apps, isEmpty);
      final account = WindowsAccountSession(
        projectId: 'demo-ripot-windows',
        apiKey: 'test-key',
        store: _MemoryStore(),
      );
      await AccountRuntime.initializeWindows(session: account);
      await FirebaseBootstrap.initializeIfConfigured();
      expect(AccountRuntime.session, same(account));
      expect(AccountRuntime.documents, isA<WindowsCloudDocuments>());
      expect(Firebase.apps, isEmpty);
    },
  );

  test(
    'sign-out synchronously clears Premium and discards the previous account load',
    () async {
      final session = _Session();
      final repo = _AccessRepo();
      final access = AccessProvider(repo: repo);
      final auth = AuthProvider(
        accessProvider: access,
        templatesRepository: TemplatesRepository(),
        session: session,
      );
      session.switchTo('account-a');
      await Future<void>.delayed(Duration.zero);
      access.acceptVerifiedPremium(
        DateTime.now().add(const Duration(hours: 1)),
      );
      expect(access.safeState.isPremiumLike, isTrue);
      session.switchTo(null);
      expect(access.safeState.isPremiumLike, isFalse);
      expect(auth.isSignedIn, isFalse);
      repo.reply.complete(
        AccessState.initial(
          installationId: 'demo-install',
        ).copyWith(plan: RipotPlan.premium),
      );
      await Future<void>.delayed(Duration.zero);
      expect(access.safeState.isPremiumLike, isFalse);
      auth.dispose();
      access.dispose();
      await session.controller.close();
    },
  );
}
