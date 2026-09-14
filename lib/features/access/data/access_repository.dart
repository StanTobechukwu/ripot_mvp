import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../../core/utils/ids.dart';
import '../domain/access_state.dart';
import 'account_access_cache.dart';

class AccessRepository {
  static const _installationIdKey = 'access.installationId';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String> getOrCreateInstallationId() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = newId('usr');
    await prefs.setString(_installationIdKey, id);
    return id;
  }

  /// Display only the current account's previously verified, unexpired access.
  Future<AccessState?> loadCached() async {
    final uid = _currentAuthUid();
    if (uid == null) return null;
    final cached = _loadAccountCache(await _prefs, uid);
    if (_currentAuthUid() != uid || cached == null) return null;
    if (cached.plan == RipotPlan.premium && cached.premiumExpiresAt == null)
      return null;
    return _normalizeState(cached);
  }

  Future<AccessState> load({bool refreshPlay = true}) async {
    final prefs = await _prefs;
    final installationId = await getOrCreateInstallationId();
    final authUid = _currentAuthUid();
    final configFuture = _loadRemoteConfigSafely();

    // Premium and trial access are account-owned. A signed-out installation
    // must never inherit the last signed-in account's cached entitlement.
    if (authUid == null) {
      return _normalizeState(
        _withoutAccountEntitlement(
          _applyConfig(
            AccessState.initial(installationId: installationId),
            await configFuture,
          ),
        ),
      );
    }

    final cached = _loadAccountCache(prefs, authUid);
    final configured = _normalizeState(
      _applyConfig(
        cached ?? AccessState.initial(installationId: installationId),
        await configFuture,
      ),
    );
    final state = _normalizeState(
      await _applyRemoteEntitlementSafely(
        configured,
        authUid: authUid,
        refreshPlay: refreshPlay,
      ),
    );
    await _saveAccountCache(prefs, authUid, state);
    unawaited(_syncToFirestore(state));
    return state;
  }

  Future<void> save(AccessState state) async {
    final normalized = _normalizeState(state);
    final authUid = _currentAuthUid();
    if (authUid == null) return;

    final prefs = await _prefs;
    await _saveAccountCache(prefs, authUid, normalized);
    await _syncToFirestore(normalized);
  }

  AccessState? _loadAccountCache(SharedPreferences prefs, String authUid) {
    final raw = prefs.getString(AccountAccessCache.keyForUid(authUid));
    if (raw == null || raw.trim().isEmpty) return null;
    return AccountAccessCache.decodeForUid(raw, authUid: authUid);
  }

  Future<void> _saveAccountCache(
    SharedPreferences prefs,
    String authUid,
    AccessState state,
  ) async {
    await prefs.setString(
      AccountAccessCache.keyForUid(authUid),
      AccountAccessCache.encode(authUid: authUid, state: state),
    );
  }

  String? _currentAuthUid() {
    if (Firebase.apps.isEmpty) return null;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim();
      return uid == null || uid.isEmpty ? null : uid;
    } catch (_) {
      return null;
    }
  }

  AccessState _normalizeState(AccessState state) {
    if (state.plan == RipotPlan.premium &&
        state.premiumExpiresAt != null &&
        !state.premiumExpiresAt!.isAfter(DateTime.now())) {
      return state.copyWith(plan: RipotPlan.free);
    }
    if (state.plan == RipotPlan.trial && !state.isTrialActive) {
      return state.copyWith(plan: RipotPlan.free, updatedAt: DateTime.now());
    }
    return state;
  }

  AccessState _applyConfig(AccessState state, _AccessRemoteConfig config) {
    return state.copyWith(
      // Legacy early-access settings may still control marketing, but they
      // must never calculate or extend account entitlement on the client.
      isEarlyUser: false,
      earlyAccessEnabled: config.earlyAccessEnabled,
      earlyAccessDurationDays: config.earlyAccessDurationDays,
      earlyAccessCutoffAt: config.earlyAccessCutoffAt,
      premiumBillingEnabled: config.premiumBillingEnabled,
      premiumMessageTitle: config.premiumMessageTitle,
      premiumMessageBody: config.premiumMessageBody,
      updatedAt: state.updatedAt,
    );
  }

  AccessState _withoutAccountEntitlement(AccessState state) {
    return state.copyWith(
      plan: RipotPlan.free,
      isEarlyUser: false,
      trialStartAt: null,
      trialEndsAt: null,
      premiumStartedAt: null,
      premiumExpiresAt: null,
      hasUsedTrial: false,
      founderCohort: null,
      founderNumber: null,
      founderFirstYearDiscountPercent: 0,
      founderEarlyFeatureAccess: false,
      updatedAt: state.updatedAt,
    );
  }

  AccessState _applyPersistedRemoteAccessState(
    AccessState state,
    Map<String, dynamic> data,
  ) {
    // Rehydrate normal user access state from Firestore. This prevents a reinstall
    // from restarting the premium-trial clock when the user signs back in.
    final remotePlan = _planFromJson(data['plan']);
    final remoteTrialStart = _dateFromJson(
      data['trialStartAtIso'] ?? data['trialStartAt'],
    );
    final remoteTrialEnd = _dateFromJson(
      data['trialEndsAtIso'] ?? data['trialEndsAt'],
    );
    final remotePremiumStart = _dateFromJson(
      data['premiumStartedAtIso'] ?? data['premiumStartedAt'],
    );
    final remoteHasUsedTrial = data['hasUsedTrial'] is bool
        ? data['hasUsedTrial'] as bool
        : null;
    final remoteUpdatedAt = _dateFromJson(
      data['updatedAtIso'] ?? data['lastSyncedAtIso'],
    );
    final remoteFounderCohort = _stringOrNull(data['founderCohort']);
    final remoteFounderNumber = _nullableIntFromJson(data['founderNumber']);
    final remoteFounderDiscount = _intFromJson(
      data['founderFirstYearDiscountPercent'],
      fallback: state.founderFirstYearDiscountPercent,
    );
    final remoteFounderEarlyAccess = data['founderEarlyFeatureAccess'] is bool
        ? data['founderEarlyFeatureAccess'] as bool
        : state.founderEarlyFeatureAccess;

    final hasMeaningfulRemoteState =
        remotePlan != null ||
        remoteTrialStart != null ||
        remoteTrialEnd != null ||
        remotePremiumStart != null ||
        remoteHasUsedTrial == true ||
        remoteFounderCohort != null ||
        remoteFounderNumber != null;
    if (!hasMeaningfulRemoteState) {
      return _withoutAccountEntitlement(state);
    }

    return state.copyWith(
      plan: remotePlan ?? state.plan,
      trialStartAt: remoteTrialStart ?? state.trialStartAt,
      trialEndsAt: remoteTrialEnd ?? state.trialEndsAt,
      premiumStartedAt: remotePremiumStart ?? state.premiumStartedAt,
      premiumExpiresAt: _dateFromJson(data['playEntitlementExpiresAtIso']),
      hasUsedTrial: remoteHasUsedTrial ?? state.hasUsedTrial,
      founderCohort: remoteFounderCohort ?? state.founderCohort,
      founderNumber: remoteFounderNumber ?? state.founderNumber,
      founderFirstYearDiscountPercent: remoteFounderDiscount,
      founderEarlyFeatureAccess: remoteFounderEarlyAccess,
      updatedAt: remoteUpdatedAt ?? state.updatedAt,
    );
  }

  Future<AccessState> _applyRemoteEntitlementSafely(
    AccessState state, {
    required String authUid,
    bool refreshPlay = true,
  }) async {
    if (Firebase.apps.isEmpty) return state;

    if (_currentAuthUid() != authUid) {
      return _withoutAccountEntitlement(state);
    }

    try {
      if (refreshPlay)
        try {
          final callable = FirebaseFunctions.instance.httpsCallable(
            'refreshPlayEntitlement',
          );
          await callable
              .call(<String, dynamic>{})
              .timeout(const Duration(seconds: 8));
        } catch (_) {}

      final snap = await FirebaseFirestore.instance
          .collection('ripot_user_access')
          .doc(authUid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      if (_currentAuthUid() != authUid) {
        return _withoutAccountEntitlement(state);
      }
      final data = snap.data();
      if (data == null) return _withoutAccountEntitlement(state);

      var next = _applyPersistedRemoteAccessState(state, data);

      final adminTrialEndsAt = _dateFromJson(
        data['adminTrialEndsAtIso'] ?? data['adminTrialEndsAt'],
      );
      if (adminTrialEndsAt != null &&
          adminTrialEndsAt.isAfter(DateTime.now())) {
        next = next.copyWith(
          plan: RipotPlan.trial,
          trialStartAt: next.trialStartAt ?? DateTime.now(),
          trialEndsAt: adminTrialEndsAt,
          hasUsedTrial: true,
          updatedAt: DateTime.now(),
        );
      }

      final overridePlan = _stringOrNull(
        data['adminPlanOverride'],
      )?.toLowerCase();
      if (overridePlan == 'premium') {
        next = next.copyWith(
          plan: RipotPlan.premium,
          premiumStartedAt: next.premiumStartedAt ?? DateTime.now(),
          premiumExpiresAt: null,
          updatedAt: DateTime.now(),
        );
      } else if (overridePlan == 'free') {
        next = next.copyWith(plan: RipotPlan.free, updatedAt: DateTime.now());
      } else if (overridePlan == 'trial' && adminTrialEndsAt != null) {
        next = next.copyWith(
          plan: RipotPlan.trial,
          trialStartAt: next.trialStartAt ?? DateTime.now(),
          trialEndsAt: adminTrialEndsAt,
          hasUsedTrial: true,
          updatedAt: DateTime.now(),
        );
      }

      return next;
    } catch (_) {
      return state;
    }
  }

  Future<_AccessRemoteConfig> _loadRemoteConfigSafely() async {
    if (Firebase.apps.isEmpty) return const _AccessRemoteConfig.defaults();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ripot_app_config')
          .doc('access')
          .get()
          .timeout(const Duration(seconds: 3));
      final data = snap.data();
      if (data == null) return const _AccessRemoteConfig.defaults();
      return _AccessRemoteConfig.fromJson(data);
    } catch (_) {
      return const _AccessRemoteConfig.defaults();
    }
  }

  Future<void> _syncToFirestore(AccessState state) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final identity = await SyncIdentityResolver().resolve();

      // Entitlement is server-authoritative. Flutter may sync only harmless
      // account/device metadata, and only for a signed-in account.
      if (!identity.isSignedInUser || identity.authUid == null) return;

      final db = FirebaseFirestore.instance;
      await db.collection('ripot_user_access').doc(identity.authUid).set({
        'ownerType': 'user',
        'ownerId': identity.authUid,
        'authUid': identity.authUid,
        'installationId': identity.installationId,
        'lastSeenInstallationId': identity.installationId,
        'lastClientSeenAtIso': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Stability first: never fail local save because cloud sync is unavailable.
    }
  }

  Future<AccessState?> activatePremiumTrialForSignedInAccount() async {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'activatePremiumTrial',
      );
      final result = await callable.call(<String, dynamic>{});
      if (_currentAuthUid() != user.uid) return null;
      final data = Map<String, dynamic>.from(result.data as Map);
      // Only a newly granted trial is installed from the callable response.
      // An already-used response is reconciled from the authoritative document.
      if (data['activated'] != true) return null;
      final start = _dateFromJson(data['trialStartAtIso']);
      final end = _dateFromJson(data['trialEndsAtIso']);
      if (start == null || end == null) return null;
      final initial =
          await loadCached() ??
          AccessState.initial(
            installationId: await getOrCreateInstallationId(),
          );
      if (_currentAuthUid() != user.uid) return null;
      return initial.copyWith(
        plan: RipotPlan.trial,
        trialStartAt: start,
        trialEndsAt: end,
        hasUsedTrial: true,
        updatedAt: DateTime.now(),
        founderCohort: data['founder'] == true ? 'founding_100' : null,
        founderNumber: _nullableIntFromJson(data['founderNumber']),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> syncFounderEntitlementForSignedInAccount() async {
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'syncFounderEntitlement',
      );
      await callable.call(<String, dynamic>{});
    } catch (_) {
      // Non-blocking: normal access refresh still runs.
    }
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final identity = await SyncIdentityResolver().resolve();
      if (!identity.isSignedInUser || identity.authUid == null) return;

      // Never copy installation-level trial/Premium fields into an account.
      // Installation identity is not proof of entitlement ownership.
      //
      // Existing account entitlement remains untouched. New trial entitlement
      // is granted only by the server-authoritative Cloud Function.
      await FirebaseFirestore.instance
          .collection('ripot_user_access')
          .doc(identity.authUid)
          .set({
            'ownerType': 'user',
            'ownerId': identity.authUid,
            'authUid': identity.authUid,
            'installationId': identity.installationId,
            'lastSeenInstallationId': identity.installationId,
            'legacyInstallationIdObserved': identity.installationId,
            'lastMigrationCheckAtIso': DateTime.now().toIso8601String(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }
}

class _AccessRemoteConfig {
  final bool earlyAccessEnabled;
  final int earlyAccessDurationDays;
  final DateTime? earlyAccessCutoffAt;
  final bool premiumBillingEnabled;
  final String? premiumMessageTitle;
  final String? premiumMessageBody;

  const _AccessRemoteConfig({
    required this.earlyAccessEnabled,
    required this.earlyAccessDurationDays,
    this.earlyAccessCutoffAt,
    required this.premiumBillingEnabled,
    this.premiumMessageTitle,
    this.premiumMessageBody,
  });

  const _AccessRemoteConfig.defaults()
    : earlyAccessEnabled = false,
      earlyAccessDurationDays = AccessState.defaultEarlyAccessDurationDays,
      earlyAccessCutoffAt = null,
      premiumBillingEnabled = false,
      premiumMessageTitle = null,
      premiumMessageBody = null;

  factory _AccessRemoteConfig.fromJson(Map<String, dynamic> json) {
    return _AccessRemoteConfig(
      earlyAccessEnabled: (json['earlyAccessEnabled'] as bool?) ?? false,
      earlyAccessDurationDays: _intFromJson(
        json['earlyAccessDurationDays'],
        fallback: AccessState.defaultEarlyAccessDurationDays,
      ),
      earlyAccessCutoffAt: _dateFromJson(
        json['earlyAccessCutoffDateIso'] ??
            json['earlyAccessCutoffAtIso'] ??
            json['earlyAccessCutoffDate'],
      ),
      premiumBillingEnabled: (json['premiumBillingEnabled'] as bool?) ?? false,
      premiumMessageTitle: _stringOrNull(json['premiumMessageTitle']),
      premiumMessageBody: _stringOrNull(json['premiumMessageBody']),
    );
  }
}

RipotPlan? _planFromJson(Object? value) {
  final raw = _stringOrNull(value)?.toLowerCase();
  if (raw == null) return null;
  for (final plan in RipotPlan.values) {
    if (plan.name == raw) return plan;
  }
  return null;
}

int? _nullableIntFromJson(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

int _intFromJson(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _dateFromJson(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}
