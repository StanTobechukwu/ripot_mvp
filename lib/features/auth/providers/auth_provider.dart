import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../access/providers/access_provider.dart';
import '../../reports/data/templates_repository.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AccessProvider accessProvider,
    required TemplatesRepository templatesRepository,
    FirebaseAuth? auth,
  })  : _accessProvider = accessProvider,
        _templatesRepository = templatesRepository,
        _auth = auth ?? FirebaseAuth.instance {
    _sub = _auth.authStateChanges().listen(_onAuthChanged);
    _currentUser = _auth.currentUser;
  }

  final AccessProvider _accessProvider;
  final TemplatesRepository _templatesRepository;
  final FirebaseAuth _auth;

  StreamSubscription<User?>? _sub;
  User? _currentUser;
  bool _busy = false;
  String? _error;
  bool _migrationAttemptedForCurrentUser = false;

  User? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get busy => _busy;
  String? get error => _error;
  String? get email => _currentUser?.email;

  Future<void> _onAuthChanged(User? user) async {
    _currentUser = user;
    _error = null;
    _migrationAttemptedForCurrentUser = false;
    notifyListeners();
    if (user != null) {
      await _migrateGuestCloudDataIfNeeded();
    }
  }

  Future<void> _migrateGuestCloudDataIfNeeded() async {
    if (_migrationAttemptedForCurrentUser || _currentUser == null) return;
    _migrationAttemptedForCurrentUser = true;
    try {
      await _accessProvider.migrateCloudIdentityToSignedInUser();
      await _templatesRepository.migrateCloudTemplatesToSignedInUser();
      await _accessProvider.refresh();
    } catch (_) {
      // Stability first: migration failures should not crash auth flow.
    }
    notifyListeners();
  }

  Future<bool> signIn({required String email, required String password}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'Unable to sign in right now.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> signUp({required String email, required String password}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'Unable to create account right now.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> sendPasswordReset({required String email}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _messageFor(e);
      return false;
    } catch (_) {
      _error = 'Unable to send password reset email right now.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _auth.signOut();
      await _accessProvider.refresh();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'That email is already linked to an account.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return e.message ?? 'Authentication failed.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
