import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/firebase/sync_identity.dart';
import '../../../core/firebase/account_functions.dart';
import '../../../core/firebase/account_runtime.dart';
import '../../../core/firebase/account_session.dart';
import '../../../core/firebase/cloud_documents.dart';
import '../../../core/utils/ids.dart';
import '../domain/access_state.dart';
import 'account_access_cache.dart';
import 'windows_access_cache.dart';

class AccessRepository {
  AccessRepository({
    AccountSession? session,
    CloudDocuments? documents,
    ProtectedAccessCache? protectedCache,
  }) : _sessionOverride = session,
       _documentsOverride = documents,
       _protectedCacheOverride = protectedCache;
  final ProtectedAccessCache? _protectedCacheOverride;
  ProtectedAccessCache? get _protectedCache =>
      _protectedCacheOverride ??
      (AccountRuntime.usesWindowsRest ? const WindowsAccessCache() : null);
  final AccountSession? _sessionOverride;
  final CloudDocuments? _documentsOverride;
  AccountSession? get _session => _sessionOverride ?? AccountRuntime.session;
  CloudDocuments? get _documents =>
      _documentsOverride ?? AccountRuntime.documents;
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
    final cached = await _loadAccountCache(await _prefs, uid);
    if (_currentAuthUid() != uid || cached == null) return null;
    if (cached.plan == RipotPlan.premium && cached.premiumExpiresAt == null) {
      return null;
    }
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

