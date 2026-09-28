import 'dart:async';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional, minimal activity reporting. It never changes auth or access state.
/// Enable in a release only after Play Integrity and the callable are ready.
class InstallationActivity extends ChangeNotifier with WidgetsBindingObserver {
  static const rolloutEnabled = bool.fromEnvironment('RIPOT_ACTIVITY_ENABLED');
  static const _enabledKey = 'ripot.activity.enabled.v1';
  static const _secretKey = 'ripot.activity.secret.v1';
  static const _lastSuccessKey = 'ripot.activity.lastSuccess.v1';
  static const _lastIdentityKey = 'ripot.activity.lastIdentity.v1';
  static const _lastVersionKey = 'ripot.activity.lastVersion.v1';
  static const _failureCodeKey = 'ripot.activity.failureCode.v1';
  static const _failureAtKey = 'ripot.activity.failureAt.v1';
  static const _heartbeat = Duration(hours: 6);
  static const _retryDelay = Duration(minutes: 15);

  SharedPreferences? _prefs;
  PackageInfo? _package;
  StreamSubscription<User?>? _authSubscription;
  Timer? _timer;
  bool _enabled = false;
  bool _ready = false;
  bool _disposed = false;
  bool _sending = false;
  bool _appCheckReady = false;
  DateTime? _lastAttempt;
  String? _secret;

  bool get available => rolloutEnabled && !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;
  bool get ready => _ready;
  bool get enabled => _enabled;

  Future<void> initialize() async {
    if (!available || Firebase.apps.isEmpty || _disposed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _prefs = prefs;
      _enabled = prefs.getBool(_enabledKey) ?? true;
      _package = await PackageInfo.fromPlatform();
      if (_disposed) return;
      _secret = prefs.getString(_secretKey);
      if (_secret == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(_secret!)) {
        final random = Random.secure();
        _secret = List.generate(32, (_) => random.nextInt(256)
            .toRadixString(16).padLeft(2, '0')).join();
        await prefs.setString(_secretKey, _secret!);
      }
      if (_disposed) return;
      _ready = true;
      WidgetsBinding.instance.addObserver(this);
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (_) => unawaited(_report()),
        onError: (_) => unawaited(_saveFailure('auth-unavailable')),
      );
      _timer = Timer.periodic(_retryDelay, (_) => unawaited(_report()));
      notifyListeners();
      unawaited(_report());
    } catch (_) {
      await _saveFailure('initialization-failed');
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!_ready || _disposed) return;
    _enabled = value;
    notifyListeners();
    try {
      await _prefs!.setBool(_enabledKey, value);
    } catch (_) {
      await _saveFailure('preference-save-failed');
    }
    if (value) unawaited(_report());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_report());
  }

  String _identity() {
    final user = FirebaseAuth.instance.currentUser;
    return user == null || user.isAnonymous ? 'guest' : user.uid;
  }

  Future<void> _report() async {
    if (!_ready || !_enabled || _disposed || _sending) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final now = DateTime.now().toUtc();
    final identity = _identity();
    final version = '${_package!.version}+${_package!.buildNumber}';
    final lastSuccess = DateTime.tryParse(_prefs!.getString(_lastSuccessKey) ?? '');
    final changed = _prefs!.getString(_lastIdentityKey) != identity ||
        _prefs!.getString(_lastVersionKey) != version;
    if (lastSuccess != null && !changed && !lastSuccess.isAfter(now) &&
        lastSuccess.toIso8601String().substring(0, 10) == now.toIso8601String().substring(0, 10) &&
        now.difference(lastSuccess) < _heartbeat) return;
    // Back off failures and rapid auth changes without blocking app use.
    if (_lastAttempt != null && !now.isBefore(_lastAttempt!) &&
        now.difference(_lastAttempt!) < const Duration(seconds: 30)) return;
    if (_prefs!.getString(_failureCodeKey) != null && _lastAttempt != null &&
        !now.isBefore(_lastAttempt!) && now.difference(_lastAttempt!) < _retryDelay) return;

    _sending = true;
    _lastAttempt = now;
    try {
      if (!_appCheckReady) {
        // No debug provider in release and no project-wide enforcement changes.
        await FirebaseAppCheck.instance.activate(
          androidProvider: AndroidProvider.playIntegrity,
        ).timeout(const Duration(seconds: 15));
        _appCheckReady = true;
      }
      if (!_enabled || _disposed) return;
      final callable = FirebaseFunctions.instance.httpsCallable(
        'recordInstallationActivity',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );
      final response = await callable.call(<String, Object>{
        'schemaVersion': 1,
        'installationSecret': _secret!,
        'platform': 'android',
        'appVersion': _package!.version,
        'buildNumber': _package!.buildNumber,
      });
      if (response.data is! Map || response.data['recorded'] is! bool) {
        await _saveFailure('invalid-response');
        return;
      }
      await _prefs!.setString(_lastSuccessKey, now.toIso8601String());
      await _prefs!.setString(_lastIdentityKey, identity);
      await _prefs!.setString(_lastVersionKey, version);
      await _prefs!.remove(_failureCodeKey);
      await _prefs!.remove(_failureAtKey);
    } on FirebaseFunctionsException catch (error) {
      await _saveFailure(error.code);
    } on FirebaseException catch (error) {
      await _saveFailure(error.code);
    } on TimeoutException {
      await _saveFailure('timeout');
    } catch (_) {
      await _saveFailure('unavailable');
    } finally {
      _sending = false;
    }
  }

  Future<void> _saveFailure(String code) async {
    // Persist useful diagnostics, never payloads, account IDs, or secrets.
    debugPrint('Ripot activity reporting: $code');
    try {
      await _prefs?.setString(_failureCodeKey, code);
      await _prefs?.setString(_failureAtKey, DateTime.now().toUtc().toIso8601String());
    } catch (_) {
      // Local preference errors must not interrupt offline clinical work.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
