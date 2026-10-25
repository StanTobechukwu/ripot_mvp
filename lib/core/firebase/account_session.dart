import 'package:firebase_auth/firebase_auth.dart';

class AccountUser {
  const AccountUser({required this.uid, this.email});
  final String uid;
  final String? email;
}

abstract interface class AccountSession {
  AccountUser? get currentUser;
  Stream<AccountUser?> authStateChanges();
  Future<String?> idToken({bool forceRefresh = false});
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  });
  Future<void> sendPasswordResetEmail({required String email});
  Future<void> signOut();
}

/// Android and web continue to use their existing Firebase SDK implementation.
class FirebaseAccountSession implements AccountSession {
  FirebaseAccountSession(this.auth);
  final FirebaseAuth auth;
  static AccountUser? _user(User? user) =>
      user == null ? null : AccountUser(uid: user.uid, email: user.email);
  @override
  AccountUser? get currentUser => _user(auth.currentUser);
  @override
  Stream<AccountUser?> authStateChanges() => auth.authStateChanges().map(_user);
  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      auth.currentUser?.getIdToken(forceRefresh);
  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    await auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) =>
      auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> signOut() => auth.signOut();
}
