import 'package:flutter/foundation.dart';

enum RipotPlan { free, trial, premium }

@immutable
class AccessState {
  final String installationId;
  final RipotPlan plan;
  final bool isEarlyUser;
  final DateTime? trialStartAt;
  final DateTime? trialEndsAt;
  final DateTime? premiumStartedAt;
  final bool hasUsedTrial;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccessState({
    required this.installationId,
    required this.plan,
    required this.isEarlyUser,
    required this.createdAt,
    required this.updatedAt,
    this.trialStartAt,
    this.trialEndsAt,
    this.premiumStartedAt,
    this.hasUsedTrial = false,
  });

  factory AccessState.initial({required String installationId, bool isEarlyUser = true}) {
    final now = DateTime.now();
    return AccessState(
      installationId: installationId,
      plan: RipotPlan.free,
      isEarlyUser: isEarlyUser,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool get isTrialActive {
    if (plan != RipotPlan.trial) return false;
    final endsAt = trialEndsAt;
    if (endsAt == null) return false;
    return DateTime.now().isBefore(endsAt);
  }

  bool get isPremiumLike => plan == RipotPlan.premium || isTrialActive;

  int get maxSavedReports => isPremiumLike ? 100 : 10;
  int get maxSavedTemplates => isPremiumLike ? 20 : 3;
  int get maxImagesPerReport => isPremiumLike ? 12 : 4;

  bool get canRemoveBranding => isPremiumLike;
  bool get canUseImageLabels => isPremiumLike;
  bool get canUseLetterhead => isPremiumLike;
  bool get canUseCustomMargins => isPremiumLike;
  bool get canUseAdvancedLayout => isPremiumLike;
  bool get canUsePremiumTemplates => isPremiumLike;

  String get badgeLabel {
    switch (plan) {
      case RipotPlan.free:
        return 'Free';
      case RipotPlan.trial:
        return isTrialActive ? 'Premium Trial' : 'Free';
      case RipotPlan.premium:
        return 'Premium';
    }
  }

  int get trialLengthDays => isEarlyUser ? 21 : 7;

  AccessState copyWith({
    RipotPlan? plan,
    bool? isEarlyUser,
    Object? trialStartAt = _unset,
    Object? trialEndsAt = _unset,
    Object? premiumStartedAt = _unset,
    bool? hasUsedTrial,
    DateTime? updatedAt,
  }) {
    return AccessState(
      installationId: installationId,
      plan: plan ?? this.plan,
      isEarlyUser: isEarlyUser ?? this.isEarlyUser,
      trialStartAt: identical(trialStartAt, _unset) ? this.trialStartAt : trialStartAt as DateTime?,
      trialEndsAt: identical(trialEndsAt, _unset) ? this.trialEndsAt : trialEndsAt as DateTime?,
      premiumStartedAt: identical(premiumStartedAt, _unset)
          ? this.premiumStartedAt
          : premiumStartedAt as DateTime?,
      hasUsedTrial: hasUsedTrial ?? this.hasUsedTrial,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      'hasUsedTrial': hasUsedTrial,
      'createdAtIso': createdAt.toIso8601String(),
      'updatedAtIso': updatedAt.toIso8601String(),
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
    final createdAt = DateTime.tryParse((json['createdAtIso'] as String?) ?? '') ?? DateTime.now();
    final updatedAt = DateTime.tryParse((json['updatedAtIso'] as String?) ?? '') ?? createdAt;

    return AccessState(
      installationId: installationId,
      plan: parsePlan(json['plan'] as String?),
      isEarlyUser: (json['isEarlyUser'] as bool?) ?? false,
      trialStartAt: DateTime.tryParse((json['trialStartAtIso'] as String?) ?? ''),
      trialEndsAt: DateTime.tryParse((json['trialEndsAtIso'] as String?) ?? ''),
      premiumStartedAt: DateTime.tryParse((json['premiumStartedAtIso'] as String?) ?? ''),
      hasUsedTrial: (json['hasUsedTrial'] as bool?) ?? false,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

const Object _unset = Object();