    final cached = await _loadAccountCache(prefs, authUid);
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
    if (_currentAuthUid() != authUid) return _withoutAccountEntitlement(state);
    await _saveAccountCache(prefs, authUid, state);
    if (_currentAuthUid() != authUid) return _withoutAccountEntitlement(state);
    unawaited(_syncToFirestore(state));
    return state;
  }

  Future<void> save(AccessState state) async {
    final normalized = _normalizeState(state);
    final authUid = _currentAuthUid();
    if (authUid == null) return;

    final prefs = await _prefs;
    if (_currentAuthUid() != authUid) return;
    await _saveAccountCache(prefs, authUid, normalized);
    await _syncToFirestore(normalized);
  }

  Future<AccessState?> _loadAccountCache(
    SharedPreferences prefs,
    String authUid,
  ) async {
    String? raw;
    try {
      final protected = _protectedCache;
      raw = protected == null
          ? prefs.getString(AccountAccessCache.keyForUid(authUid))
          : await protected.read(authUid);
    } catch (_) {
      // Never fall back to an editable preferences entitlement on Windows.
      return null;
    }
    if (raw == null || raw.trim().isEmpty) return null;
    var cached = AccountAccessCache.decodeForUid(raw, authUid: authUid);
    // An administrator override with no expiry must be re-verified online;
    // neither the quick load nor the full offline load can extend it forever.
    if (cached?.plan == RipotPlan.premium && cached?.premiumExpiresAt == null) {
      return null;
    }
    if (cached != null) {
      // A pre-upgrade cache is not a fresh verification. Keep account/trial
      // history, but require an online check before granting Premium.
      final verified = cached.accessVerifiedAt;
      final maximum = verified?.add(AccessState.offlineAllowance);
      final deadline = cached.offlineAccessUntil;
      cached = cached.copyWith(
        offlineAccessUntil: maximum == null || deadline == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : (deadline.isBefore(maximum) ? deadline : maximum),
      );
      final now = DateTime.now();
      if (cached.accessLastSeenAt == null ||
          now.isAfter(cached.accessLastSeenAt!)) {
        cached = cached.copyWith(accessLastSeenAt: now);
      }
    }
    return cached;
  }

  Future<void> _saveAccountCache(
    SharedPreferences prefs,
    String authUid,
    AccessState state,
  ) async {
    final encoded = AccountAccessCache.encode(authUid: authUid, state: state);
    try {
      final protected = _protectedCache;
      if (protected != null) {
        await protected.write(authUid, encoded);
        await prefs.remove(AccountAccessCache.keyForUid(authUid));
      } else {
        await prefs.setString(AccountAccessCache.keyForUid(authUid), encoded);
      }
    } catch (_) {
      // A storage failure cannot undo a verified online grant. It simply means
      // that another online check will be needed on the next launch.
    }
  }

  String? _currentAuthUid() {
    try {
      final uid = _session?.currentUser?.uid.trim();
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
      accessVerifiedAt: null,
      offlineAccessUntil: null,
      accessLastSeenAt: null,
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
      fallback: 0,
    );
    final remoteFounderEarlyAccess = data['founderEarlyFeatureAccess'] is bool
        ? data['founderEarlyFeatureAccess'] as bool
        : false;

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
      founderCohort: remoteFounderCohort,
      founderNumber: remoteFounderNumber,
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
    final documents = _documents;
    if (documents == null) return state;

    if (_currentAuthUid() != authUid) {
      return _withoutAccountEntitlement(state);
    }

    try {
      if (refreshPlay) {
        try {
          await AccountFunctions.call(
            'refreshPlayEntitlement',
            timeout: const Duration(seconds: 8),
          ).timeout(const Duration(seconds: 8));
        } catch (_) {}
      }

      final data = await documents
          .get('ripot_user_access', authUid, serverOnly: true)
          .timeout(const Duration(seconds: 8));
      if (_currentAuthUid() != authUid) {
        return _withoutAccountEntitlement(state);
      }
      if (data == null) return _withoutAccountEntitlement(state).verifiedNow();

      var next = _applyPersistedRemoteAccessState(state, data);
      // A normal paid entitlement must have a server-supplied expiry. Only an
      // explicit administrator override below may be open-ended online.
      if (next.plan == RipotPlan.premium && next.premiumExpiresAt == null) {
        next = next.copyWith(plan: RipotPlan.free);
      }

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

      // This timestamp is refreshed only by a successful server-only read,
      // never by an offline load or writing the local cache back to disk.
      next = next.verifiedNow();
      if (next.plan == RipotPlan.premium && overridePlan != 'premium') {
        // Reading a stale Firestore document is not a fresh Play verification.
        // A failing Play refresh must not keep extending an annual subscriber's
        // offline window after a refund or revocation.
        final paidVerifiedAt = _dateFromJson(data['billingLastVerifiedAtIso']);
        final paidDeadline = paidVerifiedAt?.add(AccessState.offlineAllowance);
        if (paidDeadline == null ||
            paidDeadline.isBefore(next.offlineAccessUntil!)) {
          next = next.copyWith(
            offlineAccessUntil:
                paidDeadline ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        }
      }
      return next;
    } catch (_) {
      return _currentAuthUid() == authUid
          ? state
          : _withoutAccountEntitlement(state);
    }
  }

  Future<_AccessRemoteConfig> _loadRemoteConfigSafely() async {
    final documents = _documents;
    if (documents == null) return const _AccessRemoteConfig.defaults();
    try {
      final data = await documents
          .get('ripot_app_config', 'access')
          .timeout(const Duration(seconds: 3));
      if (data == null) return const _AccessRemoteConfig.defaults();
      return _AccessRemoteConfig.fromJson(data);
    } catch (_) {
      return const _AccessRemoteConfig.defaults();
    }
  }

  Future<void> _syncToFirestore(AccessState state) async {
    final documents = _documents;
    if (documents == null) return;
    try {
      final identity = await SyncIdentityResolver(session: _session).resolve();

      // Entitlement is server-authoritative. Flutter may sync only harmless
      // account/device metadata, and only for a signed-in account.
      if (!identity.isSignedInUser || identity.authUid == null) return;

      await documents.merge('ripot_user_access', identity.authUid!, {
        'ownerType': 'user',
        'ownerId': identity.authUid,
        'authUid': identity.authUid,
        'installationId': identity.installationId,
        'lastSeenInstallationId': identity.installationId,
        'lastClientSeenAtIso': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Stability first: never fail local save because cloud sync is unavailable.
    }
  }

  Future<AccessState?> activatePremiumTrialForSignedInAccount() async {
    final user = _session?.currentUser;
    if (user == null) return null;

    try {
      final result = await AccountFunctions.call('activatePremiumTrial');
      if (_currentAuthUid() != user.uid) return null;
      final data = Map<String, dynamic>.from(result as Map);
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
      return initial
          .copyWith(
            plan: RipotPlan.trial,
            trialStartAt: start,
            trialEndsAt: end,
            hasUsedTrial: true,
            updatedAt: DateTime.now(),
            founderCohort: data['founder'] == true ? 'founding_100' : null,
            founderNumber: _nullableIntFromJson(data['founderNumber']),
          )
          .verifiedNow();
    } catch (_) {
      return null;
    }
  }

  Future<void> syncFounderEntitlementForSignedInAccount() async {
    final user = _session?.currentUser;
    if (user == null) return;

    try {
      await AccountFunctions.call('syncFounderEntitlement');
    } catch (_) {
      // Non-blocking: normal access refresh still runs.
    }
  }

  Future<void> migrateCloudIdentityToSignedInUser() async {
    final documents = _documents;
    if (documents == null) return;
    try {
      final identity = await SyncIdentityResolver(session: _session).resolve();
      if (!identity.isSignedInUser || identity.authUid == null) return;

      // Never copy installation-level trial/Premium fields into an account.
      // Installation identity is not proof of entitlement ownership.
      //
      // Existing account entitlement remains untouched. New trial entitlement
      // is granted only by the server-authoritative Cloud Function.
      await documents.merge('ripot_user_access', identity.authUid!, {
        'ownerType': 'user',
        'ownerId': identity.authUid,
        'authUid': identity.authUid,
        'installationId': identity.installationId,
        'lastSeenInstallationId': identity.installationId,
        'legacyInstallationIdObserved': identity.installationId,
        'lastMigrationCheckAtIso': DateTime.now().toIso8601String(),
      });
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
