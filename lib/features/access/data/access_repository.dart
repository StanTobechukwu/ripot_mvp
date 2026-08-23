import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../../core/utils/ids.dart';
import '../domain/access_state.dart';

class AccessRepository {
  static const _installationIdKey = 'access.installationId';
  static const _stateKey = 'access.state';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();

  Future<String> getOrCreateInstallationId() async {
    final prefs = await _prefs;
    final existing = prefs.getString(_installationIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final id = newId('usr');
    await prefs.setString(_installationIdKey, id);
    return id;
  }

  Future<AccessState> load() async {
    final prefs = await _prefs;
    final config = await _loadRemoteConfigSafely();
    final raw = prefs.getString(_stateKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final state = AccessState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final configured = _normalizeState(_applyConfig(state, config));
        final normalized = _normalizeState(await _applyRemoteEntitlementSafely(configured));
        if (jsonEncode(normalized.toJson()) != jsonEncode(state.toJson())) {
          await save(normalized);
        }
        return normalized;
      } catch (_) {}
    }

    final installationId = await getOrCreateInstallationId();
    final configured = _normalizeState(
      _applyConfig(AccessState.initial(installationId: installationId, isEarlyUser: true), config),
    );
    final state = _normalizeState(await _applyRemoteEntitlementSafely(configured));
    await save(state);
    return state;
  }

  Future<void> save(AccessState state) async {
    final prefs = await _prefs;
    final normalized = _normalizeState(state);
    await prefs.setString(_stateKey, jsonEncode(normalized.toJson()));
    await _syncToFirestore(normalized);
  }

  AccessState _normalizeState(AccessState state) {
    if (state.plan == RipotPlan.trial && !state.isTrialActive) {
      return state.copyWith(
        plan: RipotPlan.free,
        updatedAt: DateTime.now(),
      );
    }
    return state;
  }

  AccessState _applyConfig(AccessState state, _AccessRemoteConfig config) {
    final cutoff = config.earlyAccessCutoffAt;
    final qualifiesByDate = cutoff == null || !state.createdAt.toLocal().isAfter(cutoff.toLocal());
    final isEarlyUser = config.earlyAccessEnabled && qualifiesByDate;
    return state.copyWith(
      isEarlyUser: isEarlyUser,
      earlyAccessEnabled: config.earlyAccessEnabled,
      earlyAccessDurationDays: config.earlyAccessDurationDays,
      earlyAccessCutoffAt: cutoff,
      premiumBillingEnabled: config.premiumBillingEnabled,
      premiumMessageTitle: config.premiumMessageTitle,
      premiumMessageBody: config.premiumMessageBody,
      updatedAt: state.updatedAt,
    );
  }



  AccessState _applyPersistedRemoteAccessState(AccessState state, Map<String, dynamic> data) {
    // Rehydrate normal user access state from Firestore. This prevents a reinstall
    // from restarting the premium-trial clock when the user signs back in.
    final remotePlan = _planFromJson(data['plan']);
    final remoteTrialStart = _dateFromJson(data['trialStartAtIso'] ?? data['trialStartAt']);
    final remoteTrialEnd = _dateFromJson(data['trialEndsAtIso'] ?? data['trialEndsAt']);
    final remotePremiumStart = _dateFromJson(data['premiumStartedAtIso'] ?? data['premiumStartedAt']);
    final remoteHasUsedTrial = data['hasUsedTrial'] is bool ? data['hasUsedTrial'] as bool : null;
    final remoteUpdatedAt = _dateFromJson(data['updatedAtIso'] ?? data['lastSyncedAtIso']);

    final hasMeaningfulRemoteState = remotePlan != null ||
        remoteTrialStart != null ||
        remoteTrialEnd != null ||
        remotePremiumStart != null ||
        remoteHasUsedTrial == true;
    if (!hasMeaningfulRemoteState) return state;

    return state.copyWith(
      plan: remotePlan ?? state.plan,
      trialStartAt: remoteTrialStart ?? state.trialStartAt,
      trialEndsAt: remoteTrialEnd ?? state.trialEndsAt,
      premiumStartedAt: remotePremiumStart ?? state.premiumStartedAt,
      hasUsedTrial: remoteHasUsedTrial ?? state.hasUsedTrial,
      updatedAt: remoteUpdatedAt ?? state.updatedAt,
    );
  }

