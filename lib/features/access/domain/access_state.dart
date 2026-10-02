import 'package:flutter/foundation.dart';

enum RipotPlan { free, trial, premium }

@immutable
class AccessState {
  static const int defaultEarlyAccessDurationDays = 84;
  static const int defaultStandardTrialDays = 21;

  final String installationId;
  final RipotPlan plan;
  final bool isEarlyUser;
  final DateTime? trialStartAt;
  final DateTime? trialEndsAt;
  final DateTime? premiumStartedAt;
  final DateTime? premiumExpiresAt;
  final bool hasUsedTrial;
  final String? founderCohort;
  final int? founderNumber;
  final int founderFirstYearDiscountPercent;
  final bool founderEarlyFeatureAccess;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? accessVerifiedAt;
  final DateTime? offlineAccessUntil;
  final DateTime? accessLastSeenAt;
  static const offlineAllowance = Duration(hours: 72);

  /// Remote-controllable access settings. Defaults are deliberately safe so the
  /// app still works when Firebase/Firestore is unavailable.
  final bool earlyAccessEnabled;
  final int earlyAccessDurationDays;
  final DateTime? earlyAccessCutoffAt;
  final bool premiumBillingEnabled;
  final String? premiumMessageTitle;
  final String? premiumMessageBody;

  const AccessState({
    required this.installationId,
    required this.plan,
    required this.isEarlyUser,
    required this.createdAt,
    required this.updatedAt,
    this.accessVerifiedAt,
    this.offlineAccessUntil,
    this.accessLastSeenAt,
    this.trialStartAt,
    this.trialEndsAt,
    this.premiumStartedAt,
    this.premiumExpiresAt,
    this.hasUsedTrial = false,
    this.founderCohort,
    this.founderNumber,
    this.founderFirstYearDiscountPercent = 0,
    this.founderEarlyFeatureAccess = false,
    this.earlyAccessEnabled = false,
    this.earlyAccessDurationDays = defaultEarlyAccessDurationDays,
    this.earlyAccessCutoffAt,
    this.premiumBillingEnabled = false,
    this.premiumMessageTitle,
    this.premiumMessageBody,
  });

  factory AccessState.initial({
    required String installationId,
    bool isEarlyUser = false,
  }) {
    final now = DateTime.now();
    return AccessState(
      installationId: installationId,
      plan: RipotPlan.free,
      isEarlyUser: isEarlyUser,
      createdAt: now,
      updatedAt: now,
    );
  }

  int get trialLengthDays {
    final startAt = trialStartAt;
    final endsAt = trialEndsAt;
    if (startAt != null && endsAt != null && endsAt.isAfter(startAt)) {
      return endsAt.difference(startAt).inDays;
    }
    return defaultStandardTrialDays;
  }

  /// The backend grants a trial and writes its immutable end timestamp.
  /// Never recalculate entitlement from client flags or marketing config.
  DateTime? get effectiveTrialEndsAt => trialEndsAt;

  bool get isTrialActive {
    if (plan != RipotPlan.trial) return false;
    final endsAt = effectiveTrialEndsAt;
    if (endsAt == null) return false;
    return DateTime.now().isBefore(endsAt);
  }

  // Trial dates still describe the server's trial even when offline access
  // needs rechecking. Billing must not offer a second purchase during that trial.
  bool get isPremiumLike =>
      _offlineWindowValid &&
      ((plan == RipotPlan.premium &&
              (premiumExpiresAt == null ||
                  DateTime.now().isBefore(premiumExpiresAt!))) ||
          isTrialActive);

  bool get _offlineWindowValid {
    final now = DateTime.now();
    if (offlineAccessUntil != null && !now.isBefore(offlineAccessUntil!)) {
      return false;
    }
    // Small clock corrections are harmless; a substantial rollback must be
    // checked online before restoring Premium access.
    for (final stamp in [accessVerifiedAt, accessLastSeenAt]) {
      if (stamp != null &&
          now.isBefore(stamp.subtract(const Duration(minutes: 5)))) {
        return false;
      }
    }
    return true;
  }

  bool get hasCurrentVerification =>
      accessVerifiedAt != null &&
      offlineAccessUntil != null &&
      _offlineWindowValid;

  bool get needsOnlineVerification =>
      (plan == RipotPlan.premium || isTrialActive) && !hasCurrentVerification;

  AccessState verifiedNow() {
    final now = DateTime.now();
    return copyWith(
      accessVerifiedAt: now,
      accessLastSeenAt: now,
      offlineAccessUntil: now.add(offlineAllowance),
    );
  }

  bool get canActivatePremiumTrial {
    // One trial per account. Only the server may grant it and choose its dates.
    if (plan == RipotPlan.premium || isPremiumLike) return false;
    return !hasUsedTrial && trialStartAt == null && trialEndsAt == null;
  }

  bool get hadTrialButExpired =>
      hasUsedTrial && !isPremiumLike && plan != RipotPlan.premium;

  bool get isFounding100 =>
      founderCohort == 'founding_100' &&
      founderNumber != null &&
      founderNumber! >= 1 &&
      founderNumber! <= 100;

  int get daysRemaining {
    final endsAt = effectiveTrialEndsAt;
    if (!isPremiumLike || endsAt == null) return 0;
    final diff = endsAt.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff + 1;
  }

  String get trialEndDateLabel {
    final endsAt = effectiveTrialEndsAt;
    if (endsAt == null) return '';
    return _dateOnly(endsAt);
  }

  // Stored final PDFs only. Editable drafts do not consume this allowance.
  int get maxSavedReports => isPremiumLike ? 100 : 10;
  int get maxSavedTemplates => isPremiumLike ? 20 : 4;
  int get maxImagesPerReport => isPremiumLike ? 12 : 4;

  bool get canRemoveBranding => isPremiumLike;
  bool get canUseImageLabels => isPremiumLike;
  bool get canUseLetterhead => isPremiumLike;
  bool get canUseCustomMargins => isPremiumLike;
  bool get canUseAdvancedLayout => isPremiumLike;
  bool get canUsePremiumTemplates => isPremiumLike;
  bool get canUseRecords => isPremiumLike;

  String get badgeLabel {
    switch (plan) {
      case RipotPlan.free:
        return 'Free';
      case RipotPlan.trial:
        return isPremiumLike ? 'Premium Trial' : 'Free';
      case RipotPlan.premium:
        return isPremiumLike ? 'Premium' : 'Free';
    }
  }

  AccessState copyWith({
    RipotPlan? plan,
    bool? isEarlyUser,
    Object? trialStartAt = _unset,
    Object? trialEndsAt = _unset,
    Object? premiumStartedAt = _unset,
    Object? premiumExpiresAt = _unset,
    bool? hasUsedTrial,
    Object? founderCohort = _unset,
    Object? founderNumber = _unset,
    int? founderFirstYearDiscountPercent,
    bool? founderEarlyFeatureAccess,
    DateTime? updatedAt,
    Object? accessVerifiedAt = _unset,
    Object? offlineAccessUntil = _unset,
    Object? accessLastSeenAt = _unset,
    bool? earlyAccessEnabled,
    int? earlyAccessDurationDays,
    Object? earlyAccessCutoffAt = _unset,
    bool? premiumBillingEnabled,
    Object? premiumMessageTitle = _unset,
    Object? premiumMessageBody = _unset,
  }) {
    return AccessState(
      installationId: installationId,
      plan: plan ?? this.plan,
      isEarlyUser: isEarlyUser ?? this.isEarlyUser,
      trialStartAt: identical(trialStartAt, _unset)
          ? this.trialStartAt
          : trialStartAt as DateTime?,
      trialEndsAt: identical(trialEndsAt, _unset)
          ? this.trialEndsAt
          : trialEndsAt as DateTime?,
      premiumStartedAt: identical(premiumStartedAt, _unset)
          ? this.premiumStartedAt
          : premiumStartedAt as DateTime?,
      hasUsedTrial: hasUsedTrial ?? this.hasUsedTrial,
      premiumExpiresAt: identical(premiumExpiresAt, _unset)
          ? this.premiumExpiresAt
          : premiumExpiresAt as DateTime?,
      founderCohort: identical(founderCohort, _unset)
          ? this.founderCohort
          : founderCohort as String?,
      founderNumber: identical(founderNumber, _unset)
          ? this.founderNumber
          : founderNumber as int?,
      founderFirstYearDiscountPercent:
          founderFirstYearDiscountPercent ??
          this.founderFirstYearDiscountPercent,
      founderEarlyFeatureAccess:
          founderEarlyFeatureAccess ?? this.founderEarlyFeatureAccess,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      accessVerifiedAt: identical(accessVerifiedAt, _unset)
          ? this.accessVerifiedAt
          : accessVerifiedAt as DateTime?,
      offlineAccessUntil: identical(offlineAccessUntil, _unset)
          ? this.offlineAccessUntil
          : offlineAccessUntil as DateTime?,
      accessLastSeenAt: identical(accessLastSeenAt, _unset)
          ? this.accessLastSeenAt
          : accessLastSeenAt as DateTime?,
      earlyAccessEnabled: earlyAccessEnabled ?? this.earlyAccessEnabled,
      earlyAccessDurationDays:
          earlyAccessDurationDays ?? this.earlyAccessDurationDays,
      earlyAccessCutoffAt: identical(earlyAccessCutoffAt, _unset)
          ? this.earlyAccessCutoffAt
          : earlyAccessCutoffAt as DateTime?,
      premiumBillingEnabled:
          premiumBillingEnabled ?? this.premiumBillingEnabled,
      premiumMessageTitle: identical(premiumMessageTitle, _unset)
          ? this.premiumMessageTitle
          : premiumMessageTitle as String?,
      premiumMessageBody: identical(premiumMessageBody, _unset)
          ? this.premiumMessageBody
          : premiumMessageBody as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'installationId': installationId,
      'plan': plan.name,
      'isEarlyUser': isEarlyUser,
      'trialStartAtIso': trialStartAt?.toIso8601String(),
      'trialEndsAtIso': trialEndsAt?.toIso8601String(),
      'premiumStartedAtIso': premiumStartedAt?.toIso8601String(),
      'premiumExpiresAtIso': premiumExpiresAt?.toIso8601String(),
      'hasUsedTrial': hasUsedTrial,
      'founderCohort': founderCohort,
      'founderNumber': founderNumber,
      'founderFirstYearDiscountPercent': founderFirstYearDiscountPercent,
      'founderEarlyFeatureAccess': founderEarlyFeatureAccess,
      'createdAtIso': createdAt.toIso8601String(),
      'updatedAtIso': updatedAt.toIso8601String(),
      'accessVerifiedAtIso': accessVerifiedAt?.toIso8601String(),
      'offlineAccessUntilIso': offlineAccessUntil?.toIso8601String(),
      'accessLastSeenAtIso': accessLastSeenAt?.toIso8601String(),
      'earlyAccessEnabled': earlyAccessEnabled,
      'earlyAccessDurationDays': earlyAccessDurationDays,
      'earlyAccessCutoffAtIso': earlyAccessCutoffAt?.toIso8601String(),
      'premiumBillingEnabled': premiumBillingEnabled,
      'premiumMessageTitle': premiumMessageTitle,
      'premiumMessageBody': premiumMessageBody,
    };
  }