  Future<AccessState> _applyRemoteEntitlementSafely(AccessState state) async {
    if (Firebase.apps.isEmpty) return state;
    try {
      final identity = await SyncIdentityResolver().resolve();
      final snap = await FirebaseFirestore.instance.collection('ripot_user_access').doc(identity.documentKey).get();
      final data = snap.data();
      if (data == null) return state;

      var next = _applyPersistedRemoteAccessState(state, data);
      final forceEarlyAccess = data['adminEarlyAccessEligible'];
      if (forceEarlyAccess is bool) {
        next = next.copyWith(isEarlyUser: forceEarlyAccess);
      }

      final duration = data['adminEarlyAccessDurationDays'];
      if (duration != null) {
        next = next.copyWith(
          earlyAccessDurationDays: _intFromJson(
            duration,
            fallback: next.earlyAccessDurationDays,
          ),
        );
      }

      final adminTrialEndsAt = _dateFromJson(data['adminTrialEndsAtIso'] ?? data['adminTrialEndsAt']);
      if (adminTrialEndsAt != null && adminTrialEndsAt.isAfter(DateTime.now())) {
        next = next.copyWith(
          plan: RipotPlan.trial,
          trialStartAt: next.trialStartAt ?? DateTime.now(),
          trialEndsAt: adminTrialEndsAt,
          hasUsedTrial: true,
          updatedAt: DateTime.now(),
        );
      }

      final overridePlan = _stringOrNull(data['adminPlanOverride'])?.toLowerCase();
      if (overridePlan == 'premium') {
        next = next.copyWith(
          plan: RipotPlan.premium,
          premiumStartedAt: next.premiumStartedAt ?? DateTime.now(),
          updatedAt: DateTime.now(),
        );
      } else if (overridePlan == 'free') {
        next = next.copyWith(
          plan: RipotPlan.free,
          updatedAt: DateTime.now(),
        );
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
      final snap = await FirebaseFirestore.instance.collection('ripot_app_config').doc('access').get();
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
      final db = FirebaseFirestore.instance;
      await db.collection('ripot_user_access').doc(identity.documentKey).set(
        {
          ...state.toJson(),
          'ownerType': identity.ownerType,
          'ownerId': identity.ownerId,
          'authUid': identity.authUid,
          'lastSyncedAtIso': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Stability first: never fail local save because cloud sync is unavailable.
    }
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final identity = await SyncIdentityResolver().resolve();
      if (!identity.isSignedInUser || identity.authUid == null) return;

      final localDoc = FirebaseFirestore.instance
          .collection('ripot_user_access')
          .doc(identity.installationId);
      final localSnap = await localDoc.get();
      if (!localSnap.exists) return;

      final localData = localSnap.data() ?? <String, dynamic>{};
      final userDoc = FirebaseFirestore.instance.collection('ripot_user_access').doc(identity.authUid);
      final userSnap = await userDoc.get();
      if (userSnap.exists) {
        // Do not overwrite an existing account entitlement with a fresh local
        // install state. This is what could restart the trial clock after reinstall.
        await userDoc.set(
          {
            'ownerType': 'user',
            'ownerId': identity.authUid,
            'authUid': identity.authUid,
            'installationId': identity.installationId,
            'lastSeenInstallationId': identity.installationId,
            'lastMigrationCheckAtIso': DateTime.now().toIso8601String(),
          },
          SetOptions(merge: true),
        );
        return;
      }

      await userDoc.set(
        {
          ...localData,
          'ownerType': 'user',
          'ownerId': identity.authUid,
          'authUid': identity.authUid,
          'installationId': identity.installationId,
          'migratedFromInstallationId': identity.installationId,
          'migratedAtIso': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
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
      : earlyAccessEnabled = true,
        earlyAccessDurationDays = AccessState.defaultEarlyAccessDurationDays,
        earlyAccessCutoffAt = null,
        premiumBillingEnabled = false,
        premiumMessageTitle = null,
        premiumMessageBody = null;

  factory _AccessRemoteConfig.fromJson(Map<String, dynamic> json) {
    return _AccessRemoteConfig(
      earlyAccessEnabled: (json['earlyAccessEnabled'] as bool?) ?? true,
      earlyAccessDurationDays: _intFromJson(
        json['earlyAccessDurationDays'],
        fallback: AccessState.defaultEarlyAccessDurationDays,
      ),
      earlyAccessCutoffAt: _dateFromJson(
        json['earlyAccessCutoffDateIso'] ?? json['earlyAccessCutoffAtIso'] ?? json['earlyAccessCutoffDate'],
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