  factory AccessState.fromJson(Map<String, dynamic> json) {
    RipotPlan parsePlan(String? raw) {
      return RipotPlan.values.firstWhere(
        (e) => e.name == raw,
        orElse: () => RipotPlan.free,
      );
    }

    final installationId = (json['installationId'] as String?) ?? '';
    final createdAt =
        DateTime.tryParse((json['createdAtIso'] as String?) ?? '') ??
        DateTime.now();
    final updatedAt =
        DateTime.tryParse((json['updatedAtIso'] as String?) ?? '') ?? createdAt;

    return AccessState(
      installationId: installationId,
      plan: parsePlan(json['plan'] as String?),
      isEarlyUser: (json['isEarlyUser'] as bool?) ?? false,
      trialStartAt: DateTime.tryParse(
        (json['trialStartAtIso'] as String?) ?? '',
      ),
      trialEndsAt: DateTime.tryParse((json['trialEndsAtIso'] as String?) ?? ''),
      premiumStartedAt: DateTime.tryParse(
        (json['premiumStartedAtIso'] as String?) ?? '',
      ),
      hasUsedTrial: (json['hasUsedTrial'] as bool?) ?? false,
      premiumExpiresAt: DateTime.tryParse(
        (json['premiumExpiresAtIso'] as String?) ?? '',
      ),
      founderCohort: json['founderCohort'] as String?,
      founderNumber: _nullableIntFromJson(json['founderNumber']),
      founderFirstYearDiscountPercent: _intFromJson(
        json['founderFirstYearDiscountPercent'],
        fallback: 0,
      ),
      founderEarlyFeatureAccess:
          (json['founderEarlyFeatureAccess'] as bool?) ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
      accessVerifiedAt: DateTime.tryParse(
        (json['accessVerifiedAtIso'] as String?) ?? '',
      ),
      offlineAccessUntil: DateTime.tryParse(
        (json['offlineAccessUntilIso'] as String?) ?? '',
      ),
      accessLastSeenAt: DateTime.tryParse(
        (json['accessLastSeenAtIso'] as String?) ?? '',
      ),
      earlyAccessEnabled: (json['earlyAccessEnabled'] as bool?) ?? false,
      earlyAccessDurationDays: _intFromJson(
        json['earlyAccessDurationDays'],
        fallback: defaultEarlyAccessDurationDays,
      ),
      earlyAccessCutoffAt: DateTime.tryParse(
        (json['earlyAccessCutoffAtIso'] as String?) ?? '',
      ),
      premiumBillingEnabled: (json['premiumBillingEnabled'] as bool?) ?? false,
      premiumMessageTitle: json['premiumMessageTitle'] as String?,
      premiumMessageBody: json['premiumMessageBody'] as String?,
    );
  }
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

String _dateOnly(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

const Object _unset = Object();
